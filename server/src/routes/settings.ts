import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';

const router = Router();

async function mySpaceId(userId: string): Promise<string | null> {
  const m = await prisma.spaceMember.findFirst({ where: { userId } });
  return m?.spaceId ?? null;
}

function maskKey(key: string): string {
  if (key.length <= 8) return '****';
  return key.slice(0, 4) + '****' + key.slice(-4);
}

// GET /api/settings/ai —— 读取 AI 配置（key 脱敏）
router.get('/ai', async (req, res) => {
  const spaceId = await mySpaceId(req.userId!);
  if (!spaceId) return res.status(404).json({ error: '还没有空间' });

  const cfg = await prisma.aiConfig.findUnique({ where: { spaceId } });
  if (!cfg) return res.json({ aiConfig: null });

  return res.json({
    aiConfig: {
      baseUrl: cfg.baseUrl,
      model: cfg.model,
      style: cfg.style,
      styles: (cfg.styles as { name: string; prompt: string }[] | null) ?? [],
      hasApiKey: true,
      apiKeyMasked: maskKey(cfg.apiKey),
    },
  });
});

const styleItemSchema = z.object({
  name: z.string().min(1, '文风名字不能为空').max(30),
  prompt: z.string().min(1, '提示词不能为空').max(2000),
});

const aiSchema = z.object({
  baseUrl: z.string().url('Base URL 格式不正确'),
  apiKey: z.string().min(1, 'API Key 不能为空'),
  model: z.string().min(1, '模型名不能为空'),
  style: z.string().max(50).optional(),
  styles: z.array(styleItemSchema).max(10).optional(), // 自定义文风列表
});

// PUT /api/settings/ai —— 保存 AI 配置（空间级共享）
router.put('/ai', async (req, res) => {
  const spaceId = await mySpaceId(req.userId!);
  if (!spaceId) return res.status(404).json({ error: '还没有空间' });

  const parsed = aiSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: '参数错误', details: parsed.error.flatten() });
  }

  const data: Record<string, unknown> = {
    baseUrl: parsed.data.baseUrl,
    apiKey: parsed.data.apiKey,
    model: parsed.data.model,
  };
  if (parsed.data.style !== undefined) data.style = parsed.data.style;
  if (parsed.data.styles !== undefined) data.styles = parsed.data.styles;

  const cfg = await prisma.aiConfig.upsert({
    where: { spaceId },
    create: {
      spaceId,
      baseUrl: parsed.data.baseUrl,
      apiKey: parsed.data.apiKey,
      model: parsed.data.model,
      style: parsed.data.style ?? '温暖',
      styles: parsed.data.styles,
    },
    update: data,
  });

  return res.json({
    aiConfig: { baseUrl: cfg.baseUrl, model: cfg.model, style: cfg.style, hasApiKey: true },
  });
});

export default router;
