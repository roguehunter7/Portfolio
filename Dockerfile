# Use the official, unprivileged Nginx Alpine Slim image (No Auth Required)
FROM nginxinc/nginx-unprivileged:1.27.0-alpine-slim

# Copy custom Nginx configuration to expose /status
COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/default.conf

# Copy your frontend, overwriting the default index.html
# Explicitly chown to the unprivileged nginx user (UID 101)
COPY --chown=nginx:nginx main.html /usr/share/nginx/html/index.html

# Copy the compiled resume PDF with correct unprivileged ownership
COPY --chown=nginx:nginx resume.pdf /usr/share/nginx/html/resume.pdf

# Expose the default unprivileged port
EXPOSE 8080