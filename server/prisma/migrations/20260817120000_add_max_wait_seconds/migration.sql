-- 新增：AI 生成最大等待时间（秒），默认 240
ALTER TABLE "AiConfig" ADD COLUMN "maxWaitSeconds" INTEGER NOT NULL DEFAULT 240;
