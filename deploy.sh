#!/bin/bash
# Deploy.sh - Native GitOps Poller
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Dynamically change to the script's directory
cd "$(dirname "$0")" || exit 1

# Get Remote SHA natively via Git (This uses the PAT stored in origin)
REMOTE_SHA=$(git ls-remote origin -h refs/heads/main | awk '{print $1}')

# Get Local SHA
LOCAL_SHA=$(git rev-parse HEAD)

# Check for differences (and ensure REMOTE_SHA isn't empty)
if [ "$REMOTE_SHA" != "$LOCAL_SHA" ] &&[ -n "$REMOTE_SHA" ]; then
    echo "$(date): New version detected! Local: $LOCAL_SHA | Remote: $REMOTE_SHA"
    
    # Force the update to match GitHub perfectly
    git fetch origin main
    git reset --hard origin/main
    
    # Rebuild and Restart Docker
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