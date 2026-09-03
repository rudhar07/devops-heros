# Node.js Hello World - single-stage image
FROM node:20-alpine

# All following commands run relative to /app inside the image
WORKDIR /app

# Copy only the dependency manifest first so the npm install layer is cached
# and only re-runs when package.json changes, not on every source edit.
COPY package.json ./
RUN npm install --omit=dev

# Now copy the application source (node_modules is excluded by .dockerignore)
COPY . .

# Documents the port the app listens on; publishing still needs `-p` at run time
EXPOSE 3000

CMD ["node", "server.js"]
