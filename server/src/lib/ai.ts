import { readFile } from 'node:fs/promises';
import path from 'node:path';

/** 内置文风：名字 → 文风要求（幻觉约束规则在统一模板里带上） */
export const PRESET_STYLES: Record<string, string> = {
  温暖: '自然、口语化、有温度，像写给恋人的日常记录。',
  文艺: '文艺抒情，善用意象与细腻描写，句子更有美感，但不得因此编造画面。',
  浪漫: '浪漫甜蜜，聚焦两个人之间的温馨细节，用词温柔缱绻，但只写照片里真实存在的细节。',
  简洁: '极简记录，一两句话（20~60 字），信息密度高，不铺垫不抒情。',
  痛苦: '真实克制地记录难过、失落或低落的时刻，不强行美化，允许表达怀念与伤感，但不编造难过的原因。',
};

export interface AiConfigData {
  baseUrl: string;
  apiKey: string;
  model: string;
  /** 当前选中的文风名（内置名或自定义名） */
  style: string;
  /** 自定义文风列表 [{ name, prompt }] */
  styles?: { name: string; prompt: string }[];
}

export interface GenerateContext {
  happenedAt: Date;
  locationName: string | null;
  note: string | null;
  photoPaths: string[];
  /** false = 纯文本模式（模型不支持图片时降级用） */
  usePhotos: boolean;
  /** couple = 双人空间(用"我们")；solo = 单人空间(用"我") */
  perspective: 'couple' | 'solo';
}

function formatTime(d: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日 ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

async function fileToDataUrl(filePath: string): Promise<string> {
  const buf = await readFile(filePath);
  const ext = path.extname(filePath).toLowerCase();
  const mime = ext === '.png' ? 'image/png' : ext === '.webp' ? 'image/webp' : 'image/jpeg';
  return `data:${mime};base64,${buf.toString('base64')}`;
}

/**
 * 解析 system prompt：
 *  - 自定义文风：命中自定义列表里的名字 → 完全用用户提示词
 *  - 内置文风：名字 → 基础幻觉约束 + 文风要求
 *  - 未知名字 → 默认"温暖"
 */
function resolveSystemPrompt(style: string, styles: AiConfigData['styles'], pronoun: string): string {
  const custom = (styles ?? []).find((s) => s.name === style);
  // 自定义文风：完全交给用户自己的提示词，不加约束
  if (custom?.prompt?.trim()) return custom.prompt.trim();

  const rule = PRESET_STYLES[style] ?? PRESET_STYLES['温暖'];
  return [
    '你是「WoZai」的日记助手。用户会提供照片、时间、地点和备注，请根据这些写一段日记。严格遵守以下规则：',
    '',
    '【事实约束】',
    '1. 只能写照片中清晰可见的内容，以及用户明确提供的时间、地点、备注。',
    '2. 禁止编造：不得虚构人物、对话、具体事件、价格、名字等照片和输入里没有的信息。',
    '3. 对看不见但合理推测的内容，必须用"大概、也许、好像、隐约觉得"等不确定语气。',
    '',
    '【内容规则】',
    '4. 时间或地点缺失时直接跳过，不得自行补充或猜测。',
    '5. 用户没有备注时写 80~150 字；有备注时围绕备注扩写 150~300 字。',
    '',
    '【形式规则】',
    `6. 用第一人称"${pronoun}"，全文人称保持一致。`,
    '7. 直接输出日记正文：不要输出"时间：""地点："等前缀，不要用 markdown 符号、列表、编号或分段标题。',
    '',
    `【文风】8. ${rule}`,
  ].join('\n');
}

/**
 * 调用 OpenAI 兼容的多模态模型，根据照片+时间+地点+备注生成日记。
 * 幻觉约束见 product-design.md §6.2。
 */
export async function generateDiary(cfg: AiConfigData, ctx: GenerateContext): Promise<string> {
  const pronoun = ctx.perspective === 'couple' ? '我们' : '我';
  const system = resolveSystemPrompt(cfg.style, cfg.styles, pronoun);

  const text = [
    `时间：${formatTime(ctx.happenedAt)}`,
    `地点：${ctx.locationName ?? '未知'}`,
    `用户备注：${ctx.note ?? '无'}`,
    ctx.usePhotos && ctx.photoPaths.length > 0
      ? `照片共 ${ctx.photoPaths.length} 张：`
      : '（本次没有提供照片：请仅根据时间、地点和备注描述情景，不要编造具体画面）',
  ].join('\n');

  const userContent: unknown[] = [{ type: 'text', text }];
  if (ctx.usePhotos) {
    // 全部照片参与生成（用户要求，不限制数量）
    for (const p of ctx.photoPaths) {
      userContent.push({ type: 'image_url', image_url: { url: await fileToDataUrl(p) } });
    }
  }

  const baseUrl = cfg.baseUrl.replace(/\/+$/, '');
  const controller = new AbortController();
  // 超时随照片数增长：1 张≈80s，9 张≈240s（图片多 + 备注长时推理模型耗时显著增加）
  const timeoutMs = 60_000 + ctx.photoPaths.length * 20_000;
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  const res = await fetch(`${baseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${cfg.apiKey}`,
    },
    body: JSON.stringify({
      model: cfg.model,
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: userContent },
      ],
      temperature: 0.8,
      // 不限制输出长度：图片多/含标题描述时内容较长，交给模型自由输出，90s 超时兜底
    }),
    signal: controller.signal,
  });
  clearTimeout(timer);

  if (!res.ok) {
    const body = await res.text().catch(() => '');
    // 模型不支持图片输入时的友好提示
    if (res.status === 400 && /image|vision|multimodal|picture|图片|视觉/i.test(body)) {
      throw new Error('该模型可能不支持图片输入：可在生成时关闭「使用照片」，改为纯文本模式重试');
    }
    throw new Error(`AI 请求失败 (${res.status}): ${body.slice(0, 300)}`);
  }

  let data: {
    choices?: { message?: { content?: string; reasoning_content?: string }; finish_reason?: string }[];
  };
  try {
    data = (await res.json()) as typeof data;
  } catch (e) {
    throw new Error('AI 返回内容无法解析');
  }
  const choice = data.choices?.[0];
  const content = choice?.message?.content?.trim();
  if (!content) {
    const reasoning = (choice?.message?.reasoning_content ?? '').trim();
    const raw = JSON.stringify(data).slice(0, 200);
    if (choice?.finish_reason === 'length') {
      // 输出 token 被截断：通常因为推理模型思考过长，正文还没开始就被截断
      throw new Error(
        reasoning
          ? 'AI 思考过长导致输出被截断，请换用非推理模型（如 qwen3-plus 类）或减少照片数量后重试'
          : 'AI 输出被截断（超出长度限制），请重试或换一个模型',
      );
    }
    throw new Error(`AI 返回内容为空（可能被截断或模型不支持该请求）：${raw}`);
  }
  return content;
}
