import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';
import { JWT_SECRET, auth } from '../middleware/auth.js';

const router = Router();

function signToken(userId: string): string {
  return jwt.sign({ sub: userId }, JWT_SECRET, { expiresIn: '30d' });
}

/** 6 位邀请码：去易混淆字符 */
function generateInviteCode(): string {
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += chars[Math.floor(Math.random() * chars.length)];
  }
  return code;
}

const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6, '密码至少 6 位'),
  nickname: z.string().max(30).optional(),
});

// POST /api/auth/register —— 注册并自动创建个人空间（单人模式，可后续邀请另一半）
router.post('/register', async (req, res) => {
  const parsed = registerSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: '参数错误', details: parsed.error.flatten() });
  }
  const { email, password, nickname } = parsed.data;

  const exists = await prisma.user.findUnique({ where: { email } });
  if (exists) return res.status(409).json({ error: '该邮箱已被注册' });

  const passwordHash = await bcrypt.hash(password, 10);

  const { user, space } = await prisma.$transaction(async (tx) => {
    const u = await tx.user.create({ data: { email, passwordHash, nickname } });
    const s = await tx.space.create({
      data: {
        inviteCode: generateInviteCode(),
        createdBy: u.id,
        members: { create: { userId: u.id, role: 'owner' } },
      },
    });
    return { user: u, space: s };
  });

  return res.status(201).json({
    token: signToken(user.id),
    user: { id: user.id, email, nickname: user.nickname },
    space: { id: space.id, inviteCode: space.inviteCode },
  });
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string(),
});

// POST /api/auth/login
router.post('/login', async (req, res) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: '参数错误' });
  }
  const { email, password } = parsed.data;

  const user = await prisma.user.findUnique({ where: { email } });
  if (!user || !(await bcrypt.compare(password, user.passwordHash))) {
    return res.status(401).json({ error: '邮箱或密码错误' });
  }

  return res.json({
    token: signToken(user.id),
    user: { id: user.id, email, nickname: user.nickname },
  });
});

// GET /api/auth/me —— 当前用户 + 所在空间
router.get('/me', auth, async (req, res) => {
  const user = await prisma.user.findUnique({
    where: { id: req.userId },
    include: {
      memberships: {
        include: {
          space: {
            include: {
              members: { include: { user: { select: { id: true, nickname: true, email: true } } } },
            },
          },
        },
      },
    },
  });
  if (!user) return res.status(404).json({ error: '用户不存在' });

  const membership = user.memberships[0];
  return res.json({
    user: { id: user.id, email: user.email, nickname: user.nickname, avatarPath: user.avatarPath },
    space: membership
      ? {
          id: membership.space.id,
          inviteCode: membership.space.inviteCode,
          startDate: membership.space.startDate,
          members: membership.space.members.map((m) => ({
            id: m.id,
            role: m.role,
            user: m.user,
          })),
        }
      : null,
  });
});

export default router;
