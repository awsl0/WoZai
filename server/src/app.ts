import express from 'express';
import cors from 'cors';
import authRouter from './routes/auth.js';
import spaceRouter from './routes/space.js';
import { auth } from './middleware/auth.js';

export function createApp() {
  const app = express();

  app.use(cors());
  app.use(express.json({ limit: '2mb' }));

  app.get('/health', (_req, res) => {
    res.json({ ok: true, service: 'wozai-server' });
  });

  app.use('/api/auth', authRouter);
  app.use('/api/space', auth, spaceRouter);

  return app;
}
