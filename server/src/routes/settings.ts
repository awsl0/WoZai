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
      maxWaitSeconds: cfg.maxWaitSeconds,
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
  // apiKey 可选：不传/为空 = 保留已保存的 key（避免前端把脱敏值写回）
  apiKey: z.string().min(1, 'API Key 不能为空').optional(),
  model: z.string().min(1, '模型名不能为空'),
  style: z.string().max(50).optional(),
  styles: z.array(styleItemSchema).max(10).optional(), // 自定义文风列表
  maxWaitSeconds: z.number().int().min(30).max(600).optional(), // 最大生成等待时间（秒）30~600
});

// PUT /api/settings/ai —— 保存 AI 配置（空间级共享）
router.put('/ai', async (req, res) => {
  const spaceId = await mySpaceId(req.userId!);
  if (!spaceId) return res.status(404).json({ error: '还没有空间' });

  const parsed = aiSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: '参数错误', details: parsed.error.flatten() });
  }

  // 首次创建（还没有配置）时必须提供 apiKey
  const existing = await prisma.aiConfig.findUnique({ where: { spaceId } });
  const newKey = parsed.data.apiKey?.trim();
  if (!existing && !newKey) {
    return res.status(400).json({ error: '请填写 API Key' });
  }

  const data: Record<string, unknown> = {
    baseUrl: parsed.data.baseUrl,
    model: parsed.data.model,
  };
  // 只有用户真正填写了新 key 才覆盖（前端未改时不传）
  if (newKey) data.apiKey = newKey;
  if (parsed.data.style !== undefined) data.style = parsed.data.style;
  if (parsed.data.styles !== undefined) data.styles = parsed.data.styles;
  if (parsed.data.maxWaitSeconds !== undefined) data.maxWaitSeconds = parsed.data.maxWaitSeconds;

  const cfg = await prisma.aiConfig.upsert({
    where: { spaceId },
    create: {
      spaceId,
      baseUrl: parsed.data.baseUrl,
      // upsert 会校验 create 分支：existing 存在时走 update，这里给个非空兑底即可
      apiKey: newKey ?? '',
      model: parsed.data.model,
      style: parsed.data.style ?? '温暖',
      styles: parsed.data.styles,
      maxWaitSeconds: parsed.data.maxWaitSeconds ?? 240,
    },
    update: data,
  });

  return res.json({
    aiConfig: { baseUrl: cfg.baseUrl, model: cfg.model, style: cfg.style, hasApiKey: true },
  });
});

// POST /api/settings/ai/test —— 测试 AI 配置是否可用
// body 可选传 baseUrl/apiKey/model（前端表单临时值，未传则用已保存配置）
router.post('/ai/test', async (req, res) => {
  const spaceId = await mySpaceId(req.userId!);
  if (!spaceId) return res.status(404).json({ error: '还没有空间' });

  const body = (req.body ?? {}) as { baseUrl?: string; apiKey?: string; model?: string };
  let baseUrl = body.baseUrl?.trim();
  let apiKey = body.apiKey?.trim();
  let model = body.model?.trim();

  if (!baseUrl || !apiKey || !model) {
    const cfg = await prisma.aiConfig.findUnique({ where: { spaceId } });
    baseUrl = baseUrl || cfg?.baseUrl || '';
    apiKey = apiKey || cfg?.apiKey || '';
    model = model || cfg?.model || '';
  }
  if (!baseUrl || !apiKey || !model) {
    return res.status(400).json({ ok: false, error: '请先填写 AI 配置' });
  }

  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 20000);
    const r = await fetch(`${baseUrl.replace(/\/+$/, '')}/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}` },
      body: JSON.stringify({
        model,
        messages: [{ role: 'user', content: '请只回复两个字：正常' }],
        max_tokens: 256,
      }),
      signal: controller.signal,
    });
    clearTimeout(timer);
    if (!r.ok) {
      const t = await r.text().catch(() => '');
      return res.json({ ok: false, error: `HTTP ${r.status}: ${t.slice(0, 200)}` });
    }
    const data = (await r.json()) as { choices?: { message?: { content?: string } }[]; model?: string };
    const content = data.choices?.[0]?.message?.content;
    if (!content) return res.json({ ok: false, error: '返回内容为空' });
    return res.json({ ok: true, model: data.model ?? model, reply: content.trim().slice(0, 50) });
  } catch (e) {
    const err = e as Error & { name?: string };
    return res.json({
      ok: false,
      error: err?.name === 'AbortError' ? '请求超时（20 秒）' : `连接失败: ${err?.message ?? e}`,
    });
  }
});

export default router;
