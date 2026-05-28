# Use the official, unprivileged Nginx Alpine Slim image as the base image
FROM nginxinc/nginx-unprivileged:1.27.12-alpine-slim

# Clean up default Nginx HTML placeholder assets
RUN rm -rf /usr/share/nginx/html/*

# Copy your frontend with explicit non-root ownership (nginx user is UID 101)
COPY --chown=nginx:nginx main.html /usr/share/nginx/html/index.html

# Expose the default unprivileged port (8080)
EXPOSE 8080