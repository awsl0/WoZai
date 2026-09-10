import express from 'express';
import cors from 'cors';
import fs from 'node:fs';
import path from 'node:path';
import sharp from 'sharp';
import authRouter from './routes/auth.js';
import spaceRouter from './routes/space.js';
import eventsRouter from './routes/events.js';
import settingsRouter from './routes/settings.js';
import exportRouter from './routes/export.js';
import geocodeRouter from './routes/geocode.js';
import { auth } from './middleware/auth.js';

export function createApp() {
  const app = express();

  app.use(cors());
  app.use(express.json({ limit: '2mb' }));
  app.use('/uploads', express.static('uploads'));

  // 缩略图：/thumb/<文件名>?w=480 —— 按需生成并磁盘缓存（列表/照片墙用，大幅减少流量与解码内存）
  app.get('/thumb/:file', async (req, res) => {
    const file = path.basename(String(req.params.file));
    const orig = path.join('uploads', file);
    if (!fs.existsSync(orig)) return res.status(404).end();
    const w = Math.min(1200, Math.max(80, Number(req.query.w) || 480));
    const thumbDir = path.join('uploads', 'thumbs');
    try {
      fs.mkdirSync(thumbDir, { recursive: true });
    } catch {
      /* 已存在 */
    }
    const base = file.replace(/\.[^.]+$/, '');
    const dest = path.join(thumbDir, `${base}-w${w}.jpg`);
    try {
      if (!fs.existsSync(dest)) {
        await sharp(orig)
          .rotate() // 按 EXIF 方向纠正
          .resize(w, w, { fit: 'inside', withoutEnlargement: true })
          .jpeg({ quality: 78 })
          .toFile(dest);
      }
      res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
      return res.sendFile(path.resolve(dest));
    } catch {
      // 生成失败则回退原图
      return res.sendFile(path.resolve(orig));
    }
  });

  app.get('/health', (_req, res) => {
    res.json({ ok: true, service: 'wozai-server' });
  });

  app.use('/api/auth', authRouter);
  app.use('/api/space', auth, spaceRouter);
  app.use('/api/events', auth, eventsRouter);
  app.use('/api/settings', auth, settingsRouter);
  app.use('/api/export', auth, exportRouter);
  // 地理编码代理：不需要登录（选点搜索），但有节流保护
  app.use('/api/geocode', geocodeRouter);

  return app;
}
