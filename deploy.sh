#!/bin/bash
# Deploy.sh - Native GitOps Poller
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

TARGET_DIR="/opt/portfolio"
cd "$TARGET_DIR" || exit 1

REMOTE_SHA=$(git ls-remote origin -h refs/heads/main | awk '{print $1}')
LOCAL_SHA=$(git rev-parse HEAD)
IMAGE_EXISTS=$(docker images -q portfolio-site)

# Logic: Build if SHA changed OR if the image is missing entirely
if [ "$REMOTE_SHA" != "$LOCAL_SHA" ] || [ -z "$IMAGE_EXISTS" ]; then
    echo "$(date): Deployment triggered (New SHA or Missing Image)."
    
    git fetch origin main
    git reset --hard origin/main
    
    echo "Building Docker image..."
    docker build --no-cache --pull -t portfolio-site .
    
    echo "Restarting container..."
    docker stop my-website || true
    docker rm my-website || true
    docker run -d --name my-website -p 80:80 --restart always portfolio-site
    
    echo "$(date): Deployment successful."
else
    # Safety: If image exists but container is stopped, start it
    if [ ! "$(docker ps -q -f name=my-website)" ]; then
        echo "Container stopped. Restarting..."
        docker start my-website || docker run -d --name my-website -p 80:80 --restart always portfolio-site
    fi
    echo "$(date): No changes found and container is healthy."
fi