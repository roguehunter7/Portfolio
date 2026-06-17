#!/bin/bash
# deploy.sh - Push-Based Deployment Script (Cloud-Native Image Edition)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

TARGET_DIR="/opt/portfolio"
cd "$TARGET_DIR" || exit 1

echo "Syncing repository to latest main branch..."
git fetch origin main
git reset --hard origin/main

# Extract git Remote token to authenticate local docker pulls from private GHCR
TOKEN=$(git config --get remote.origin.url | sed -E 's|https://([^@]+)@github.com.*|\1|' | cut -d':' -f2)
echo "$TOKEN" | docker login ghcr.io -u roguehunter7 --password-stdin

# Define target image
REPO_LOWER="roguehunter7/portfolio"
IMAGE_NAME="ghcr.io/${REPO_LOWER}/portfolio-web:${IMAGE_TAG}"

echo "Pulling $IMAGE_NAME from GHCR..."
docker pull "$IMAGE_NAME"

echo "Tearing down stale web container..."
docker stop portfolio-web || true
docker rm portfolio-web || true

echo "Launching unprivileged Nginx container..."
docker run -d \
  --name portfolio-web \
  -p 80:8080 \
  --add-host=host.docker.internal:host-gateway \
  --restart always \
  "$IMAGE_NAME"

# Restart host daemon
systemctl restart metrics-daemon || true