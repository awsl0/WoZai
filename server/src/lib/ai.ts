import { readFile } from 'node:fs/promises';
import path from 'node:path';

export type DiaryStyle = 'warm' | 'literary';

export interface AiConfigData {
  baseUrl: string;
  apiKey: string;
  model: string;
  style: string;
  /** 用户自定义 system prompt（非空时替换默认） */
  customPrompt?: string | null;
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

const STYLE_RULE: Record<DiaryStyle, string> = {
  warm: '自然、口语化、有温度',
  literary: '文艺抒情，多用意象与细腻描写，句子更有美感',
};

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
 * 调用 OpenAI 兼容的多模态模型，根据照片+时间+地点+备注生成日记。
 * 幻觉约束见 product-design.md §6.2：
 *  - 只描述照片可见事实，推测用不确定语气，缺失信息不编造。
 */
export async function generateDiary(cfg: AiConfigData, ctx: GenerateContext): Promise<string> {
  const style: DiaryStyle = cfg.style === 'literary' ? 'literary' : 'warm';
  const pronoun = ctx.perspective === 'couple' ? '我们' : '我';

  // 用户自定义提示词：非空时完全替换默认 system prompt
  const system = cfg.customPrompt?.trim()
    ? cfg.customPrompt.trim()
    : [
        '你是「WoZai」的日记助手，根据用户提供的照片、时间、地点和备注，写一段温暖的日记。',
        '规则：',
        '1. 只描述照片中可见的事实，以及用户提供的时间、地点；照片里看不到的信息不得写成事实。',
        '2. 对心情、动机的推测必须使用"大概、也许、好像"等不确定语气。',
        '3. 时间或地点缺失时直接跳过，绝不编造。',
        '4. 用户没有备注时写 80~150 字的短记录；有备注时围绕备注扩写 150~300 字。',
        `5. 用第一人称"${pronoun}"。`,
        `6. 文风要求：${STYLE_RULE[style]}。`,
      ].join('\n');

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
    for (const p of ctx.photoPaths) {
      userContent.push({ type: 'image_url', image_url: { url: await fileToDataUrl(p) } });
    }
  }

  const baseUrl = cfg.baseUrl.replace(/\/+$/, '');
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
    }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => '');
    // 模型不支持图片输入时的友好提示
    if (res.status === 400 && /image|vision|multimodal|picture|图片|视觉/i.test(body)) {
      throw new Error('该模型可能不支持图片输入：可在生成时关闭「使用照片」，改为纯文本模式重试');
    }
    throw new Error(`AI 请求失败 (${res.status}): ${body.slice(0, 300)}`);
  }

  const data = (await res.json()) as { choices?: { message?: { content?: string } }[] };
  const content = data.choices?.[0]?.message?.content?.trim();
  if (!content) {
    const raw = JSON.stringify(data).slice(0, 200);
    throw new Error(`AI 返回内容为空（可能被截断或模型不支持该请求）：${raw}`);
  }
  return content;
}
