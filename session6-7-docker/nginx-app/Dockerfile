# Nginx Hello World - static page on the official nginx image
FROM nginx:1.27-alpine

# nginx's default web root in this image is /usr/share/nginx/html/.
# Copying our page there replaces the default "Welcome to nginx!" index.
COPY index.html /usr/share/nginx/html/index.html

# nginx listens on 80 inside the container; the base image's CMD starts it in the foreground
EXPOSE 80
