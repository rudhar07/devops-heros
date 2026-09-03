# Docker Fundamentals - Hello World Applications

**Name:** Rudhar Bajaj

**Environment:** macOS 26.5.2 (Apple Silicon), Docker Desktop, Docker Engine 29.6.1 linux/arm64

This document covers the "Docker Fundamentals" task: six minimal Hello World web applications, each in its own folder with its own Dockerfile, built into an image, run as a container, and verified over HTTP. All command output below is copied from what I actually ran on my machine; long build logs are trimmed and the full tails are kept in the `outputs/` folder.

| Folder | Stack | Container port | Host port | URL |
|---|---|---|---|---|
| `nodejs-app` | Node.js 20 + Express | 3000 | 3000 | http://localhost:3000 |
| `python-app` | Python 3.11 + Flask | 5000 | 5001 | http://localhost:5001 |
| `java-app` | Java 17 (`com.sun.net.httpserver`) + Maven, multi-stage | 8080 | 8084 | http://localhost:8084 |
| `Apache-app` | Apache httpd 2.4 (static HTML) | 80 | 8081 | http://localhost:8081 |
| `React-app` | React 18 + Vite, served by nginx, multi-stage | 80 | 8082 | http://localhost:8082 |
| `nginx-app` | nginx 1.27 (static HTML) | 80 | 8083 | http://localhost:8083 |

Image names and container names are the same: `hello-nodejs`, `hello-python`, `hello-java`, `hello-apache`, `hello-react`, `hello-nginx`.

Host port 5000 is not used because macOS AirPlay Receiver listens on it, and 8080 is kept free for the multi-stage task in this same session, so the Java app is published on 8084.

---

## 1. Node.js application (`nodejs-app`)

A tiny Express server (`server.js`) with one route, `GET /`, that returns an HTML page containing `<h1>Hello World</h1>`. It binds to `0.0.0.0:3000` so it is reachable from outside the container. The folder has `package.json`, `server.js`, a `.dockerignore` that excludes `node_modules`, and the Dockerfile.

```dockerfile
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
```

`FROM node:20-alpine` starts from the official Node 20 image on Alpine, which is small and multi-arch so it runs natively on my arm64 machine. `WORKDIR /app` makes `/app` the working directory for every later `COPY`, `RUN` and for the running process. I copy `package.json` and run `npm install --omit=dev` before copying the rest so that the dependency layer is cached and only re-runs when `package.json` changes; `COPY . .` then adds `server.js` (the `.dockerignore` keeps my host `node_modules` out of the build context). `EXPOSE 3000` documents the port and `CMD` starts the server as the container's main process.

```bash
cd session6-7-docker
docker build -t hello-nodejs ./nodejs-app
docker run -d --name hello-nodejs -p 3000:3000 hello-nodejs
curl -s -i http://localhost:3000
```

```text
===== hello-nodejs  ->  $ curl -s -i http://localhost:3000 =====
HTTP/1.1 200 OK
X-Powered-By: Express
Content-Type: text/html; charset=utf-8
Content-Length: 233
ETag: W/"e9-+VRmuv1x2TGshbJa+HgV9f5l0Yo"
Date: Thu, 03 Sep 2026 15:05:57 GMT
Connection: keep-alive
Keep-Alive: timeout=5

<!DOCTYPE html>
<html lang="en">
  <head><meta charset="utf-8"><title>Hello World - Node.js</title></head>
  <body>
    <h1>Hello World</h1>
    <p>Served by Node.js v20.20.2 + Express inside a Docker container.</p>
  </body>
</html>
```

---

## 2. Python application (`python-app`)

The `python-app` folder already existed with a `Dockerfile` and an `app.py` that only printed to stdout. I turned it into a Flask web app: `app.py` defines one route that returns the Hello World HTML page and runs on `0.0.0.0:5000`, and `requirements.txt` pins `flask==3.0.3`. I also rewrote the Dockerfile, because the original ran `apt install -y pip3 python3` which is not needed (the `python:3.11-slim` image already ships Python and pip, and `pip3` is not an apt package name).

