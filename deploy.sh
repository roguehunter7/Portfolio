#!/bin/bash
# deploy.sh - Push-based zero-ingress deployment orchestrator
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

TARGET_DIR="/opt/portfolio"
cd "$TARGET_DIR" || exit 1

echo "Syncing repository to latest main branch..."
git fetch origin main
git reset --hard origin/main

echo "Writing environment variables for Docker Compose..."
echo "IMAGE_TAG=${IMAGE_TAG}" > .env
echo "CLOUDFLARE_TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}" >> .env

echo "Pulling latest portfolio-web container..."
docker-compose pull web

echo "Deploying Docker Compose services..."
docker-compose up -d --remove-orphans

echo "Deployment complete!"
