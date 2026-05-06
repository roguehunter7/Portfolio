#!/bin/bash
# Deploy.sh - Native GitOps Poller (Explicit Path Version)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 1. HARDCODE THE PATH (Align with Terraform /opt/portfolio)
TARGET_DIR="/opt/portfolio"
cd "$TARGET_DIR" || exit 1

# 2. Get Remote SHA (Using the PAT in origin)
REMOTE_SHA=$(git ls-remote origin -h refs/heads/main | awk '{print $1}')

# 3. Get Local SHA
LOCAL_SHA=$(git rev-parse HEAD)

if [ "$REMOTE_SHA" != "$LOCAL_SHA" ] && [ -n "$REMOTE_SHA" ]; then
    echo "$(date): New version detected! Local: $LOCAL_SHA | Remote: $REMOTE_SHA"
    
    # Force the update
    git fetch origin main
    git reset --hard origin/main
    
    # Rebuild and Restart Docker (Added sudo to be safe in automation)
    echo "Rebuilding Docker image..."
    docker build --no-cache --pull -t portfolio-site .
    
    echo "Stopping old container..."
    docker stop my-website || true
    docker rm my-website || true
    
    echo "Starting new container..."
    docker run -d --name my-website -p 80:80 --restart always portfolio-site
    
    echo "$(date): Deployment successful."
else
    # Logic: If the container isn't running at all (e.g., first boot), start it!
    if [ ! "$(docker ps -q -f name=my-website)" ]; then
        echo "Container not found. Performing initial launch..."
        docker run -d --name my-website -p 80:80 --restart always portfolio-site
    fi
    echo "$(date): No changes found."
fi