```dockerfile
# Python Hello World - single-stage image
FROM python:3.11-slim

# Send Python logs straight to the container output without buffering
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install dependencies in their own layer so it is cached until requirements.txt changes
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code last because it changes most often
COPY app.py .

# Flask listens on 5000 inside the container
EXPOSE 5000

CMD ["python", "app.py"]
```

`FROM python:3.11-slim` gives me Python 3.11 on a slim Debian base. `ENV PYTHONUNBUFFERED=1` makes Flask's logs appear immediately in `docker logs`. Copying `requirements.txt` and running `pip install --no-cache-dir` first means the dependency layer is reused on every rebuild where only `app.py` changed; `--no-cache-dir` keeps pip's download cache out of the image. `EXPOSE 5000` documents the container port and `CMD ["python", "app.py"]` starts the Flask development server.

```bash
cd session6-7-docker
docker build -t hello-python ./python-app
# container port 5000 -> host port 5001 (macOS AirPlay owns host port 5000)
docker run -d --name hello-python -p 5001:5000 hello-python
curl -s -i http://localhost:5001
```

```text
===== hello-python  ->  $ curl -s -i http://localhost:5001 =====
HTTP/1.1 200 OK
Server: Werkzeug/3.1.8 Python/3.11.16
Date: Thu, 03 Sep 2026 15:05:57 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 228
Connection: close

<!DOCTYPE html>
<html lang="en">
  <head><meta charset="utf-8"><title>Hello World - Python</title></head>
  <body>
    <h1>Hello World</h1>
    <p>Served by Python 3.11.16 + Flask inside a Docker container.</p>
  </body>
</html>
```

---

## 3. Java application (`java-app`)

A plain Java 17 program (`HelloServer.java`) that uses the JDK's built-in `com.sun.net.httpserver.HttpServer`, so there is no framework dependency at all. The `pom.xml` configures `maven-jar-plugin` to write a `Main-Class` manifest entry and fixes the jar name to `hello-java.jar`, so the result is runnable with `java -jar`. Because I have no JDK or Maven installed locally, the compile happens entirely inside Docker with a multi-stage build.

```dockerfile
# Java Hello World - multi-stage build
# Stage 1: compile and package with Maven (JDK 17 included in this image)
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app

# Copy the pom first and pre-download plugins/dependencies so this slow layer
# is cached and does not re-run every time the Java source changes.
COPY pom.xml .
RUN mvn -B dependency:go-offline

# Copy the source and build the runnable jar
COPY src ./src
RUN mvn -B package

# Stage 2: small runtime image with only a JRE (no Maven, no JDK, no source)
FROM eclipse-temurin:17-jre
WORKDIR /app

# Pull just the packaged jar out of the build stage
COPY --from=build /app/target/hello-java.jar app.jar

# The server listens on 8080 inside the container
EXPOSE 8080

CMD ["java", "-jar", "app.jar"]
```

Stage 1 (`FROM maven:3.9-eclipse-temurin-17 AS build`) has both Maven and JDK 17. I copy `pom.xml` alone and run `mvn dependency:go-offline` so all plugins and dependencies are downloaded into a cached layer; on my first build this step took about 57 seconds and it will be skipped on rebuilds unless the pom changes. Then `COPY src ./src` and `mvn package` compile the code and produce `target/hello-java.jar`, which only took about a second. Stage 2 (`FROM eclipse-temurin:17-jre`) contains just a Java runtime; `COPY --from=build` pulls only the jar across, so Maven, the compiler, the `~/.m2` cache and the source never end up in the final image. `EXPOSE 8080` documents the port and `CMD ["java", "-jar", "app.jar"]` starts the server. I used `eclipse-temurin:17-jre` rather than the `-alpine` variant because the Alpine tag is amd64-only and does not run on Apple Silicon.

```bash
cd session6-7-docker
docker build -t hello-java ./java-app
# container port 8080 -> host port 8084 (8080 is reserved for the multi-stage task)
docker run -d --name hello-java -p 8084:8080 hello-java
curl -s -i http://localhost:8084
```

```text
===== hello-java  ->  $ curl -s -i http://localhost:8084 =====
HTTP/1.1 200 OK
Date: Thu, 03 Sep 2026 15:05:57 GMT
Content-type: text/html; charset=utf-8
Content-length: 242

<!DOCTYPE html>
<html lang="en">
  <head><meta charset="utf-8"><title>Hello World - Java</title></head>
  <body>
    <h1>Hello World</h1>
    <p>Served by Java 17.0.20 (com.sun.net.httpserver) inside a Docker container.</p>
  </body>
</html>
```

