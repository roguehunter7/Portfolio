# Use the official Docker Hardened Image (DHI) for Nginx
FROM dhi.io/nginx:1-alpine3.23-fips

# Clear default Nginx html assets
RUN rm -rf /usr/share/nginx/html/*

# Copy your frontend with explicit non-root ownership
COPY --chown=nginx:nginx main.html /usr/share/nginx/html/index.html

# DHI Nginx binds to 8080 by default because it runs unprivileged
EXPOSE 8080