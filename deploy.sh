#!/bin/bash
# deploy.sh - Push-based zero-ingress deployment orchestrator
set -e
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]; then echo "ERROR: CLOUDFLARE_TUNNEL_TOKEN is not set" >&2; exit 1; fi

TARGET_DIR="/opt/portfolio"
cd "$TARGET_DIR" || exit 1

echo "Syncing repository to latest main branch..."
git config --global --add safe.directory "$TARGET_DIR"
git fetch origin main
git reset --hard origin/main

echo "Writing environment variables for Docker Compose..."
echo "CLOUDFLARE_TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}" > .env

echo "Pulling latest containers..."
docker compose pull

echo "Deploying Docker Compose services..."
docker compose up -d --remove-orphans

echo "Deployment complete!"