---

## 4. Apache web server (`Apache-app`)

A static `index.html` with `<h1>Hello World</h1>` served by Apache HTTP Server. There is no application code to run; the page just needs to be placed in httpd's document root.

```dockerfile
# Apache Hello World - static page on the official httpd image
FROM httpd:2.4-alpine

# httpd's default DocumentRoot in this image is /usr/local/apache2/htdocs/.
# Copying our page there replaces the default "It works!" index.
COPY index.html /usr/local/apache2/htdocs/index.html

# httpd listens on 80 inside the container; the base image's CMD (httpd-foreground) starts it
EXPOSE 80
```

`FROM httpd:2.4-alpine` is the official Apache image. Its DocumentRoot is `/usr/local/apache2/htdocs/`, so `COPY index.html` into that path replaces the default "It works!" page. `EXPOSE 80` documents the port. There is no `CMD` in my Dockerfile because the base image already defines `httpd-foreground`, which keeps Apache running in the foreground as PID 1, and that CMD is inherited.

```bash
cd session6-7-docker
docker build -t hello-apache ./Apache-app
docker run -d --name hello-apache -p 8081:80 hello-apache
curl -s -i http://localhost:8081
```

```text
===== hello-apache  ->  $ curl -s -i http://localhost:8081 =====
HTTP/1.1 200 OK
Date: Thu, 03 Sep 2026 15:05:57 GMT
Server: Apache/2.4.68 (Unix)
Last-Modified: Thu, 03 Sep 2026 15:03:12 GMT
ETag: "f6-65a9573576c00"
Accept-Ranges: bytes
Content-Length: 246
Content-Type: text/html

<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Hello World - Apache</title>
  </head>
  <body>
    <h1>Hello World</h1>
    <p>Served by Apache HTTP Server (httpd) inside a Docker container.</p>
  </body>
</html>
```

---

## 5. React application (`React-app`)

A React 18 project scaffolded for Vite: `index.html` mounts `src/main.jsx`, which renders `src/App.jsx`, and `App.jsx` returns `<h1>Hello World</h1>`. The production build is static HTML plus a hashed JavaScript bundle, so nothing Node-related is needed at run time; nginx just serves the files. `.dockerignore` excludes `node_modules` and `dist`.

```dockerfile
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
```

Stage 1 (`FROM node:20-alpine AS build`) installs dependencies and compiles the app. `COPY package.json` followed by `npm install` runs first so that layer is cached; here I need dev dependencies too because Vite itself is a devDependency that performs the build. `COPY . .` adds the source and `npm run build` writes the optimized bundle to `dist/`. Stage 2 (`FROM nginx:1.27-alpine`) is a fresh, tiny web-server image; `COPY --from=build /app/dist /usr/share/nginx/html` brings over only the built files. The final image is about 76 MB, while the Node build image alone is well over 200 MB with `node_modules`. `EXPOSE 80` documents the port and nginx's own CMD is inherited.

```bash
cd session6-7-docker
docker build -t hello-react ./React-app
docker run -d --name hello-react -p 8082:80 hello-react
curl -s -i http://localhost:8082
```

```text
===== hello-react  ->  $ curl -s -i http://localhost:8082 =====
HTTP/1.1 200 OK
Server: nginx/1.27.5
Date: Thu, 03 Sep 2026 15:05:57 GMT
Content-Type: text/html
Content-Length: 406
Last-Modified: Thu, 03 Sep 2026 15:05:11 GMT
Connection: keep-alive
ETag: "6a998ca7-196"
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Hello World - React</title>
    <script type="module" crossorigin src="/assets/index-C2JW_ARs.js"></script>
  </head>
  <body>
    <div id="root"></div>
    <!-- Vite replaces this with the hashed production bundle at build time -->
  </body>
</html>
```

For a React app the words "Hello World" are not in `index.html`; they live in the compiled JavaScript bundle that the page loads. The bundle check in the Verification section below shows that the bundle referenced by `index.html` is served with HTTP 200 and contains the `Hello World` string inside the compiled `<h1>` element.

