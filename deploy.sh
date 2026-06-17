#!/bin/bash
# deploy.sh - Push-Based Deployment Script (Docker Compose Edition)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

TARGET_DIR="/opt/portfolio"
cd "$TARGET_DIR" || exit 1

echo "Syncing repository to latest main branch..."
git fetch origin main
git reset --hard origin/main

# Copy the compiled resume from /tmp into the build context
if [ -f /tmp/resume.pdf ]; then
  echo "Found compiled resume.pdf in /tmp, copying to build context..."
  cp /tmp/resume.pdf /opt/portfolio/resume.pdf
fi

echo "Rebuilding and restarting services via Docker Compose..."
docker-compose down || true
docker-compose up -d --build

echo "Deployment of zero-trust portfolio and metrics daemon successful."