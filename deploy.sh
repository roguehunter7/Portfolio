#!/bin/bash
# deploy.sh - Push-Based Deployment Script (DHI Alpine FIPS)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

TARGET_DIR="/opt/portfolio"
cd "$TARGET_DIR" || exit 1

echo "Syncing repository to latest main branch..."
git fetch origin main
git reset --hard origin/main

echo "Building Docker container from hardened Alpine FIPS base..."
docker build --no-cache --pull -t portfolio-site .

echo "Tearing down stale container..."
docker stop my-website || true
docker rm my-website || true

# Map Host Port 80 -> Hardened Container Port 8080
echo "Deploying unprivileged container..."
docker run -d --name my-website -p 80:8080 --restart always portfolio-site

echo "Deployment of dhi.io/nginx:1-alpine3.23-fips successful."