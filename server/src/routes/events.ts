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
  // 不允许记录未来时间（容差 5 分钟，应对客户端时钟偏差）
  if (happenedAt.getTime() > Date.now() + 5 * 60 * 1000) {
    return res.status(400).json({ error: '事件时间不能晚于当前时间' });
  }

  const files = (req.files as Express.Multer.File[]) ?? [];
  // 天气（前端按日期+地点调用 Open-Meteo 获取，JSON 字符串）
  let weather: unknown = null;
  if (body.weather) {
    try {
      const w = JSON.parse(body.weather) as Record<string, unknown>;
      if (w && typeof w.text === 'string') weather = w as never;
    } catch {
      // 天气格式错误则忽略
    }
  }
  const event = await prisma.event.create({
    data: {
      spaceId,
      authorId: req.userId!,
      happenedAt,
      lat: body.lat ? Number(body.lat) : null,
      lng: body.lng ? Number(body.lng) : null,
      locationName: body.locationName || null,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      weather: weather as any,
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
  // 编辑时按新时间/地点重新获取的天气（JSON 字符串或 null 清除）
  weather: z.string().nullable().optional(),
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
  if (parsed.data.happenedAt !== undefined) {
    const d = new Date(parsed.data.happenedAt);
    if (Number.isNaN(d.getTime())) {
      return res.status(400).json({ error: 'happenedAt 格式不正确' });
    }
    if (d.getTime() > Date.now() + 5 * 60 * 1000) {
      return res.status(400).json({ error: '事件时间不能晚于当前时间' });
    }
    data.happenedAt = d;
  }
  if (parsed.data.locationName !== undefined) data.locationName = parsed.data.locationName;
  if (parsed.data.note !== undefined) data.note = parsed.data.note;
  if (parsed.data.lat !== undefined) data.lat = parsed.data.lat;
  if (parsed.data.lng !== undefined) data.lng = parsed.data.lng;
  if (parsed.data.weather !== undefined) {
    if (parsed.data.weather === null || parsed.data.weather.trim() === '') {
      data.weather = null;
    } else {
      try {
        const w = JSON.parse(parsed.data.weather) as Record<string, unknown>;
        if (w && typeof w.text === 'string') data.weather = w as never;
      } catch {
        // 天气格式错误则忽略（保持原值）
      }
    }
  }

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
  // 先删照片记录再删事件（避免外键约束冲突）
  await prisma.photo.deleteMany({ where: { eventId: event.id } });
  await prisma.event.delete({ where: { id: event.id } });
  return res.json({ ok: true });
});

// ---- 追加照片：POST /api/events/:id/photos（上限合计 9 张） ----
router.post('/:id/photos', upload.array('photos', 9), async (req, res) => {
  const event = await getOwnedEvent(req.userId!, String(req.params.id));
  if (!event) return res.status(404).json({ error: '事件不存在' });

  const files = (req.files as Express.Multer.File[]) ?? [];
  if (files.length === 0) return res.status(400).json({ error: '没有收到照片文件' });
  if (event.photos.length + files.length > 9) {
    for (const f of files) fs.unlink(f.path, () => {});
    return res.status(400).json({ error: '每个事件最多 9 张照片' });
  }

  const photos = await prisma.$transaction(
    files.map((f) =>
      prisma.photo.create({ data: { eventId: event.id, filePath: f.path.replace(/\\/g, '/') } }),
    ),
  );
  return res.status(201).json({ photos });
});

// ---- 删除照片：DELETE /api/events/:id/photos/:photoId ----
router.delete('/:id/photos/:photoId', async (req, res) => {
  const event = await getOwnedEvent(req.userId!, req.params.id);
  if (!event) return res.status(404).json({ error: '事件不存在' });

  const photo = event.photos.find((p) => p.id === String(req.params.photoId));
  if (!photo) return res.status(404).json({ error: '照片不存在' });

  fs.unlink(photo.filePath, () => {});
  await prisma.photo.delete({ where: { id: photo.id } });
  return res.json({ ok: true });
});

// ---- AI 生成日记：POST /api/events/:id/generate ----
const generateSchema = z.object({
  style: z.string().max(50).optional(), // 文风名：内置（温暖/文艺/浪漫/简洁/痛苦）或自定义名
  usePhotos: z.boolean().optional(), // false = 纯文本模式（模型不支持图片时）
});

router.post('/:id/generate', async (req, res) => {
  const event = await getOwnedEvent(req.userId!, req.params.id);
  if (!event) return res.status(404).json({ error: '事件不存在' });

  const aiConfig = await prisma.aiConfig.findUnique({ where: { spaceId: event.spaceId } });
  if (!aiConfig) return res.status(400).json({ error: '请先在设置中配置 AI（Base URL / API Key / 模型）' });

  const parsed = generateSchema.safeParse(req.body ?? {});
  const style = parsed.success && parsed.data.style ? parsed.data.style : aiConfig.style;
  let usePhotos = parsed.success ? (parsed.data.usePhotos ?? true) : true;

  // 没照片时自动降级纯文本（不报错，UI 也不显示开关）
  if (event.photos.length === 0) {
    usePhotos = false;
  }

  const memberCount = await prisma.spaceMember.count({ where: { spaceId: event.spaceId } });

  try {
    const content = await generateDiary(
      { baseUrl: aiConfig.baseUrl, apiKey: aiConfig.apiKey, model: aiConfig.model, style },
      {
        happenedAt: event.happenedAt,
        locationName: event.locationName,
        note: event.note,
        photoPaths: usePhotos ? event.photos.map((p) => p.filePath) : [],
        usePhotos,
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
