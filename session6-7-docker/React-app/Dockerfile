# React Hello World - multi-stage build
# Stage 1: install dependencies and produce the static production bundle
FROM node:20-alpine AS build
WORKDIR /app

# Dependency manifest first so `npm install` is cached until package.json changes
COPY package.json ./
RUN npm install

# Copy the rest of the source (node_modules and dist excluded via .dockerignore) and build
COPY . .
RUN npm run build

# Stage 2: serve the built files with nginx; Node and node_modules are left behind
FROM nginx:1.27-alpine

# dist/ contains index.html plus the hashed assets/ bundle
COPY --from=build /app/dist /usr/share/nginx/html

# nginx listens on 80; the base image's CMD starts it in the foreground
EXPOSE 80
