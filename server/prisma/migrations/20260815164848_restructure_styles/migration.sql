-- 自定义文风重构：移除 customPrompt，新增 styles(JSON)
ALTER TABLE "AiConfig" DROP COLUMN "customPrompt";
ALTER TABLE "AiConfig" ADD COLUMN "styles" TEXT;
