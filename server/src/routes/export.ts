import { Router } from 'express';
import { ZipArchive } from 'archiver';
import fs from 'node:fs';
import path from 'node:path';
import { prisma } from '../lib/prisma.js';

const router = Router();

async function mySpaceId(userId: string): Promise<string | null> {
  const m = await prisma.spaceMember.findFirst({ where: { userId } });
  return m?.spaceId ?? null;
}

// GET /api/export —— 导出全部事件 + 照片为 ZIP（events.json + photos/）
router.get('/', async (req, res) => {
  const spaceId = await mySpaceId(req.userId!);
  if (!spaceId) return res.status(404).json({ error: '还没有空间' });

  const [space, events] = await Promise.all([
    prisma.space.findUnique({ where: { id: spaceId } }),
    prisma.event.findMany({
      where: { spaceId },
      include: { photos: true },
      orderBy: { happenedAt: 'asc' },
    }),
  ]);
  if (!space) return res.status(404).json({ error: '空间不存在' });

  const dateStr = new Date().toISOString().slice(0, 10);
  res.setHeader('Content-Type', 'application/zip');
  res.setHeader('Content-Disposition', `attachment; filename="wozai-export-${dateStr}.zip"`);

  const archive = new ZipArchive({ zlib: { level: 6 } });
  archive.on('error', (err: Error) => {
    console.error('导出失败:', err);
    res.status(500).end();
  });
  archive.pipe(res);

  const payload = {
    app: 'wozai',
    exportedAt: new Date().toISOString(),
    space: { id: space.id, startDate: space.startDate },
    events: events.map((e) => ({
      id: e.id,
      happenedAt: e.happenedAt,
      lat: e.lat,
      lng: e.lng,
      locationName: e.locationName,
      note: e.note,
      content: e.content,
      isAiGenerated: e.isAiGenerated,
      editedByUser: e.editedByUser,
      createdAt: e.createdAt,
      photos: e.photos.map((p) => ({ file: `photos/${path.basename(p.filePath)}` })),
    })),
  };
  archive.append(JSON.stringify(payload, null, 2), { name: 'events.json' });

  for (const e of events) {
    for (const p of e.photos) {
      if (fs.existsSync(p.filePath)) {
        archive.file(p.filePath, { name: `photos/${path.basename(p.filePath)}` });
      }
    }
  }

  await archive.finalize();
});

export default router;
