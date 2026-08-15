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
      customPrompt: cfg.customPrompt,
      hasApiKey: true,
      apiKeyMasked: maskKey(cfg.apiKey),
    },
  });
});

const aiSchema = z.object({
  baseUrl: z.string().url('Base URL 格式不正确'),
  apiKey: z.string().min(1, 'API Key 不能为空'),
  model: z.string().min(1, '模型名不能为空'),
  style: z.enum(['warm', 'literary']).default('warm'),
  customPrompt: z.string().max(2000).optional(), // 非空时替换默认 system prompt
});

// PUT /api/settings/ai —— 保存 AI 配置（空间级共享）
router.put('/ai', async (req, res) => {
  const spaceId = await mySpaceId(req.userId!);
  if (!spaceId) return res.status(404).json({ error: '还没有空间' });

  const parsed = aiSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: '参数错误', details: parsed.error.flatten() });
  }

  const data = {
    baseUrl: parsed.data.baseUrl,
    apiKey: parsed.data.apiKey,
    model: parsed.data.model,
    style: parsed.data.style,
    customPrompt: parsed.data.customPrompt?.trim() || null,
  };

  const cfg = await prisma.aiConfig.upsert({
    where: { spaceId },
    create: { spaceId, ...data },
    update: data,
  });

  return res.json({
    aiConfig: { baseUrl: cfg.baseUrl, model: cfg.model, style: cfg.style, hasApiKey: true },
  });
});

export default router;