---

## 6. Nginx application (`nginx-app`)

A static `index.html` with `<h1>Hello World</h1>` served by nginx, the same idea as the Apache app but with the other common web server.

```dockerfile
# Nginx Hello World - static page on the official nginx image
FROM nginx:1.27-alpine

# nginx's default web root in this image is /usr/share/nginx/html/.
# Copying our page there replaces the default "Welcome to nginx!" index.
COPY index.html /usr/share/nginx/html/index.html

# nginx listens on 80 inside the container; the base image's CMD starts it in the foreground
EXPOSE 80
```

`FROM nginx:1.27-alpine` is the official nginx image. Its default web root is `/usr/share/nginx/html/`, so `COPY index.html` into that folder replaces the default "Welcome to nginx!" page. `EXPOSE 80` documents the port, and the base image's CMD (`nginx -g "daemon off;"`) is inherited so nginx runs in the foreground and the container stays alive.

```bash
cd session6-7-docker
docker build -t hello-nginx ./nginx-app
docker run -d --name hello-nginx -p 8083:80 hello-nginx
curl -s -i http://localhost:8083
```

```text
===== hello-nginx  ->  $ curl -s -i http://localhost:8083 =====
HTTP/1.1 200 OK
Server: nginx/1.27.5
Date: Thu, 03 Sep 2026 15:05:57 GMT
Content-Type: text/html
Content-Length: 224
Last-Modified: Thu, 03 Sep 2026 15:03:28 GMT
Connection: keep-alive
ETag: "6a998c40-e0"
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Hello World - Nginx</title>
  </head>
  <body>
    <h1>Hello World</h1>
    <p>Served by nginx inside a Docker container.</p>
  </body>
</html>
```

---

## Verification

All raw outputs are also saved as text files in `session6-7-docker/outputs/`:

- `fundamentals-build.txt` - tail of each `docker build` log
- `fundamentals-docker-images.txt` - the six images
- `fundamentals-docker-ps.txt` - the six running containers
- `fundamentals-curl.txt` - all six `curl -s -i` responses
- `fundamentals-react-bundle-check.txt` - proof that the React bundle contains "Hello World"

### Build results

Key lines pulled from the real build logs (`docker build --progress=plain ...`). The full tails are in `outputs/fundamentals-build.txt`.

```text
--- hello-nodejs ---
#10 naming to docker.io/library/hello-nodejs:latest done
--- hello-python ---
#10 naming to docker.io/library/hello-python:latest done
--- hello-java ---
#11 56.90 [INFO] BUILD SUCCESS
#13 1.189 [INFO] Building jar: /app/target/hello-java.jar
#13 1.205 [INFO] BUILD SUCCESS
#15 naming to docker.io/library/hello-java:latest done
--- hello-apache ---
#7 naming to docker.io/library/hello-apache:latest done
--- hello-react ---
#12 0.874 ✓ built in 552ms
#14 naming to docker.io/library/hello-react:latest done
--- hello-nginx ---
#7 naming to docker.io/library/hello-nginx:latest done
```

### Images

```text
$ docker images --filter reference='hello-*'
IMAGE                 ID             DISK USAGE   CONTENT SIZE   EXTRA
hello-apache:latest   f67446cd6794        105MB         21.1MB   U    
hello-java:latest     5875e646d33b        446MB          108MB   U    
hello-nginx:latest    2cabd0d85e6d       75.9MB         21.8MB   U    
hello-nodejs:latest   8d1ffd671e3e        210MB         51.6MB   U    
hello-python:latest   7bca0dff260d        248MB         54.9MB   U    
hello-react:latest    a333a911df48       76.1MB         21.9MB   U    
```

### Running containers

