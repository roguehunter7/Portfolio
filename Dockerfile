# Dockerfile
# Use the ultra-lightweight Nginx Alpine image
FROM dhi.io/nginx:mainline-alpine
# Force an update of all underlying OS packages to patch known CVEs
RUN apk update && apk upgrade --no-cache
# Remove default nginx page and add yours
RUN rm /usr/share/nginx/html/index.html
COPY main.html /usr/share/nginx/html/index.html
# Nginx runs on port 80 by default
EXPOSE 80
