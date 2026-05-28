#!/bin/bash
# deploy.sh - Push-Based Deployment Script (Unprivileged Edition)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

TARGET_DIR="/opt/portfolio"
cd "$TARGET_DIR" || exit 1

echo "Syncing repository to latest main branch..."
git fetch origin main
git reset --hard origin/main

echo "Rebuilding container using Nginx Unprivileged base..."
docker build --no-cache --pull -t portfolio-site .

echo "Tearing down stale container..."
docker stop my-website || true
docker rm my-website || true

# Map Host Port 80 -> Unprivileged Container Port 8080
echo "Launching unprivileged container on port 8080..."
docker run -d --name my-website -p 80:8080 --restart always portfolio-site

echo "Deployment of nginx-unprivileged portfolio successful."