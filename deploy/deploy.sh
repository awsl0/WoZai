#!/usr/bin/env bash
# WoZai 一键部署脚本（Ubuntu/Debian）
# 用法: bash deploy.sh   （在服务器上执行）
set -euo pipefail

APP_DIR=/opt/wozai
APP_USER=wozai

echo "==> 1/6 安装基础依赖"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl git build-essential nginx

echo "==> 2/6 安装 Node.js 20 + PM2"
if ! command -v node >/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
npm install -g pm2

echo "==> 3/6 创建运行用户"
id -u $APP_USER >/dev/null 2>&1 || useradd -m -s /bin/bash $APP_USER
mkdir -p $APP_DIR/uploads
chown -R $APP_USER:$APP_USER $APP_DIR

echo "==> 4/6 安装后端依赖并构建"
cd $APP_DIR/server
sudo -u $APP_USER npm install --omit=dev 2>/dev/null || npm install --omit=dev
sudo -u $APP_USER npx prisma generate
# 初始化数据库（若不存在）
sudo -u $APP_USER npx prisma db push --skip-generate || true

echo "==> 5/6 配置 Nginx（前端静态 + /api 反代）"
cat > /etc/nginx/sites-available/wozai << 'NGINX'
server {
    listen 80;
    server_name _;

    # 前端（Flutter web 构建产物）
    root /opt/wozai/app/build/web;
    index index.html;

    # API 反代到后端
    location /api/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        client_max_body_size 50m;   # 上传照片
    }

    # 上传文件（头像）
    location /uploads/ {
        alias /opt/wozai/server/uploads/;
        expires 30d;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }

    gzip on;
    gzip_types text/plain text/css application/javascript application/json image/svg+xml;
}
NGINX
ln -sf /etc/nginx/sites-available/wozai /etc/nginx/sites-enabled/wozai
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

echo "==> 6/6 启动后端（PM2 守护 + 开机自启）"
cd $APP_DIR/server
# 生产环境变量
cat > $APP_DIR/server/.env << ENVEOF
DATABASE_URL="file:./prisma/dev.db"
JWT_SECRET="$(openssl rand -hex 32)"
PORT=3000
ENVEOF
chown $APP_USER:$APP_USER $APP_DIR/server/.env
sudo -u $APP_USER pm2 start dist/index.js --name wozai-server --cwd $APP_DIR/server
sudo -u $APP_USER pm2 save
env PATH=$PATH:/usr/bin pm2 startup systemd -u $APP_USER --hp /home/$APP_USER >/dev/null 2>&1 || true
sudo -u $APP_USER pm2 restart wozai-server

echo ""
echo "部署完成！"
echo "  - 后端: http://127.0.0.1:3000 (Nginx 反代 /api)"
echo "  - 前端: http://<服务器IP>/"
echo "  - 上传: /opt/wozai/server/uploads"
echo "  - 日志: pm2 logs wozai-server"
echo ""
echo "上传到服务器的文件结构:"
echo "  /opt/wozai/server   (后端, 从项目 server/ 上传)"
echo "  /opt/wozai/app/build/web (前端, Flutter web 构建产物)"
