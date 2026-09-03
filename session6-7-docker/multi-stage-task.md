# Docker Images - Multi-Stage Build Homework

**Name:** Rudhar Bajaj
**Enrollment Number:** YOUR_NUMBER_HERE
**Environment:** macOS 26.5.2 (Apple Silicon), Docker Desktop, Docker Engine 29.6.1 linux/arm64

The three tasks are: run the multi-stage Dockerfile shared in the course repo,
document it, and deploy at least three different types of applications with
Docker. All command output below is real output from my machine; the raw
captures are in [`outputs/`](outputs) (files starting with `multistage-`).

## Contents

1. [Task 1 - Run the multi-stage Dockerfile](#task-1---run-the-multi-stage-dockerfile)
2. [Task 2 - Documentation](#task-2---documentation)
3. [Task 3 - Deploy three or more application types](#task-3---deploy-three-or-more-application-types)
4. [What I understood](#what-i-understood)
5. [Cleanup](#cleanup)
6. [Summary](#summary)

---

## Task 1 - Run the multi-stage Dockerfile

### Where the Dockerfile comes from

The repository containing the multi-stage Dockerfile is the course repo
`Nency-Ravaliya/devops-heros`. I forked it to `rudhar07/devops-heros` and
cloned my fork, so the Dockerfile is at
[`multi-stage-dockerfile/Dockerfile`](multi-stage-dockerfile/Dockerfile) in this
same folder, together with `server.js` and `package.json`. I did not modify any
of the three files.

```bash
git clone git@github.com:rudhar07/devops-heros.git
cd devops-heros/session6-7-docker/multi-stage-dockerfile
```

### The Dockerfile

```dockerfile
# -------------------------
# Stage 1: Build
# -------------------------
FROM node:24-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .

# -------------------------
# Stage 2: Production
# -------------------------
FROM node:24-alpine AS production
WORKDIR /app
COPY --from=builder /app/package*.json ./
RUN npm install --omit=dev
COPY --from=builder /app/server.js ./
EXPOSE 3000
CMD ["npm", "start"]
```

Two `FROM` lines means two stages:

- **Stage 1, `builder`:** starts from `node:24-alpine`, copies `package.json`,
  runs `npm install` (all dependencies, including any dev dependencies), then
  copies the whole source tree.
- **Stage 2, `production`:** starts again from a clean `node:24-alpine`. It
  copies only `package*.json` and `server.js` from the builder with
  `COPY --from=builder`, installs production dependencies only
  (`npm install --omit=dev`), documents port 3000 with `EXPOSE`, and starts the
  app with `npm start`. Everything else from stage 1 (dev dependencies, build
  cache, any files that were not explicitly copied) is left behind, and only the
  last stage becomes the image.

The application itself is a one-route Express server:

```javascript
const express = require("express");

const app = express();
const PORT = 3000;

app.get("/", (req, res) => {
  res.send("<h1>Hello World from Docker Multi-Stage Build!</h1>");
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
```

### Build the image

```bash
docker build -t multi-stage-app .
```

Real output (trimmed to the last lines, full tail in
`outputs/multistage-build.txt`). I also built only the first stage with
`--target builder` to compare the two images.

```text
$ docker build -t multi-stage-app .
#8 DONE 2.5s
#9 [builder 5/5] COPY . .
#9 DONE 0.0s
#10 [production 3/5] COPY --from=builder /app/package*.json ./
#10 DONE 0.0s
#11 [production 4/5] RUN npm install --omit=dev
#11 0.891 
#11 0.891 added 68 packages, and audited 69 packages in 744ms
#11 0.891 
#11 0.891 27 packages are looking for funding
#11 0.891   run `npm fund` for details
#11 0.891 
#11 0.891 found 0 vulnerabilities
#11 0.892 npm notice
#11 0.892 npm notice New major version of npm available! 11.19.0 -> 12.0.2
#11 0.892 npm notice Changelog: https://github.com/npm/cli/releases/tag/v12.0.2
#11 0.892 npm notice To update run: npm install -g npm@12.0.2
#11 0.892 npm notice
#11 DONE 0.9s
#12 [production 5/5] COPY --from=builder /app/server.js ./
#12 DONE 0.0s
#13 exporting to image
#13 exporting layers 0.1s done
#13 exporting manifest sha256:2719173a4101aeefc0e8d163a909ce1ab910a76a88d056101298e97670bbfcff done
#13 exporting config sha256:b65f570434b5920931c6a649469c6325b634e39d7434f2fe33c6eb368ad4a6e6 done
#13 exporting attestation manifest sha256:b0b682362b41fe44aa94f3123f60e4a2714453d1a6ce034dbb24805de69a0138 done
#13 exporting manifest list sha256:60e80dd7228fef91812db3b3b10528000fa48e9efa4af2915dedd8ce340ffb9a done
#13 naming to docker.io/library/multi-stage-app:latest done
#13 unpacking to docker.io/library/multi-stage-app:latest 0.1s done
#13 DONE 0.3s

$ docker build --target builder -t multi-stage-app:builder-only .
#10 exporting manifest list sha256:ec848f23ff0f4f3be91190ffb7f1b3e3a03f8923b5093ba39e8607bd5e4ddc1a done
#10 naming to docker.io/library/multi-stage-app:builder-only done
#10 unpacking to docker.io/library/multi-stage-app:builder-only 0.1s done
#10 DONE 0.4s

$ docker images multi-stage-app
IMAGE                          ID             DISK USAGE   CONTENT SIZE   EXTRA
multi-stage-app:builder-only   ec848f23ff0f        249MB         61.8MB        
multi-stage-app:latest         60e80dd7228f        243MB         60.9MB        
```

Both images are about the same size here (61 MB content) because this app has
no dev dependencies and nothing to compile, so the production stage removes
almost nothing. The pattern pays off for compiled or bundled apps, which I saw
in the Java and React images in Task 3.

### First attempt and what went wrong

The assignment says the app should run on port 8080, so my first run was:

```bash
docker run -d --name multi-stage-app -p 8080:8080 multi-stage-app
curl -s -i http://localhost:8080
```

`curl` returned nothing at all. `docker logs` explained it:

```text

# Why it was empty: the container was started with -p 8080:8080 but the app listens on 3000 inside.
$ docker logs multi-stage-app

> docker-hello-world@1.0.0 start
> node server.js

Server running on port 3000

$ grep -n "PORT" server.js; grep -n EXPOSE Dockerfile
4:const PORT = 3000;
10:app.listen(PORT, () => {
11:  console.log(`Server running on port ${PORT}`);
18:EXPOSE 3000

$ docker rm -f multi-stage-app
multi-stage-app
```

The server is hard-coded to listen on **3000** inside the container
(`const PORT = 3000;`, `EXPOSE 3000`). `-p 8080:8080` forwards host port 8080 to
container port **8080**, where nothing is listening, so the connection was
accepted by Docker and then dropped. The fix is to publish host port 8080 to
container port 3000, without changing the course files.

### Run the container and access the application

```bash
docker run -d --name multi-stage-app -p 8080:3000 multi-stage-app
curl -s -i http://localhost:8080
```

```text
$ docker run -d --name multi-stage-app -p 8080:3000 multi-stage-app

$ curl -s -i http://localhost:8080
HTTP/1.1 200 OK
X-Powered-By: Express
Content-Type: text/html; charset=utf-8
Content-Length: 51
ETag: W/"33-gCAsBJJtlso/BVPWoV3U/pWC3Ak"
Date: Thu, 03 Sep 2026 15:09:51 GMT
Connection: keep-alive
Keep-Alive: timeout=5

<h1>Hello World from Docker Multi-Stage Build!</h1>

$ curl -s http://localhost:8080
<h1>Hello World from Docker Multi-Stage Build!</h1>

$ curl -s -o /dev/null -w "http_code=%{http_code} time_total=%{time_total}s
" http://localhost:8080
http_code=200 time_total=0.001840s
```

The response is `HTTP/1.1 200 OK` and the body is
`<h1>Hello World from Docker Multi-Stage Build!</h1>`, which is the required
"Hello World from Docker multi-stage build" message. Opening
http://localhost:8080 in the browser shows the same heading.

### Verify with `docker ps` and confirm port 8080

```bash
docker ps --filter name=multi-stage-app
docker port multi-stage-app
docker logs multi-stage-app
```

```text
$ docker ps --filter name=multi-stage-app
CONTAINER ID   IMAGE             COMMAND                  STATUS         PORTS                                         NAMES
261173d4df14   multi-stage-app   "docker-entrypoint.s…"   Up 3 seconds   0.0.0.0:8080->3000/tcp, [::]:8080->3000/tcp   multi-stage-app

$ docker port multi-stage-app
3000/tcp -> 0.0.0.0:8080
3000/tcp -> [::]:8080

$ docker logs multi-stage-app

> docker-hello-world@1.0.0 start
> node server.js

Server running on port 3000

$ docker inspect multi-stage-app --format "{{.State.Status}} started={{.State.StartedAt}} ports={{json .NetworkSettings.Ports}}"
running started=2026-09-03T15:09:48.782563921Z ports={"3000/tcp":[{"HostIp":"0.0.0.0","HostPort":"8080"},{"HostIp":"::","HostPort":"8080"}]}

$ docker image history multi-stage-app --format "table {{.CreatedBy}}	{{.Size}}" | head -8
CREATED BY                                      SIZE
CMD ["npm" "start"]                             0B
EXPOSE [3000/tcp]                               0B
COPY /app/server.js ./ # buildkit               12.3kB
RUN /bin/sh -c npm install --omit=dev # buil…   9.45MB
COPY /app/package*.json ./ # buildkit           45.1kB
WORKDIR /app                                    8.19kB
CMD ["node"]                                    0B

$ docker images multi-stage-app
IMAGE                          ID             DISK USAGE   CONTENT SIZE   EXTRA
multi-stage-app:builder-only   ec848f23ff0f        249MB         61.8MB        
multi-stage-app:latest         60e80dd7228f        243MB         60.9MB   U    
```

The `PORTS` column reads `0.0.0.0:8080->3000/tcp`: the application is reachable
on **port 8080** of the host, and inside the container the process listens on
3000. `docker port` shows the same mapping from the other direction.

---

## Task 2 - Documentation

This file is the documentation for the task. It contains:

- my name and enrollment number (top of the file),
- the output showing the application running successfully
  (`curl -s -i http://localhost:8080` above, saved in
  `outputs/multistage-curl.txt`),
- the `docker ps` output showing the running container published on port 8080
  (`outputs/multistage-ps.txt`).

The assignment allows either screenshots or command output as evidence. I used
command output so that every value in this document is reproducible from the
files in `outputs/`.

---

## Task 3 - Deploy three or more application types

For the "Docker Fundamentals" task I containerised six different application
types in this same folder, each with its own Dockerfile. That work is documented
in detail in [`fundamental-task.md`](fundamental-task.md); this section shows
that all of them run alongside the multi-stage app.

| Folder | Type | Container port | Host port |
| --- | --- | --- | --- |
| `nodejs-app` | Node.js 20 + Express | 3000 | 3000 |
| `python-app` | Python 3.11 + Flask | 5000 | 5001 |
| `java-app` | Java 17, Maven multi-stage build, JRE runtime | 8080 | 8084 |
| `Apache-app` | Apache httpd 2.4, static page | 80 | 8081 |
| `React-app` | React 18 + Vite multi-stage build, nginx runtime | 80 | 8082 |
| `nginx-app` | nginx 1.27, static page | 80 | 8083 |

```bash
# from session6-7-docker/
for d in nodejs-app python-app java-app Apache-app React-app nginx-app; do
  name=hello-$(echo $d | tr 'A-Z' 'a-z' | sed 's/-app//')
  docker build -t $name ./$d
done
docker run -d --name hello-nodejs -p 3000:3000 hello-nodejs
docker run -d --name hello-python -p 5001:5000 hello-python
docker run -d --name hello-java   -p 8084:8080 hello-java
docker run -d --name hello-apache -p 8081:80   hello-apache
docker run -d --name hello-react  -p 8082:80   hello-react
docker run -d --name hello-nginx  -p 8083:80   hello-nginx
```

All seven containers running together, and one HTTP check per port:

```text
$ docker ps --filter name=hello- --filter name=multi-stage-app --format "table {{.Names}}	{{.Image}}	{{.Status}}	{{.Ports}}"
NAMES             IMAGE             STATUS          PORTS
multi-stage-app   multi-stage-app   Up 32 seconds   0.0.0.0:8080->3000/tcp, [::]:8080->3000/tcp
hello-nginx       hello-nginx       Up 4 minutes    0.0.0.0:8083->80/tcp, [::]:8083->80/tcp
hello-react       hello-react       Up 4 minutes    0.0.0.0:8082->80/tcp, [::]:8082->80/tcp
hello-apache      hello-apache      Up 4 minutes    0.0.0.0:8081->80/tcp, [::]:8081->80/tcp
hello-java        hello-java        Up 4 minutes    0.0.0.0:8084->8080/tcp, [::]:8084->8080/tcp
hello-python      hello-python      Up 4 minutes    0.0.0.0:5001->5000/tcp, [::]:5001->5000/tcp
hello-nodejs      hello-nodejs      Up 4 minutes    0.0.0.0:3000->3000/tcp, [::]:3000->3000/tcp

$ for p in 3000 5001 8084 8081 8082 8083 8080; do printf "%-5s " $p; curl -s -o /dev/null -w "%{http_code} " http://localhost:$p; curl -s http://localhost:$p | grep -o "Hello World[^<]*" | head -1; done
3000  200 Hello World - Node.js
5001  200 Hello World - Python
8084  200 Hello World - Java
8081  200 Hello World - Apache
8082  200 Hello World - React
8083  200 Hello World - Nginx
8080  200 Hello World from Docker Multi-Stage Build!
```

Host port 5001 is used for Python because macOS AirPlay Receiver occupies host
port 5000, and the Java app is on 8084 because 8080 is taken by the multi-stage
app from Task 1.

---

## What I understood

A multi-stage Dockerfile is several Dockerfiles chained in one file. Each `FROM`
starts a fresh filesystem, and `COPY --from=<stage>` is the only bridge between
them, so the final image contains exactly what I chose to carry over. The point
is to separate the *build* environment (compilers, Maven, the full `npm install`,
source code) from the *runtime* environment (a JRE, nginx, or just the
production `node_modules`). For this Express app the saving was tiny, because
there was nothing to compile and no dev dependencies. For the Java app in Task 3
the difference is the entire Maven and JDK toolchain, and for the React app the
final image is nginx plus a few static files, with Node and `node_modules` gone.
`docker build --target builder` lets me build and inspect an intermediate stage
on its own, which is useful for debugging.

The port problem taught me the difference between `EXPOSE` and `-p`. `EXPOSE` is
only documentation of the port the process listens on inside the container. `-p
host:container` is what actually publishes it, and the container side must match
the port the process really binds to. When a published port returns nothing,
`docker logs` and `docker port` are the first two commands to run.

---

## Cleanup

```bash
docker rm -f multi-stage-app hello-nodejs hello-python hello-java hello-apache hello-react hello-nginx
docker rmi multi-stage-app multi-stage-app:builder-only
```

## Summary

| Assignment requirement | Where it is satisfied |
| --- | --- |
| Clone the repository containing the multi-stage Dockerfile | Fork of `Nency-Ravaliya/devops-heros`, file `multi-stage-dockerfile/Dockerfile` |
| Build the image using the multi-stage Dockerfile | `docker build -t multi-stage-app .`, `outputs/multistage-build.txt` |
| Run a container from the image | `docker run -d --name multi-stage-app -p 8080:3000 multi-stage-app` |
| Access the application | `curl -s -i http://localhost:8080`, `outputs/multistage-curl.txt` |
| Verify it displays "Hello World from Docker multi-stage build" | Response body `<h1>Hello World from Docker Multi-Stage Build!</h1>` |
| Verify the running container with `docker ps` | `outputs/multistage-ps.txt` |
| Confirm the application is running on port 8080 | `PORTS 0.0.0.0:8080->3000/tcp`, `docker port`, HTTP 200 on localhost:8080 |
| Documentation with name, enrollment number and evidence | This file (Task 2) |
| Deploy at least 3 different application types | Six apps in Task 3, detailed in `fundamental-task.md` |
