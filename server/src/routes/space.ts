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
    include: { user: { select: { id: true, email: true, nickname: true, avatarPath: true } } },
  });

  return res.json({
    id: space.id,
    inviteCode: space.inviteCode,
    startDate: space.startDate,
    customDates: space.customDates ?? [],
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

// POST /api/space/transfer —— 转让空间给另一位成员（仅 owner）
const transferSchema = z.object({
  userId: z.string(),
});

router.post('/transfer', async (req, res) => {
  const parsed = transferSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: '参数错误' });

  const space = await getMySpace(req.userId!);
  if (!space) return res.status(404).json({ error: '还没有空间' });

  const me = await prisma.spaceMember.findUnique({
    where: { spaceId_userId: { spaceId: space.id, userId: req.userId! } },
  });
  if (!me || me.role !== 'owner') {
    return res.status(403).json({ error: '只有空间创建者可以转让' });
  }

  const target = await prisma.spaceMember.findUnique({
    where: { spaceId_userId: { spaceId: space.id, userId: parsed.data.userId } },
  });
  if (!target) return res.status(404).json({ error: '目标用户不在这个空间里' });
  if (target.userId === req.userId) return res.status(400).json({ error: '不能转让给自己' });

  await prisma.$transaction([
    prisma.spaceMember.update({
      where: { spaceId_userId: { spaceId: space.id, userId: req.userId! } },
      data: { role: 'member' },
    }),
    prisma.spaceMember.update({
      where: { spaceId_userId: { spaceId: space.id, userId: parsed.data.userId } },
      data: { role: 'owner' },
    }),
  ]);

  return res.json({ ok: true });
});

// PUT /api/space/start-date —— 设置/修改“在一起日期”（可清空）
const startDateSchema = z.object({
  startDate: z.string().nullable().optional(),
});

router.put('/start-date', async (req, res) => {
  const parsed = startDateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: '参数错误' });

  const space = await getMySpace(req.userId!);
  if (!space) return res.status(404).json({ error: '还没有空间' });

  let startDate: Date | null = null;
  if (parsed.data.startDate) {
    const d = new Date(parsed.data.startDate);
    if (Number.isNaN(d.getTime())) return res.status(400).json({ error: '日期格式不正确' });
    startDate = d;
  }

  const updated = await prisma.space.update({ where: { id: space.id }, data: { startDate } });
  return res.json({ startDate: updated.startDate });
});

// PUT /api/space/custom-dates —— 覆盖保存 DIY 纪念日（生日/毕业日等，每年提醒）
const customDatesSchema = z.object({
  customDates: z
    .array(
      z.object({
        name: z.string().min(1).max(20),
        month: z.number().int().min(1).max(12),
        day: z.number().int().min(1).max(31),
        // 归属：ownerId = 用户 id（自己的）；null/缺省 = 共同的
        ownerId: z.string().nullable().optional(),
      }),
    )
    .max(20),
});

router.put('/custom-dates', async (req, res) => {
  const parsed = customDatesSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: '参数格式不正确' });

  const space = await getMySpace(req.userId!);
  if (!space) return res.status(404).json({ error: '还没有空间' });

  const updated = await prisma.space.update({
    where: { id: space.id },
    data: { customDates: parsed.data.customDates as unknown as object },
  });
  return res.json({ customDates: updated.customDates ?? [] });
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

  // 用户注册时自动创建了自己的空间；加入对方空间前，先清理自己的空空间（无事件记录才允许）
  const mine = await prisma.spaceMember.findMany({
    where: { userId: req.userId! },
    include: { space: { include: { events: { select: { id: true } } } } },
  });
  for (const m of mine) {
    if (m.space.events.length > 0) {
      return res.status(409).json({
        error: '你已有自己的记录，无法加入对方空间（可先把记录导出备份）',
      });
    }
  }
  if (mine.length > 0) {
    await prisma.$transaction(async (tx) => {
      for (const m of mine) {
        await tx.spaceMember.deleteMany({ where: { spaceId: m.spaceId } });
        await tx.aiConfig.deleteMany({ where: { spaceId: m.spaceId } });
        await tx.space.delete({ where: { id: m.spaceId } });
      }
    });
  }

  await prisma.spaceMember.create({
    data: { spaceId: space.id, userId: req.userId!, role: 'member' },
  });

  return res.json({ ok: true, spaceId: space.id });
});

export default router;
