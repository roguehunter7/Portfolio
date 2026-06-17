#!/bin/bash
# deploy.sh - Push-Based Deployment Script (Docker Compose Edition)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

TARGET_DIR="/opt/portfolio"
cd "$TARGET_DIR" || exit 1

echo "Syncing repository to latest main branch..."
git fetch origin main
git reset --hard origin/main

echo "Rebuilding and restarting services via Docker Compose..."
docker-compose down || true
docker-compose up -d --build

echo "Deployment of zero-trust portfolio and metrics daemon successful."