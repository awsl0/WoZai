import express from 'express';
import cors from 'cors';
import authRouter from './routes/auth.js';
import spaceRouter from './routes/space.js';
import eventsRouter from './routes/events.js';
import settingsRouter from './routes/settings.js';
import exportRouter from './routes/export.js';
import { auth } from './middleware/auth.js';

export function createApp() {
  const app = express();

  app.use(cors());
  app.use(express.json({ limit: '2mb' }));
  app.use('/uploads', express.static('uploads'));

  app.get('/health', (_req, res) => {
    res.json({ ok: true, service: 'wozai-server' });
  });

  app.use('/api/auth', authRouter);
  app.use('/api/space', auth, spaceRouter);
  app.use('/api/events', auth, eventsRouter);
  app.use('/api/settings', auth, settingsRouter);
  app.use('/api/export', auth, exportRouter);

  return app;
}
