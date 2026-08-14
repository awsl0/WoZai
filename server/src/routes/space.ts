import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';

const router = Router();

/** 取当前用户所在空间（用户只属于一个空间，取第一个） */
async function getMySpace(userId: string) {
  const membership = await prisma.spaceMember.findFirst({
    where: { userId },
    include: { space: { include: { members: true } } },
  });
  return membership?.space ?? null;
}

// GET /api/space —— 我的空间（含成员）
router.get('/', async (req, res) => {
  const space = await getMySpace(req.userId!);
  if (!space) return res.status(404).json({ error: '还没有空间' });

  const members = await prisma.spaceMember.findMany({
    where: { spaceId: space.id },
    include: { user: { select: { id: true, email: true, nickname: true } } },
  });

  return res.json({
    id: space.id,
    inviteCode: space.inviteCode,
    startDate: space.startDate,
    members: members.map((m) => ({ id: m.id, role: m.role, user: m.user })),
  });
});

// POST /api/space/invite —— 重新生成邀请码（仅 owner）
router.post('/invite', async (req, res) => {
  const space = await getMySpace(req.userId!);
  if (!space) return res.status(404).json({ error: '还没有空间' });

  const me = await prisma.spaceMember.findUnique({
    where: { spaceId_userId: { spaceId: space.id, userId: req.userId! } },
  });
  if (!me || me.role !== 'owner') {
    return res.status(403).json({ error: '只有空间创建者可以生成邀请码' });
  }

  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 6; i++) code += chars[Math.floor(Math.random() * chars.length)];

  const updated = await prisma.space.update({ where: { id: space.id }, data: { inviteCode: code } });
  return res.json({ inviteCode: updated.inviteCode });
});

const joinSchema = z.object({
  inviteCode: z.string().length(6),
});

// POST /api/space/join —— 通过邀请码加入（空间上限 2 人）
router.post('/join', async (req, res) => {
  const parsed = joinSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: '邀请码格式不正确' });

  const space = await prisma.space.findUnique({
    where: { inviteCode: parsed.data.inviteCode.toUpperCase() },
    include: { members: true },
  });
  if (!space) return res.status(404).json({ error: '邀请码无效' });

  const memberCount = space.members.length;
  if (memberCount >= 2) return res.status(409).json({ error: '这个空间已经有两个人了' });

  const alreadyIn = space.members.some((m) => m.userId === req.userId);
  if (alreadyIn) return res.status(409).json({ error: '你已经在空间里了' });

  await prisma.spaceMember.create({
    data: { spaceId: space.id, userId: req.userId!, role: 'member' },
  });

  return res.json({ ok: true, spaceId: space.id });
});

export default router;
