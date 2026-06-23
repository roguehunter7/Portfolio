FROM nginxinc/nginx-unprivileged:1.27.0-alpine-slim

COPY index.html resume.pd* /usr/share/nginx/html/