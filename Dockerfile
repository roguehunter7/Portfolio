# Use the official, unprivileged Nginx Alpine Slim image (No Auth Required)
FROM nginxinc/nginx-unprivileged:alpine-slim

# Copy your frontend, overwriting the default index.html
# Explicitly chown to the unprivileged nginx user (UID 101)
COPY --chown=nginx:nginx main.html /usr/share/nginx/html/index.html

# Expose the default unprivileged port
EXPOSE 8080