```text
$ docker ps --filter name=hello- --format 'table {{.Names}}	{{.Image}}	{{.Status}}	{{.Ports}}'
NAMES          IMAGE          STATUS          PORTS
hello-nginx    hello-nginx    Up 32 seconds   0.0.0.0:8083->80/tcp, [::]:8083->80/tcp
hello-react    hello-react    Up 32 seconds   0.0.0.0:8082->80/tcp, [::]:8082->80/tcp
hello-apache   hello-apache   Up 32 seconds   0.0.0.0:8081->80/tcp, [::]:8081->80/tcp
hello-java     hello-java     Up 33 seconds   0.0.0.0:8084->8080/tcp, [::]:8084->8080/tcp
hello-python   hello-python   Up 33 seconds   0.0.0.0:5001->5000/tcp, [::]:5001->5000/tcp
hello-nodejs   hello-nodejs   Up 33 seconds   0.0.0.0:3000->3000/tcp, [::]:3000->3000/tcp
```

### HTTP checks (all six)

Each response is `HTTP/1.1 200 OK` and the body contains `<h1>Hello World</h1>` (for React the heading is rendered by the bundle; see the next section).

```text
===== hello-nodejs  ->  $ curl -s -i http://localhost:3000 =====
HTTP/1.1 200 OK
X-Powered-By: Express
Content-Type: text/html; charset=utf-8
Content-Length: 233
ETag: W/"e9-+VRmuv1x2TGshbJa+HgV9f5l0Yo"
Date: Thu, 03 Sep 2026 15:05:57 GMT
Connection: keep-alive
Keep-Alive: timeout=5

<!DOCTYPE html>
<html lang="en">
  <head><meta charset="utf-8"><title>Hello World - Node.js</title></head>
  <body>
    <h1>Hello World</h1>
    <p>Served by Node.js v20.20.2 + Express inside a Docker container.</p>
  </body>
</html>

===== hello-python  ->  $ curl -s -i http://localhost:5001 =====
HTTP/1.1 200 OK
Server: Werkzeug/3.1.8 Python/3.11.16
Date: Thu, 03 Sep 2026 15:05:57 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 228
Connection: close

<!DOCTYPE html>
<html lang="en">
  <head><meta charset="utf-8"><title>Hello World - Python</title></head>
  <body>
    <h1>Hello World</h1>
    <p>Served by Python 3.11.16 + Flask inside a Docker container.</p>
  </body>
</html>

===== hello-java  ->  $ curl -s -i http://localhost:8084 =====
HTTP/1.1 200 OK
Date: Thu, 03 Sep 2026 15:05:57 GMT
Content-type: text/html; charset=utf-8
Content-length: 242

<!DOCTYPE html>
<html lang="en">
  <head><meta charset="utf-8"><title>Hello World - Java</title></head>
  <body>
    <h1>Hello World</h1>
    <p>Served by Java 17.0.20 (com.sun.net.httpserver) inside a Docker container.</p>
  </body>
</html>


===== hello-apache  ->  $ curl -s -i http://localhost:8081 =====
HTTP/1.1 200 OK
Date: Thu, 03 Sep 2026 15:05:57 GMT
Server: Apache/2.4.68 (Unix)
Last-Modified: Thu, 03 Sep 2026 15:03:12 GMT
ETag: "f6-65a9573576c00"
Accept-Ranges: bytes
Content-Length: 246
Content-Type: text/html

<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Hello World - Apache</title>
  </head>
  <body>
    <h1>Hello World</h1>
    <p>Served by Apache HTTP Server (httpd) inside a Docker container.</p>
  </body>
</html>


===== hello-react  ->  $ curl -s -i http://localhost:8082 =====
HTTP/1.1 200 OK
Server: nginx/1.27.5
Date: Thu, 03 Sep 2026 15:05:57 GMT
Content-Type: text/html
Content-Length: 406
Last-Modified: Thu, 03 Sep 2026 15:05:11 GMT
Connection: keep-alive
ETag: "6a998ca7-196"
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Hello World - React</title>
    <script type="module" crossorigin src="/assets/index-C2JW_ARs.js"></script>
  </head>
  <body>
    <div id="root"></div>
    <!-- Vite replaces this with the hashed production bundle at build time -->
  </body>
</html>


===== hello-nginx  ->  $ curl -s -i http://localhost:8083 =====
HTTP/1.1 200 OK
Server: nginx/1.27.5
Date: Thu, 03 Sep 2026 15:05:57 GMT
Content-Type: text/html
Content-Length: 224
Last-Modified: Thu, 03 Sep 2026 15:03:28 GMT
Connection: keep-alive
ETag: "6a998c40-e0"
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Hello World - Nginx</title>
  </head>
  <body>
    <h1>Hello World</h1>
    <p>Served by nginx inside a Docker container.</p>
  </body>
</html>


```

