import { Router } from 'express';
import multer from 'multer';
import crypto from 'node:crypto';
import path from 'node:path';
import fs from 'node:fs';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';
import { generateDiary } from '../lib/ai.js';

const router = Router();

// ---- 照片上传（本地磁盘，uploads/ 已在 .gitignore） ----
fs.mkdirSync('uploads', { recursive: true });

const upload = multer({
  storage: multer.diskStorage({
    destination: 'uploads/',
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname).toLowerCase() || '.jpg';
      cb(null, `${Date.now()}-${crypto.randomUUID()}${ext}`);
    },
  }),
  limits: { fileSize: 8 * 1024 * 1024 }, // 单张 8MB（客户端会压缩到 ~500KB）
});

// ---- 工具 ----
async function mySpaceId(userId: string): Promise<string | null> {
  const m = await prisma.spaceMember.findFirst({ where: { userId } });
  return m?.spaceId ?? null;
}

/** 校验事件属于当前用户所在空间 */
async function getOwnedEvent(userId: string, eventId: string) {
  const spaceId = await mySpaceId(userId);
  if (!spaceId) return null;
  return prisma.event.findFirst({
    where: { id: eventId, spaceId },
    include: { photos: true },
  });
}

// ---- 创建事件：multipart/form-data（happenedAt, lat?, lng?, locationName?, note?, photos[]≤9） ----
router.post('/', upload.array('photos', 9), async (req, res) => {
  const spaceId = await mySpaceId(req.userId!);
  if (!spaceId) return res.status(404).json({ error: '还没有空间' });

  const body = req.body as Record<string, string>;
  const happenedAt = body.happenedAt ? new Date(body.happenedAt) : new Date();
  if (Number.isNaN(happenedAt.getTime())) {
    return res.status(400).json({ error: 'happenedAt 格式不正确' });
  }

  const files = (req.files as Express.Multer.File[]) ?? [];
  const event = await prisma.event.create({
    data: {
      spaceId,
      authorId: req.userId!,
      happenedAt,
      lat: body.lat ? Number(body.lat) : null,
      lng: body.lng ? Number(body.lng) : null,
      locationName: body.locationName || null,
      note: body.note || null,
      photos: { create: files.map((f) => ({ filePath: f.path.replace(/\\/g, '/') })) },
    },
    include: { photos: true },
  });
  return res.status(201).json({ event });
});

// ---- 事件列表（时间线，倒序） ----
router.get('/', async (req, res) => {
  const spaceId = await mySpaceId(req.userId!);
  if (!spaceId) return res.status(404).json({ error: '还没有空间' });

  const events = await prisma.event.findMany({
    where: { spaceId },
    include: {
      photos: true,
      author: { select: { id: true, nickname: true } },
    },
    orderBy: { happenedAt: 'desc' },
  });
  return res.json({ events });
});

// ---- 事件详情 ----
router.get('/:id', async (req, res) => {
  const event = await getOwnedEvent(req.userId!, req.params.id);
  if (!event) return res.status(404).json({ error: '事件不存在' });
  return res.json({ event });
});

const updateSchema = z.object({
  content: z.string().max(5000).optional(),
  happenedAt: z.string().optional(),
  locationName: z.string().max(200).nullable().optional(),
  note: z.string().max(500).nullable().optional(),
  lat: z.number().nullable().optional(),
  lng: z.number().nullable().optional(),
});

// ---- 编辑事件（用户手动改正文时置 editedByUser=true） ----
router.put('/:id', async (req, res) => {
  const event = await getOwnedEvent(req.userId!, req.params.id);
  if (!event) return res.status(404).json({ error: '事件不存在' });

  const parsed = updateSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: '参数错误', details: parsed.error.flatten() });
  }

  const data: Record<string, unknown> = {};
  if (parsed.data.content !== undefined) {
    data.content = parsed.data.content;
    data.editedByUser = true; // 用户编辑过，不再标记为纯 AI 原文
  }
  if (parsed.data.happenedAt !== undefined) data.happenedAt = new Date(parsed.data.happenedAt);
  if (parsed.data.locationName !== undefined) data.locationName = parsed.data.locationName;
  if (parsed.data.note !== undefined) data.note = parsed.data.note;
  if (parsed.data.lat !== undefined) data.lat = parsed.data.lat;
  if (parsed.data.lng !== undefined) data.lng = parsed.data.lng;

  const updated = await prisma.event.update({
    where: { id: event.id },
    data,
    include: { photos: true },
  });
  return res.json({ event: updated });
});

// ---- 删除事件（连同照片文件） ----
router.delete('/:id', async (req, res) => {
  const event = await getOwnedEvent(req.userId!, req.params.id);
  if (!event) return res.status(404).json({ error: '事件不存在' });

  for (const p of event.photos) {
    fs.unlink(p.filePath, () => {});
  }
  await prisma.event.delete({ where: { id: event.id } });
  return res.json({ ok: true });
});

// ---- AI 生成日记：POST /api/events/:id/generate ----
const generateSchema = z.object({
  style: z.enum(['warm', 'literary']).optional(),
});

router.post('/:id/generate', async (req, res) => {
  const event = await getOwnedEvent(req.userId!, req.params.id);
  if (!event) return res.status(404).json({ error: '事件不存在' });

  const aiConfig = await prisma.aiConfig.findUnique({ where: { spaceId: event.spaceId } });
  if (!aiConfig) return res.status(400).json({ error: '请先在设置中配置 AI（Base URL / API Key / 模型）' });

  if (event.photos.length === 0) {
    return res.status(400).json({ error: '这个事件没有照片，无法看图生成' });
  }

  const parsed = generateSchema.safeParse(req.body ?? {});
  const style = parsed.success && parsed.data.style ? parsed.data.style : aiConfig.style;

  const memberCount = await prisma.spaceMember.count({ where: { spaceId: event.spaceId } });

  try {
    const content = await generateDiary(
      { baseUrl: aiConfig.baseUrl, apiKey: aiConfig.apiKey, model: aiConfig.model, style },
      {
        happenedAt: event.happenedAt,
        locationName: event.locationName,
        note: event.note,
        photoPaths: event.photos.map((p) => p.filePath),
        perspective: memberCount > 1 ? 'couple' : 'solo',
      },
    );

    const updated = await prisma.event.update({
      where: { id: event.id },
      data: { content, isAiGenerated: true, editedByUser: false },
      include: { photos: true },
    });
    return res.json({ event: updated });
  } catch (err) {
    const msg = err instanceof Error ? err.message : '生成失败';
    return res.status(502).json({ error: msg });
  }
});

export default router;
