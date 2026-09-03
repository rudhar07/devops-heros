# Apache Hello World - static page on the official httpd image
FROM httpd:2.4-alpine

# httpd's default DocumentRoot in this image is /usr/local/apache2/htdocs/.
# Copying our page there replaces the default "It works!" index.
COPY index.html /usr/local/apache2/htdocs/index.html

# httpd listens on 80 inside the container; the base image's CMD (httpd-foreground) starts it
EXPOSE 80
