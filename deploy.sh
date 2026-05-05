#!/bin/bash
# Set path to include /usr/bin where gh is located
export PATH=$PATH:/usr/bin
cd /home/krsreeram007/portfolio

# 1. Get the latest Commit SHA from the Private Repo using GH API
REMOTE_SHA=$(gh api repos/:owner/:repo/commits/main -q .sha)
# 2. Get the local Commit SHA
LOCAL_SHA=$(git rev-parse HEAD)

if [ "$REMOTE_SHA" != "$LOCAL_SHA" ]; then
    echo "New version detected on GitHub. Pulling changes..."
    
    # 3. Use GH to sync the repo (authenticated pull)
    gh repo sync
    
    # 4. Rebuild the Docker container
    docker build -t portfolio-site .
    docker stop my-website || true
    docker rm my-website || true
    docker run -d --name my-website -p 80:80 --restart always portfolio-site
    
    echo "Deployment successful: $(date)"
else
    echo "No changes found: $(date)"
fi