### React bundle check

```text
$ curl -s http://localhost:8082/
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Hello World - React</title>
    <script type="module" crossorigin src="/assets/index-C2JW_ARs.js"></script>
  </head>
  <body>
    <div id="root"></div>
    <!-- Vite replaces this with the hashed production bundle at build time -->
  </body>
</html>


$ BUNDLE=$(curl -s http://localhost:8082/ | grep -o "/assets/index-[^\"]*\.js"); echo "$BUNDLE"
/assets/index-C2JW_ARs.js

$ curl -s -o /dev/null -w 'HTTP %{http_code}  %{size_download} bytes
' http://localhost:8082/assets/index-C2JW_ARs.js
HTTP 200  142792 bytes

$ curl -s http://localhost:8082/assets/index-C2JW_ARs.js | grep -o 'Hello World' | head -1
Hello World

$ curl -s http://localhost:8082/assets/index-C2JW_ARs.js | grep -o '.\{60\}Hello World.\{60\}'
d(){return Sn.jsxs("main",{children:[Sn.jsx("h1",{children:"Hello World"}),Sn.jsx("p",{children:"Served by React 18 + Vite, built a
```

---

## What I understood

An image is the read-only, layered template that `docker build` produces from a Dockerfile; a container is a running (or stopped) instance of that image with its own writable layer, process, and network namespace. I built six images and started six containers, and I could start a second container from the same image without rebuilding anything. Each Dockerfile instruction creates a layer, and Docker caches layers as long as the instruction and its inputs have not changed. That is why I always `COPY package.json` (or `requirements.txt`, or `pom.xml`) and install dependencies before `COPY . .`: when I only edit application code, the expensive install layer is reused and the rebuild takes seconds. I saw this clearly with Java, where `mvn dependency:go-offline` took about 57 seconds the first time while the actual `mvn package` afterwards took about one second.

`EXPOSE` in a Dockerfile is only documentation of the port the process listens on inside the container; it does not open anything on my Mac. The actual mapping is done at run time with `-p host:container`, which is why I could run the Python app on port 5000 inside the container but reach it at 5001 on the host. I had to do that because macOS AirPlay Receiver already occupies port 5000, so `-p 5000:5000` would either fail or hit the wrong service. Multi-stage builds (Java and React) let me use one heavy image with Maven or Node to compile and then `COPY --from=build` just the artifact into a small runtime image; the final images contain no compilers, no `node_modules`, and no source, which makes them smaller and reduces what an attacker could reach. Finally, on Apple Silicon I need multi-arch base images; `eclipse-temurin:17-jre-alpine` is amd64-only, so I used `eclipse-temurin:17-jre` instead.

---

## Summary

| Assignment requirement | Where it is satisfied |
|---|---|
| Separate folders named exactly `nodejs-app`, `python-app`, `java-app`, `Apache-app`, `React-app`, `nginx-app` | The six folders under `session6-7-docker/` |
| Application code for each app | `nodejs-app/server.js`, `python-app/app.py`, `java-app/src/main/java/com/example/HelloServer.java`, `Apache-app/index.html`, `React-app/src/App.jsx`, `nginx-app/index.html` |
| A Dockerfile per application | `Dockerfile` in each of the six folders (shown above) |
| Build the Docker image | `docker build -t hello-<name> ./<folder>` for each; results in `outputs/fundamentals-build.txt` and `outputs/fundamentals-docker-images.txt` |
| Run the application using Docker | `docker run -d --name hello-<name> -p <host>:<container> hello-<name>`; `outputs/fundamentals-docker-ps.txt` shows all six up |
| Verify that "Hello World" is displayed | `curl -s -i` on each host port returns 200 with `<h1>Hello World</h1>` (`outputs/fundamentals-curl.txt`); React verified via its JS bundle (`outputs/fundamentals-react-bundle-check.txt`) |
| Maintain the folder structure and push | All app folders, Dockerfiles, this document, and `outputs/` live under `session6-7-docker/`, ready to commit |
