#!/bin/bash
# 1. Set explicit paths so systemd can find docker, git, and gh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 2. Dynamically change to the script's directory
cd "$(dirname "$0")" || exit 1

# 3. Get Remote SHA via GH API
REMOTE_SHA=$(gh api repos/roguehunter7/portfolio/commits/main -q .sha)

# 4. Get Local SHA
LOCAL_SHA=$(git rev-parse HEAD)

# 5. Check for differences (Notice the spaces!)
if [ "$REMOTE_SHA" != "$LOCAL_SHA" ]; then
    echo "$(date): New version detected! Local: $LOCAL_SHA | Remote: $REMOTE_SHA"
    
    # 6. Force the update to match GitHub perfectly
    git fetch origin main
    git reset --hard origin/main
    
    # 7. Rebuild and Restart Docker
    echo "Rebuilding Docker image..."
    docker build --no-cache --pull -t portfolio-site .
    
    echo "Stopping old container..."
    docker stop my-website || true
    docker rm my-website || true
    
    echo "Starting new container..."
    docker run -d --name my-website -p 80:80 --restart always portfolio-site
    
    echo "$(date): Deployment successful."
else
    echo "$(date): No changes found."
fi