# Use the ultra-lightweight Nginx Alpine image
FROM nginx:alpine
# Remove default nginx page and add yours
RUN rm /usr/share/nginx/html/index.html
COPY main.html /usr/share/nginx/html/index.html
# Nginx runs on port 80 by default
EXPOSE 80
