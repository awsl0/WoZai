# WoZai（我在）

> 帮懒人情侣/个人记录每一天的 App —— 拍张照，AI 帮你写日记，沉淀成时间线。

**WoZai** 是一个自部署、数据私有的"懒人日记 + 时间线"应用：

- 拍一张照（或写一句话），AI 自动补齐时间、地点、照片内容，生成一段有温度的日记
- 单人可用（个人生活日记），也可以邀请另一半组成情侣空间（2 人共享同一份时间线）
- 数据完全在自己掌控下：自部署后端 + 自己的 AI API Key（BYOK）

## 功能

- 📸 **记录事件**：多张照片 + 自动定位 + 时间（可回填补记）+ 一句话备注（可选）
- 🤖 **AI 生成日记**：多模态 LLM 看图 + 上下文（时间/地点/备注）→ 温暖日记；可编辑 / 重新生成 / 换文风；幻觉约束（只写照片可见事实）
- ⏱ **时间线**：按月分组，顶部显示"在一起第 N 天"
- 💑 **情侣空间**：邀请码加入，2 人共享；也支持单人自用
- 🔑 **BYOK**：OpenAI 兼容协议，支持通义千问 / 智谱 / DeepSeek / OpenAI 等
- 📦 **数据导出**：一键导出全部事件 + 照片

## 架构

```
Flutter App (Android/iOS/桌面/Web 调试)
      │  REST API (http://IP:3000)
      ▼
Node.js + TypeScript + Express + Prisma
      │
      ├── SQLite（事件/日记/用户）
      └── 本地文件系统（照片）
```

- **后端**：Node 20 + TypeScript + Express + Prisma + SQLite
- **客户端**：Flutter（开发期可跑 Windows 桌面 / Chrome，无需 Android Studio；APK 由 GitHub Actions CI 构建）
- **部署**：Docker Compose 一键起服务（轻量云 IP 直连即可，无需域名/备案/HTTPS）

完整产品设计见 [docs/product-design.md](docs/product-design.md)。

## 快速开始（开发环境）

前置要求：

| 工具 | 版本 | 用途 |
|---|---|---|
| Node.js | ≥ 20 | 后端 |
| Flutter SDK | ≥ 3.x | 客户端 |
| Git | 任意 | 版本管理 |

```bash
# 1. 克隆
git clone <repo-url> && cd WoZai

# 2. 后端
cd server
npm install
cp .env.example .env   # 按需修改端口等
npm run dev            # 默认 http://localhost:3000

# 3. 客户端（开发调试）
cd ../app
flutter pub get
flutter run -d windows   # 或 -d chrome，无需 Android Studio
```

> App 首次启动需在"设置"中配置后端地址（如 `http://localhost:3000`）与 AI 配置。

## API 概览（当前已实现）

| 方法 | 路径 | 说明 | 鉴权 |
|---|---|---|---|
| POST | `/api/auth/register` | 注册（自动创建个人空间） | - |
| POST | `/api/auth/login` | 登录，返回 JWT | - |
| GET | `/api/auth/me` | 当前用户 + 空间 | ✅ |
| PUT | `/api/auth/profile` | 修改昵称 | ✅ |
| GET | `/api/space` | 我的空间（含成员） | ✅ |
| POST | `/api/space/join` | 邀请码加入（上限 2 人） | ✅ |
| POST | `/api/space/invite` | 重新生成邀请码（仅 owner） | ✅ |
| POST | `/api/space/transfer` | 转让空间（仅 owner） | ✅ |
| PUT | `/api/space/start-date` | 设置/清空在一起日期 | ✅ |
| POST | `/api/events` | 创建事件（multipart：照片≤9张 + 时间 + 定位 + 备注） | ✅ |
| GET | `/api/events` | 时间线（倒序，含照片） | ✅ |
| GET | `/api/events/:id` | 事件详情 | ✅ |
| PUT | `/api/events/:id` | 编辑事件（改正文/时间/地点，正文改动标记用户编辑） | ✅ |
| DELETE | `/api/events/:id` | 删除事件（连照片） | ✅ |
| POST | `/api/events/:id/generate` | AI 看图生成日记（BYOK 多模态） | ✅ |
| GET | `/api/settings/ai` | 读取 AI 配置（key 脱敏） | ✅ |
| PUT | `/api/settings/ai` | 保存 AI 配置（空间级共享） | ✅ |
| GET | `/api/export` | 导出全部事件 + 照片（ZIP） | ✅ |

## 部署（轻量云）

```bash
docker compose up -d
# 安全组放行对应端口（默认 3000）
# App 设置里填 http://服务器IP:3000
```

照片是核心资产，请务必为服务器配置**定期备份**（快照 / 数据盘 / 定期 rsync）。

## AI 配置（BYOK）

在 App 设置 → AI 配置中填写：

| 字段 | 说明 | 示例 |
|---|---|---|
| Base URL | OpenAI 兼容端点 | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| API Key | 你的密钥 | `sk-...` |
| 模型 | 多模态模型名 | `qwen-vl-max` / `glm-4v-plus` / `gpt-4o` |

> 隐私说明：照片与上下文会发送到你**自己配置的** AI 服务商；项目本身不收集任何数据。

## 隐私与合规

- 本项目不收集任何用户数据，全部数据存储于你的自部署实例
- 定位、照片属个人信息，部署者自行负责合规（[个人信息保护法](http://www.npc.gov.cn/npc/c30834/202108/a8c4e3672c74491a80b53a172bb753fe.shtml)）
- 更多细节见 [docs/product-design.md](docs/product-design.md) §9

## 路线图

- [x] 产品设计（v0.2）
- [x] M0 后端脚手架：Express + Prisma + SQLite + 注册登录 + 空间/邀请码（含 CI）
- [x] M1 后端核心：事件 CRUD + 照片上传 + AI 看图生成日记 + 转让/日期/导出
- [x] M1 客户端：Flutter 骨架（登录/时间线/记录/事件详情/设置），Web 调试可用
- [ ] M2：定位接入、地图视图、纪念日、EXIF、编辑历史、搜索、通知
- [ ] M3：Android APK CI 构建、iOS 支持、分享卡片、年度报告、视觉打磨

## License

[MIT](LICENSE)
