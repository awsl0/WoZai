-- AlterTable
ALTER TABLE "Event" ADD COLUMN "weather" JSONB;

-- AlterTable
ALTER TABLE "Space" ADD COLUMN "customDates" JSONB;

-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;
CREATE TABLE "new_AiConfig" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "spaceId" TEXT NOT NULL,
    "baseUrl" TEXT NOT NULL,
    "apiKey" TEXT NOT NULL,
    "model" TEXT NOT NULL,
    "style" TEXT NOT NULL DEFAULT '温暖',
    "styles" JSONB,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "AiConfig_spaceId_fkey" FOREIGN KEY ("spaceId") REFERENCES "Space" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
INSERT INTO "new_AiConfig" ("apiKey", "baseUrl", "id", "model", "spaceId", "style", "styles", "updatedAt") SELECT "apiKey", "baseUrl", "id", "model", "spaceId", "style", "styles", "updatedAt" FROM "AiConfig";
DROP TABLE "AiConfig";
ALTER TABLE "new_AiConfig" RENAME TO "AiConfig";
CREATE UNIQUE INDEX "AiConfig_spaceId_key" ON "AiConfig"("spaceId");
PRAGMA foreign_keys=ON;
PRAGMA defer_foreign_keys=OFF;

