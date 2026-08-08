FROM nginxinc/nginx-unprivileged:alpine-slim

# Copy custom Nginx configuration to expose /status
COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/default.conf

# Copy static site and resume files
COPY --chown=nginx:nginx index.html 404.html resume.pdf resume-html.pdf resume.html /usr/share/nginx/html/

EXPOSE 8080