# Docker Networking & Volumes - Homework

**Name:** Rudhar Bajaj
**Environment:** macOS 26.5.2 (Apple Silicon), Docker Desktop, Docker Engine 29.6.1 linux/arm64

Every output block below is the real output of a command I ran on my machine on 2026-09-03. The complete, untrimmed transcripts are committed in the `outputs/` folder next to this file. Where I shortened a long listing I say so. The `bind-mount/html/index.html` file used in Task 3 is committed in its final state.

| File | Contents |
|---|---|
| `outputs/task1-setup.txt` | network and container creation |
| `outputs/task1-inspect.txt` | `network ls`, `ps`, `inspect` for the three containers |
| `outputs/task1-connectivity.txt` | ping / nc / wget / getent connectivity tests |
| `outputs/task2-host-network.txt` | Apache with `--network host` and the published-port fallback |
| `outputs/task2-inspect.txt` | inspect output, macOS curl tests, Docker Desktop settings check |
| `outputs/task3-bind-mount.txt` | bind mount creation, first edit |
| `outputs/task3-recheck.txt`, `outputs/task3-propagation.txt` | re-check and timed second edit |
| `outputs/task4-overlay.txt`, `outputs/task4-dns-loadbalancing.txt` | swarm / overlay demo |
| `outputs/cleanup.txt` | cleanup and final state |

---

## Task 1 - Container networking with three networks

I created three user-defined bridge networks and three containers: `frontend` (nginx:alpine), `backend` (nginx:alpine) and `database` (mysql:8.0). The backend is the only container that sits on two networks, so it is the only one that can talk to both the frontend and the database. The frontend and the database have no network in common, so they must not be able to reach each other.

### Topology

```text
 macOS  http://localhost:8090
            |
            v  (published 8090 -> 80)
   +--------------------+
   |  frontend          |  nginx:alpine
   |  172.19.0.2        |
   +--------------------+
            |
   ======== frontend-net  (bridge, 172.19.0.0/16) ========
            |
   +--------------------+
   |  backend           |  nginx:alpine        ======== backend-net (bridge, 172.20.0.0/16) ========
   |  172.19.0.3        |                      (created as the 3rd network; no members - see note)
   |  172.21.0.2        |
   +--------------------+
            |
   ======== database-net (bridge, 172.21.0.0/16) ========
            |
   +--------------------+
   |  database          |  mysql:8.0
   |  172.21.0.3        |
   +--------------------+
```

**Design note on `backend-net`.** The task asks for three networks and for the backend to be on exactly two of them. With only three containers, two networks are enough to build the chain frontend -> backend -> database, so the third network cannot be used by anybody without either putting the backend on three networks or making frontend/database multi-homed. I therefore created `backend-net` as the third required network and left it empty, and I put the backend on `frontend-net` + `database-net`. In a real deployment `backend-net` is where backend-only peers such as a cache or a message queue would live, unreachable from both the edge and the database tier.

### Commands

```bash
docker network create frontend-net
docker network create backend-net
docker network create database-net
docker run -d --name frontend --network frontend-net -p 8090:80 nginx:alpine
docker run -d --name backend  --network frontend-net nginx:alpine
docker network connect database-net backend          # backend is now on 2 networks
docker run -d --name database --network database-net -e MYSQL_ROOT_PASSWORD=root mysql:8.0
```

```text
$ docker network create frontend-net
d435c52ad29963d788d3f0e7bc29e278cebdc50813714114618fda5332909878

$ docker network create backend-net
b23ab390af35954258e04cebc1d202803becb6b79c808c7f039d38fa0d3151f7

$ docker network create database-net
9fe062829511e90da621024387bf47e49267a26776934875c46110101a229505

$ docker run -d --name frontend --network frontend-net -p 8090:80 nginx:alpine
ad59efa255e83f585312a42dde9c17c46dda7dafe4ebfe8b3683d24d673ec13a

$ docker run -d --name backend --network frontend-net nginx:alpine
18c3ab2585afd07c0cb99638bd76f6e280f16848136d9f99626e6016b74aad54

$ docker network connect database-net backend

$ docker run -d --name database --network database-net -e MYSQL_ROOT_PASSWORD=root mysql:8.0
2ca00952a49a16dbcb325a8ae68985950cd7255d75711d7793ffa42e8dd69b08
```

I waited for MySQL to finish its first-time initialisation before testing (log trimmed to the last lines):

```text
$ docker logs database 2>&1 | grep -E 'ready for connections|Entrypoint'
...
2026-09-03 15:05:28+00:00 [Note] [Entrypoint]: MySQL init process done. Ready for start up.
2026-09-03T15:05:28.762664Z 0 [System] [MY-010931] [Server] /usr/sbin/mysqld: ready for connections. Version: '8.0.46'  socket: '/var/run/mysqld/mysqld.sock'  port: 3306  MySQL Community Server - GPL.

$ docker exec database mysqladmin ping -uroot -proot
mysqladmin: [Warning] Using a password on the command line interface can be insecure.
mysqld is alive
```

### Networks and containers

```bash
docker network ls
docker ps --filter name=^frontend$ --filter name=^backend$ --filter name=^database$ \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Networks}}'
docker inspect backend --format '{{json .NetworkSettings.Networks}}' | jq 'to_entries[] | {network: .key, ip: .value.IPAddress, gateway: .value.Gateway}'
docker network inspect frontend-net backend-net database-net \
  --format '{{.Name}}: driver={{.Driver}} subnet={{range .IPAM.Config}}{{.Subnet}}{{end}} containers=[{{range .Containers}}{{.Name}} {{end}}]'
```

```text
$ docker network ls
NETWORK ID     NAME           DRIVER    SCOPE
b23ab390af35   backend-net    bridge    local
f97de1351b5c   bridge         bridge    local
9fe062829511   database-net   bridge    local
d435c52ad299   frontend-net   bridge    local
4321bfb79d1e   grr_default    bridge    local
1e633e39c71a   host           host      local
91d8a28dc325   none           null      local

$ docker ps --filter name=^frontend$ --filter name=^backend$ --filter name=^database$ --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Networks}}'
NAMES      IMAGE          STATUS         PORTS                                     NETWORKS
database   mysql:8.0      Up 2 minutes   3306/tcp, 33060/tcp                       database-net
backend    nginx:alpine   Up 2 minutes   80/tcp                                    database-net,frontend-net
frontend   nginx:alpine   Up 2 minutes   0.0.0.0:8090->80/tcp, [::]:8090->80/tcp   frontend-net

$ docker inspect backend --format '{{json .NetworkSettings.Networks}}' | jq 'to_entries[] | {network: .key, ip: .value.IPAddress, gateway: .value.Gateway}'
{
  "network": "database-net",
  "ip": "172.21.0.2",
  "gateway": "172.21.0.1"
}
{
  "network": "frontend-net",
  "ip": "172.19.0.3",
  "gateway": "172.19.0.1"
}

$ docker inspect frontend --format 'frontend: {{range $k,$v := .NetworkSettings.Networks}}{{$k}}={{$v.IPAddress}} {{end}}'
frontend: frontend-net=172.19.0.2

$ docker inspect backend --format 'backend:  {{range $k,$v := .NetworkSettings.Networks}}{{$k}}={{$v.IPAddress}} {{end}}'
backend:  database-net=172.21.0.2 frontend-net=172.19.0.3

$ docker inspect database --format 'database: {{range $k,$v := .NetworkSettings.Networks}}{{$k}}={{$v.IPAddress}} {{end}}'
database: database-net=172.21.0.3

$ docker network inspect frontend-net backend-net database-net --format '{{.Name}}: driver={{.Driver}} subnet={{range .IPAM.Config}}{{.Subnet}}{{end}} containers=[{{range .Containers}}{{.Name}} {{end}}]'
frontend-net: driver=bridge subnet=172.19.0.0/16 containers=[backend frontend ]
backend-net: driver=bridge subnet=172.20.0.0/16 containers=[]
database-net: driver=bridge subnet=172.21.0.0/16 containers=[backend database ]
```

### Connectivity tests

```bash
docker exec frontend ping -c 3 backend
docker exec backend  ping -c 3 frontend
docker exec backend  ping -c 3 database
docker exec frontend ping -c 3 database            # expected to fail
docker exec database getent hosts backend          # mysql image has no ping, so I test name resolution
docker exec database getent hosts frontend         # expected to fail
docker exec backend  nc -zv database 3306
docker exec backend  wget -qO- http://frontend | head -5
docker exec frontend wget -qO- --timeout=3 http://database:3306   # expected to fail
docker exec database mysql -uroot -proot -e 'SELECT VERSION() AS version, @@hostname AS hostname;'
curl -s -o /dev/null -w 'frontend via published port 8090 -> HTTP %{http_code}\n' http://localhost:8090
```

```text
$ docker exec frontend ping -c 3 backend
PING backend (172.19.0.3): 56 data bytes
64 bytes from 172.19.0.3: seq=0 ttl=64 time=0.758 ms
64 bytes from 172.19.0.3: seq=1 ttl=64 time=0.172 ms
64 bytes from 172.19.0.3: seq=2 ttl=64 time=0.322 ms

--- backend ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 0.172/0.417/0.758 ms

$ docker exec backend ping -c 3 frontend
PING frontend (172.19.0.2): 56 data bytes
64 bytes from 172.19.0.2: seq=0 ttl=64 time=0.089 ms
64 bytes from 172.19.0.2: seq=1 ttl=64 time=0.223 ms
64 bytes from 172.19.0.2: seq=2 ttl=64 time=0.373 ms

--- frontend ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 0.089/0.228/0.373 ms

$ docker exec backend ping -c 3 database
PING database (172.21.0.3): 56 data bytes
64 bytes from 172.21.0.3: seq=0 ttl=64 time=0.196 ms
64 bytes from 172.21.0.3: seq=1 ttl=64 time=0.162 ms
64 bytes from 172.21.0.3: seq=2 ttl=64 time=0.182 ms

--- database ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 0.162/0.180/0.196 ms

$ docker exec frontend ping -c 3 database
ping: bad address 'database'
[exit code: 1]

$ docker exec database getent hosts backend
172.21.0.2      backend

$ docker exec database getent hosts frontend
[exit code: 2]

$ docker exec backend nc -zv database 3306
database (172.21.0.3:3306) open

$ docker exec backend wget -qO- http://frontend | head -5
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>

$ docker exec frontend wget -qO- --timeout=3 http://database:3306
wget: bad address 'database:3306'
[exit code: 1]

$ docker exec database mysql -uroot -proot -e 'SELECT VERSION() AS version, @@hostname AS hostname;'
mysql: [Warning] Using a password on the command line interface can be insecure.
version	hostname
8.0.46	2ca00952a49a

$ curl -s -o /dev/null -w 'frontend via published port 8090 -> HTTP %{http_code}\n' http://localhost:8090
frontend via published port 8090 -> HTTP 200
```

### Results

| # | From | To | Test | Expected | Result |
|---|---|---|---|---|---|
| 1 | frontend | backend | `ping -c 3` | reachable (share `frontend-net`) | PASS - 3/3 replies, 0% loss |
| 2 | backend | frontend | `ping -c 3` | reachable | PASS - 3/3 replies |
| 3 | backend | database | `ping -c 3` | reachable (share `database-net`) | PASS - 3/3 replies |
| 4 | frontend | database | `ping -c 3` | blocked (no common network) | PASS - fails as expected: `bad address 'database'` |
| 5 | database | backend | `getent hosts` | resolves | PASS - `172.21.0.2 backend` |
| 6 | database | frontend | `getent hosts` | does not resolve | PASS - fails as expected (exit 2) |
| 7 | backend | database:3306 | `nc -zv` | port open | PASS - `open` |
| 8 | backend | frontend:80 | `wget` | nginx page | PASS - HTML returned |
| 9 | frontend | database:3306 | `wget` | blocked | PASS - fails as expected: `bad address` |
| 10 | macOS | frontend:8090 | `curl` | HTTP 200 | PASS - 200 |

### What I understood

Each user-defined bridge network is its own Linux bridge with its own subnet (172.19, 172.20 and 172.21 here), and Docker's embedded DNS only answers for containers that share a network with the asker, which is why `frontend` cannot even resolve the name `database`. Isolation between tiers is therefore enforced by the network layout itself rather than by firewall rules I have to maintain. A container can be attached to several networks with `docker network connect`, and it then gets one interface and one IP per network, which is exactly what made `backend` the bridge between the edge and the data tier. I also noticed that the mysql image ships without ping, so I verified reachability with `getent hosts` from that side and with `nc -zv` on port 3306 from the backend. The published port on the frontend is the only way traffic from my laptop enters this topology.

---

## Task 2 - Host network with Apache

I pulled `httpd:2.4` and ran it with `--network host`, then checked how it can be reached from inside Docker and from macOS. Because Docker Desktop runs the engine in a Linux VM, this task behaves differently on a Mac than on a Linux server, and I documented what I actually observed.

### Commands

```bash
docker pull httpd:2.4
docker run -d --name apache-host --network host httpd:2.4
docker ps --filter name=^apache- --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Networks}}'
docker inspect apache-host --format 'NetworkMode={{.HostConfig.NetworkMode}} PortBindings={{json .HostConfig.PortBindings}} ...'
docker exec apache-host curl -s -i http://localhost:80 | head -12      # image has no curl
docker exec apache-host bash -c 'exec 3<>/dev/tcp/127.0.0.1/80; printf "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n" >&3; cat <&3'
docker run --rm --network host alpine wget -S -qO- http://localhost:80
docker run --rm --network host alpine sh -c 'hostname; ip -4 addr show | grep inet'
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:80            # from macOS
curl -sv http://localhost:80 2>&1 | head -10                           # from macOS
```

```text
$ docker pull httpd:2.4
2.4: Pulling from library/httpd
Digest: sha256:979c38c2228d28c2edfd45c6e27dcee1c7b4a101a5526721ae8ece454e89e99e
Status: Image is up to date for httpd:2.4
docker.io/library/httpd:2.4

$ docker run -d --name apache-host --network host httpd:2.4
088411b738930314393edf9885a06004df523478c4b6ecd785829f39a58dc526

$ docker ps --filter name=^apache- --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Networks}}'
NAMES              IMAGE       STATUS         PORTS                                     NETWORKS
apache-published   httpd:2.4   Up 2 minutes   0.0.0.0:8095->80/tcp, [::]:8095->80/tcp   bridge
apache-host        httpd:2.4   Up 2 minutes                                             host

$ docker inspect apache-host --format 'apache-host:      NetworkMode={{.HostConfig.NetworkMode}} PortBindings={{json .HostConfig.PortBindings}} Networks=[{{range $k,$v := .NetworkSettings.Networks}}{{$k}} ip="{{$v.IPAddress}}"{{end}}]'
apache-host:      NetworkMode=host PortBindings={} Networks=[host ip="invalid IP"]

$ docker exec apache-host curl -s -i http://localhost:80 | head -12
OCI runtime exec failed: exec failed: unable to start container process: exec: "curl": executable file not found in $PATH

$ docker exec apache-host bash -c 'exec 3<>/dev/tcp/127.0.0.1/80; printf "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n" >&3; cat <&3'
HTTP/1.1 200 OK
Date: Thu, 03 Sep 2026 15:05:37 GMT
Server: Apache/2.4.68 (Unix)
Last-Modified: Fri, 07 Nov 2025 08:23:08 GMT
ETag: "bf-642fce432f300"
Accept-Ranges: bytes
Content-Length: 191
Connection: close
Content-Type: text/html

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<title>It works! Apache httpd</title>
</head>
<body>
<p>It works!</p>
</body>
</html>

$ docker run --rm --network host alpine wget -S -qO- http://localhost:80
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<title>It works! Apache httpd</title>
</head>
<body>
<p>It works!</p>
</body>
</html>
  HTTP/1.1 200 OK
  Date: Thu, 03 Sep 2026 15:05:37 GMT
  Server: Apache/2.4.68 (Unix)
  Last-Modified: Fri, 07 Nov 2025 08:23:08 GMT
  ETag: "bf-642fce432f300"
  Accept-Ranges: bytes
  Content-Length: 191
  Connection: close
  Content-Type: text/html

$ docker run --rm --network host alpine sh -c 'hostname; ip -4 addr show | grep inet'
docker-desktop
    inet 127.0.0.1/8 scope host lo
    inet 192.168.65.3/24 brd 192.168.65.255 scope global eth0
    inet 192.168.65.6/32 scope global services1
    inet 172.18.0.1/16 brd 172.18.255.255 scope global br-4321bfb79d1e
    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0
    inet 172.19.0.1/16 brd 172.19.255.255 scope global br-d435c52ad299
    inet 172.20.0.1/16 brd 172.20.255.255 scope global br-b23ab390af35
    inet 172.21.0.1/16 brd 172.21.255.255 scope global br-9fe062829511

$ curl -s -o /dev/null -w '%{http_code}\n' http://localhost:80
000
[exit code: 7]

$ curl -sv http://localhost:80 2>&1 | head -10
* Host localhost:80 was resolved.
* IPv6: ::1
* IPv4: 127.0.0.1
*   Trying [::1]:80...
* connect to ::1 port 80 from ::1 port 51134 failed: Connection refused
*   Trying 127.0.0.1:80...
* connect to 127.0.0.1 port 80 from 127.0.0.1 port 51135 failed: Connection refused
* Failed to connect to localhost port 80 after 0 ms: Couldn't connect to server
* Closing connection
```

(The raw transcript also contains one `docker inspect` call that failed with `map has no entry for key "IPAddress"`: Docker 29 no longer exposes the legacy top-level `.NetworkSettings.IPAddress`, so I re-ran it with the per-network template shown above.)

### Why macOS `localhost:80` is refused: the Docker Desktop VM

```text
$ docker info --format 'OS={{.OperatingSystem}} OSType={{.OSType}} Arch={{.Architecture}} Kernel={{.KernelVersion}}'
OS=Docker Desktop OSType=linux Arch=aarch64 Kernel=6.12.76-linuxkit

$ docker version --format 'Client={{.Client.Version}} Server={{.Server.Version}} ServerOS={{.Server.Os}}/{{.Server.Arch}}'
Client=29.6.1 Server=29.6.1 ServerOS=linux/arm64

$ jq -c 'keys' "$HOME/Library/Group Containers/group.com.docker/settings-store.json"
["AutoStart","DisplayedOnboarding","DockerAppLaunchPath","EnableDockerAI","LastContainerdSnapshotterEnable","LicenseTermsVersion","SettingsVersion","ShowInstallScreen","UseContainerdSnapshotter","UseVirtualizationFrameworkRosetta"]

$ jq -c 'to_entries[] | select(.key|test("host|network";"i"))' "$HOME/Library/Group Containers/group.com.docker/settings-store.json"; echo "(no keys matched: host networking is not enabled / at default)"
(no keys matched: host networking is not enabled / at default)
```

```text
   macOS (my laptop)
   curl http://localhost:80   -> Connection refused (000, exit 7)
   curl http://localhost:8095 -> HTTP 200 (published port is forwarded by Docker Desktop)
        |
        | virtualisation boundary
        v
   +---------------- Linux VM "docker-desktop" (192.168.65.3, kernel 6.12 linuxkit) ----------------+
   |  apache-host      --network host   -> shares the VM's namespace, listens on the VM's :80       |
   |  apache-published -p 8095:80       -> bridge 172.17.0.10:80, NAT/forwarded to the Mac's :8095  |
   +------------------------------------------------------------------------------------------------+
```

The "host" that `--network host` refers to is the Linux kernel that runs the Docker daemon. On my Mac that kernel belongs to Docker Desktop's VM (hostname `docker-desktop`, IP 192.168.65.3), not to macOS. That is why everything I ran *inside* the VM (the `bash /dev/tcp` request from the container itself and the `alpine --network host` helper) got `HTTP/1.1 200 OK` from Apache on port 80, while `curl http://localhost:80` from macOS was refused: nothing on macOS listens on port 80, and Docker Desktop does not forward host-mode ports by default. Docker Desktop has an opt-in setting ("Enable host networking" under Settings > Resources > Network) that would make host-networked containers reachable from the Mac; my `settings-store.json` has no such key, so it is at its default (off), and I did not turn it on because I wanted to document the default behaviour. On a native Linux host the same `docker run --network host httpd:2.4` would make `http://localhost:80` work immediately.

### Published-port fallback so the page is reachable from a browser

```bash
docker run -d --name apache-published -p 8095:80 httpd:2.4
curl -s --retry 10 --retry-connrefused --retry-delay 1 -i http://localhost:8095
curl -s -o /dev/null -w 'macOS -> http://localhost:8095 HTTP %{http_code} (curl exit %{exitcode})\n' http://localhost:8095
```

```text
$ docker run -d --name apache-published -p 8095:80 httpd:2.4
dc325de3c37784caa1cb2475911b3749c334658582d04b96764d70e235229943

$ curl -s --retry 10 --retry-connrefused --retry-delay 1 -i http://localhost:8095
HTTP/1.1 200 OK
Date: Thu, 03 Sep 2026 15:05:38 GMT
Server: Apache/2.4.68 (Unix)
Last-Modified: Fri, 07 Nov 2025 08:23:08 GMT
ETag: "bf-642fce432f300"
Accept-Ranges: bytes
Content-Length: 191
Content-Type: text/html

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<title>It works! Apache httpd</title>
</head>
<body>
<p>It works!</p>
</body>
</html>

$ docker inspect apache-published --format 'apache-published: NetworkMode={{.HostConfig.NetworkMode}} PortBindings={{json .HostConfig.PortBindings}} Networks=[{{range $k,$v := .NetworkSettings.Networks}}{{$k}} ip="{{$v.IPAddress}}"{{end}}]'
apache-published: NetworkMode=bridge PortBindings={"80/tcp":[{"HostIp":"","HostPort":"8095"}]} Networks=[bridge ip="172.17.0.10"]

$ curl -s -o /dev/null -w 'macOS -> http://localhost:80   HTTP %{http_code} (curl exit %{exitcode})\n' http://localhost:80
macOS -> http://localhost:80   HTTP 000 (curl exit 7)
[exit code: 7]

$ curl -s -o /dev/null -w 'macOS -> http://localhost:8095 HTTP %{http_code} (curl exit %{exitcode})\n' http://localhost:8095
macOS -> http://localhost:8095 HTTP 200 (curl exit 0)
```

### Results

| Check | Where the request came from | Result |
|---|---|---|
| `docker ps` PORTS column for `apache-host` | - | empty, NETWORKS = `host` (nothing is published, the container uses the host's ports directly) |
| `NetworkMode` in `docker inspect` | - | `host`, `PortBindings={}` |
| `http://localhost:80` | inside the container (`bash /dev/tcp`) | HTTP 200 "It works!" |
| `http://localhost:80` | helper `alpine --network host` inside the VM | HTTP 200 "It works!" |
| `http://localhost:80` | macOS terminal | Connection refused - HTTP 000, curl exit 7 |
| `http://localhost:8095` (`apache-published`, `-p 8095:80`) | macOS terminal | HTTP 200 "It works!" |

### What I understood

`--network host` removes the network namespace boundary: the container has no IP of its own, nothing appears in the PORTS column, and Apache simply binds port 80 on whatever kernel the daemon runs on. That is convenient and fast (no NAT), but it also means no port isolation, and two host-mode containers cannot both bind port 80. The surprise for me was that on Docker Desktop the "host" is a hidden Linux VM, so the port was open inside the VM but not on macOS; I proved both sides with real requests rather than assuming. If I need a host-mode service reachable from the Mac I either enable Docker Desktop's host-networking option or, as I did here, fall back to a published port, which Docker Desktop forwards from the Mac into the VM.

---

## Task 3 - Bind mount with live edits

I created `bind-mount/html/index.html` on my Mac, mounted the folder read-only into an nginx container, changed the file on the host and checked that nginx served the new content without the container being restarted.

### Commands

```bash
cd session8-docker-networking-volume
mkdir -p bind-mount/html
printf '<h1>Hello students</h1>\n' > bind-mount/html/index.html
docker run -d --name nginx-bind -p 8091:80 -v "$PWD/bind-mount/html:/usr/share/nginx/html:ro" nginx:alpine
docker inspect nginx-bind --format '{{json .Mounts}}' | jq
curl -s http://localhost:8091
docker inspect nginx-bind --format 'StartedAt={{.State.StartedAt}} RestartCount={{.RestartCount}} Pid={{.State.Pid}}'
printf '<p>Updated on the host without restarting the container</p>\n' >> bind-mount/html/index.html
curl -s http://localhost:8091
docker inspect nginx-bind --format 'StartedAt={{.State.StartedAt}} RestartCount={{.RestartCount}} Pid={{.State.Pid}}'
docker exec nginx-bind cat /usr/share/nginx/html/index.html
docker exec nginx-bind sh -c 'echo hacked >> /usr/share/nginx/html/index.html'   # must fail: mounted :ro
```

```text
$ pwd
/Users/rudhar/Desktop/NIFTY/Devops/hw-1/devops-heros/session8-docker-networking-volume

$ mkdir -p bind-mount/html

$ printf '<h1>Hello students</h1>\n' > bind-mount/html/index.html

$ cat bind-mount/html/index.html
<h1>Hello students</h1>

$ docker run -d --name nginx-bind -p 8091:80 -v "$PWD/bind-mount/html:/usr/share/nginx/html:ro" nginx:alpine
79746f8121f4d4672aa83eb4d1fca2fd706207c3d90b15f3ec926ec22012af9a

$ docker inspect nginx-bind --format '{{json .Mounts}}' | jq
[
  {
    "Type": "bind",
    "Source": "/Users/rudhar/Desktop/NIFTY/Devops/hw-1/devops-heros/session8-docker-networking-volume/bind-mount/html",
    "Destination": "/usr/share/nginx/html",
    "Mode": "ro",
    "RW": false,
    "Propagation": "rprivate"
  }
]

$ curl -s --retry 10 --retry-connrefused --retry-delay 1 http://localhost:8091
<h1>Hello students</h1>

$ docker inspect nginx-bind --format 'StartedAt={{.State.StartedAt}} RestartCount={{.RestartCount}} Pid={{.State.Pid}}'
StartedAt=2026-09-03T15:05:41.368920792Z RestartCount=0 Pid=62073

$ printf '<p>Updated on the host without restarting the container</p>\n' >> bind-mount/html/index.html

$ cat bind-mount/html/index.html
<h1>Hello students</h1>
<p>Updated on the host without restarting the container</p>

$ curl -s http://localhost:8091
<h1>Hello students</h1>

$ docker inspect nginx-bind --format 'StartedAt={{.State.StartedAt}} RestartCount={{.RestartCount}} Pid={{.State.Pid}}'
StartedAt=2026-09-03T15:05:41.368920792Z RestartCount=0 Pid=62073

$ docker exec nginx-bind cat /usr/share/nginx/html/index.html
<h1>Hello students</h1>
<p>Updated on the host without restarting the container</p>

$ docker exec nginx-bind sh -c 'echo hacked >> /usr/share/nginx/html/index.html'
sh: can't create /usr/share/nginx/html/index.html: Read-only file system
[exit code: 1]
```

**An honest observation.** The `curl` I ran immediately after the append (my script fired it a few milliseconds after the write) still returned the old one-line body, even though `docker exec cat` a moment later already showed the new content. I did not want to hide that, so I re-checked and then measured the delay.

### Re-check and timed second edit

```bash
curl -si http://localhost:8091
stat -f 'host:      size=%z mtime=%Sm' bind-mount/html/index.html
docker exec nginx-bind stat -c 'container: size=%s mtime=%y' /usr/share/nginx/html/index.html
# second edit, then poll nginx (no restart) until the new line is served, timing it
start=$(date +%s.%N); printf "<p>Second edit at %s</p>\n" "$(date -u +%H:%M:%SZ)" >> bind-mount/html/index.html
n=0; while [ $n -lt 3000 ]; do n=$((n+1)); body=$(curl -s http://localhost:8091); case "$body" in *"Second edit"*) break;; esac; done
end=$(date +%s.%N); echo "new content served on poll #$n after $(echo "$end - $start" | bc) s"
```

```text
$ date -u +%Y-%m-%dT%H:%M:%SZ
2026-09-03T15:07:48Z

$ curl -si http://localhost:8091
HTTP/1.1 200 OK
Server: nginx/1.31.5
Date: Thu, 03 Sep 2026 15:07:48 GMT
Content-Type: text/html
Content-Length: 84
Last-Modified: Thu, 03 Sep 2026 15:05:41 GMT
Connection: keep-alive
ETag: "6a998cc5-54"
Accept-Ranges: bytes

<h1>Hello students</h1>
<p>Updated on the host without restarting the container</p>

$ stat -f 'host:      size=%z mtime=%Sm' bind-mount/html/index.html
host:      size=84 mtime=Sep  3 20:35:41 2026

$ docker exec nginx-bind stat -c 'container: size=%s mtime=%y' /usr/share/nginx/html/index.html
container: size=84 mtime=2026-09-03 15:05:41.500454580 +0000

$ docker exec nginx-bind grep -nE 'sendfile|open_file_cache' /etc/nginx/nginx.conf
24:    sendfile        on;

$ curl -s http://localhost:8091
<h1>Hello students</h1>
<p>Updated on the host without restarting the container</p>

$ start=$(date +%s.%N); printf "<p>Second edit at %s</p>\n" "$(date -u +%H:%M:%SZ)" >> bind-mount/html/index.html
$ n=0; while [ $n -lt 3000 ]; do n=$((n+1)); body=$(curl -s http://localhost:8091); case "$body" in *"Second edit"*) break;; esac; done
$ end=$(date +%s.%N); echo "new content served on poll #$n after $(echo "$end - $start" | bc) s"
new content served on poll #2 after .024837000 s

$ cat bind-mount/html/index.html
<h1>Hello students</h1>
<p>Updated on the host without restarting the container</p>
<p>Second edit at 15:09:17Z</p>

$ curl -si http://localhost:8091
HTTP/1.1 200 OK
Server: nginx/1.31.5
Date: Thu, 03 Sep 2026 15:09:17 GMT
Content-Type: text/html
Content-Length: 116
Last-Modified: Thu, 03 Sep 2026 15:09:17 GMT
Connection: keep-alive
ETag: "6a998d9d-74"
Accept-Ranges: bytes

<h1>Hello students</h1>
<p>Updated on the host without restarting the container</p>
<p>Second edit at 15:09:17Z</p>

$ docker inspect nginx-bind --format 'StartedAt={{.State.StartedAt}} RestartCount={{.RestartCount}} Pid={{.State.Pid}}'
StartedAt=2026-09-03T15:05:41.368920792Z RestartCount=0 Pid=62073

$ docker exec nginx-bind cat /usr/share/nginx/html/index.html
<h1>Hello students</h1>
<p>Updated on the host without restarting the container</p>
<p>Second edit at 15:09:17Z</p>
```

### Results

| Step | `index.html` on the host | What nginx served (`curl localhost:8091`) | `StartedAt` / `RestartCount` / `Pid` |
|---|---|---|---|
| Initial | `<h1>Hello students</h1>` | `<h1>Hello students</h1>` | `15:05:41.368920792Z` / 0 / 62073 |
| First edit (append `<p>Updated ...</p>`) | 2 lines, 84 bytes | first curl a few ms later: still 1 line; on re-check: 2 lines, `Content-Length: 84` | `15:05:41.368920792Z` / 0 / 62073 (unchanged) |
| Second edit (append `<p>Second edit ...</p>`) | 3 lines, 116 bytes | new content on poll #2, 0.025 s after the write, `Content-Length: 116` | `15:05:41.368920792Z` / 0 / 62073 (unchanged) |
| Write from inside the container | - | - | rejected: `Read-only file system` (mounted `:ro`) |

The three identical `StartedAt` / `RestartCount=0` / `Pid=62073` readings prove the container was never restarted. The final version of the file (three lines) is the one committed at `bind-mount/html/index.html`.

### What I understood

A bind mount does not copy anything: the container's `/usr/share/nginx/html` *is* my Mac folder, so whatever I write on the host is what nginx reads on its next request, with no image rebuild and no restart, which is why bind mounts are the standard tool for local development. The `:ro` flag gave me a useful safety net, as the container was refused when it tried to write into the folder. The stale first read taught me that on Docker Desktop the folder is shared into the Linux VM through a file-sharing layer (VirtioFS), so a host write becomes visible in the container a few tens of milliseconds later rather than atomically; on a native Linux host the mount is the same kernel path and there is no such gap. I also learned to verify "no restart" with `StartedAt`, `RestartCount` and the process PID instead of trusting the `Up` status text alone.

---

## Task 4 - Overlay networks: research and a local demo

### What problem an overlay network solves

A bridge network exists only inside one Docker host. Each host hands out private addresses (172.17.x, 172.19.x, ...) behind NAT, so a container on host A has no route to a container on host B and cannot resolve its name; the only way across is to publish ports on the hosts and hard-code host IPs. Overlay networks remove that limit: containers on many hosts are attached to one virtual layer-2 segment with a single shared subnet, they resolve each other by name through Docker's embedded DNS, and east-west traffic never has to be published on a host port.

### How it works

* **Data plane: VXLAN.** Every Ethernet frame a container sends is wrapped in a UDP datagram to port 4789 and sent to the physical IP of the host that owns the destination container, where it is unwrapped and delivered. Each overlay network gets its own VXLAN Network Identifier (VNI) and, on every participating host, its own network namespace holding a Linux bridge plus a `vxlan` interface. In my demo `app-overlay` was given VNI 4097 (`com.docker.network.driver.overlay.vxlanid_list`). Because encapsulation adds headers, overlay MTU is typically 1450 instead of 1500.
* **Control plane: swarm mode.** Managers listen on TCP 2377 for cluster management and keep the cluster state in a Raft-replicated store; that store acts as the distributed key-value store for IPAM (which IP/MAC is allocated to which task) and endpoint state, so two hosts never allocate the same address. Nodes exchange network state over a gossip protocol on TCP and UDP 7946, and a host only receives the state of an overlay when it actually runs a task on it. Firewalls between hosts must allow 2377/tcp, 7946/tcp+udp and 4789/udp (plus IP protocol 50 ESP when encryption is on).
* **Encryption.** Gossip traffic is always encrypted; the VXLAN data plane can be encrypted too with `docker network create -d overlay --opt encrypted`, which sets up IPsec ESP tunnels between the nodes, at a CPU cost.
* **Service discovery and load balancing.** The embedded DNS server at 127.0.0.11 resolves a service name to a Virtual IP (VIP); the kernel's IPVS spreads connections to that VIP across the healthy tasks. `tasks.<service>` returns the individual task IPs (DNS round-robin) for clients that want to pick their own backend. The `ingress` overlay plus the routing mesh make a published service port answer on every node.

### Use cases

* Swarm services whose replicas are spread over several nodes for capacity and failover, with rolling updates.
* Multi-host microservice applications where frontend, backend and database tiers run on different machines but must talk by name.
* Built-in service discovery and internal load balancing without an external load balancer.
* `--attachable` overlays let standalone containers (debug shells, one-off jobs, like my `overlay-client`) join a swarm network.
* Isolation per application or tenant: each overlay has its own VNI and subnet, and containers on different overlays cannot see each other.

### Overlay vs bridge

| | bridge (default / user-defined) | overlay |
|---|---|---|
| Scope | one Docker host (`SCOPE=local`) | whole swarm (`SCOPE=swarm`) |
| Requires swarm mode | no | yes (manager keeps the state) |
| Cross-host container traffic | impossible without publishing ports | native, via VXLAN tunnels (UDP 4789) |
| IP allocation | local daemon | cluster-wide IPAM from the manager's Raft store |
| Name resolution | embedded DNS, container names | embedded DNS, service names -> VIP, `tasks.<svc>` -> task IPs |
| Load balancing | none built in | IPVS across tasks, routing mesh for published ports |
| Encryption of traffic | not applicable (same host) | optional `--opt encrypted` (IPsec) |
| Typical use | single-host dev, compose stacks | multi-node services, clustered apps |

### How the same setup would run on several hosts

On a second and third machine I would run the `docker swarm join --token ... 192.168.65.3:2377` command that `swarm init` printed, with the firewall ports above open. Nothing else changes: `docker network create -d overlay` and `docker service create --network app-overlay --replicas 3` are identical, but the scheduler would place the three tasks on different nodes, `docker service ps web-svc` would show different hostnames in the NODE column, and the VXLAN tunnels between the hosts would be created automatically the first time a task on that network lands on a node. Since I have a single node, all three replicas landed on `docker-desktop`; the DNS, VIP and load-balancing behaviour I observed below is the same one that would work across hosts.

### Local single-node demo

```bash
docker swarm init
docker node ls
docker network create -d overlay --attachable app-overlay
docker service create --name web-svc --replicas 3 --network app-overlay nginx:alpine
docker service ls
docker service ps web-svc --format 'table {{.Name}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}'
docker run -d --name overlay-client --network app-overlay alpine tail -f /dev/null
docker exec overlay-client getent hosts web-svc
docker exec overlay-client getent hosts tasks.web-svc
docker exec overlay-client nslookup web-svc
docker exec overlay-client nslookup tasks.web-svc
docker service inspect web-svc --format 'VIP={{range .Endpoint.VirtualIPs}}{{.Addr}} {{end}} EndpointMode={{.Spec.EndpointSpec.Mode}}'
docker exec overlay-client wget -qO- http://web-svc | head -5
docker exec overlay-client sh -c 'for i in 1 2 3 4 5 6; do wget -qO- http://web-svc >/dev/null && echo "request $i via VIP web-svc -> OK"; done'
docker service logs web-svc 2>&1 | grep 'GET / ' | tail -6
docker network inspect app-overlay --format 'Driver={{.Driver}} Scope={{.Scope}} Subnet={{range .IPAM.Config}}{{.Subnet}}{{end}} Attachable={{.Attachable}} VXLAN_ID={{index .Options "com.docker.network.driver.overlay.vxlanid_list"}}'
docker network ls
```

```text
$ docker info --format 'Swarm state before: {{.Swarm.LocalNodeState}}'
Swarm state before: inactive

$ docker swarm init
Swarm initialized: current node (lomcr58ja1vdtvzky2epssgfx) is now a manager.

To add a worker to this swarm, run the following command:

    docker swarm join --token SWMTKN-1-5znd8fq2srx4y7wtg2qwpmnhwkxtbqgymlz0wieo9gm8omvljq-4ogjob2vhybys08k28p9ipngp 192.168.65.3:2377

To add a manager to this swarm, run 'docker swarm join-token manager' and follow the instructions.

$ docker info --format 'Swarm state after: {{.Swarm.LocalNodeState}} (manager={{.Swarm.ControlAvailable}} nodes={{.Swarm.Nodes}})'
Swarm state after: active (manager=true nodes=1)

$ docker node ls
ID                            HOSTNAME         STATUS    AVAILABILITY   MANAGER STATUS   ENGINE VERSION
lomcr58ja1vdtvzky2epssgfx *   docker-desktop   Ready     Active         Leader           29.6.1

$ docker network create -d overlay --attachable app-overlay
vj4pyhw09lsv07zwwn4cgxauc

$ docker service create --name web-svc --replicas 3 --network app-overlay nginx:alpine
hpantyliy5tprcdzrt3t8mi0p
overall progress: 0 out of 3 tasks
...                                   (progress lines trimmed)
overall progress: 3 out of 3 tasks
verify: Waiting 5 seconds to verify that tasks are stable...
...
verify: Service hpantyliy5tprcdzrt3t8mi0p converged

$ docker service ls
ID             NAME      MODE         REPLICAS   IMAGE          PORTS
hpantyliy5tp   web-svc   replicated   3/3        nginx:alpine

$ docker service ps web-svc --format 'table {{.Name}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}'
NAME        NODE             DESIRED STATE   CURRENT STATE
web-svc.1   docker-desktop   Running         Running 5 seconds ago
web-svc.2   docker-desktop   Running         Running 5 seconds ago
web-svc.3   docker-desktop   Running         Running 5 seconds ago

$ docker run -d --name overlay-client --network app-overlay alpine tail -f /dev/null
a1ef2cbbaeb7f662b888dc9d7e0cd03cbfdd883a5e8303ff46a86e6e910d2826

$ docker exec overlay-client getent hosts web-svc
10.0.1.2          web-svc  web-svc

$ docker exec overlay-client getent hosts tasks.web-svc
10.0.1.5          tasks.web-svc  tasks.web-svc

$ docker exec overlay-client nslookup web-svc
Server:		127.0.0.11
Address:	127.0.0.11:53

Non-authoritative answer:
Name:	web-svc
Address: 10.0.1.2

$ docker exec overlay-client nslookup tasks.web-svc
Server:		127.0.0.11
Address:	127.0.0.11:53

Non-authoritative answer:
Name:	tasks.web-svc
Address: 10.0.1.5
Name:	tasks.web-svc
Address: 10.0.1.4
Name:	tasks.web-svc
Address: 10.0.1.3

$ docker service inspect web-svc --format 'VIP={{range .Endpoint.VirtualIPs}}{{.Addr}} {{end}} EndpointMode={{.Spec.EndpointSpec.Mode}}'
VIP=10.0.1.2/24  EndpointMode=vip

$ docker exec overlay-client wget -qO- http://web-svc | head -5
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>

$ docker exec overlay-client sh -c 'for i in 1 2 3 4 5 6; do wget -qO- http://web-svc >/dev/null && echo "request $i via VIP web-svc -> OK"; done'
request 1 via VIP web-svc -> OK
request 2 via VIP web-svc -> OK
request 3 via VIP web-svc -> OK
request 4 via VIP web-svc -> OK
request 5 via VIP web-svc -> OK
request 6 via VIP web-svc -> OK

$ docker service logs web-svc 2>&1 | grep 'GET / ' | tail -6
web-svc.2.7brkvc5i9c8z@docker-desktop    | 10.0.1.6 - - [03/Sep/2026:15:10:24 +0000] "GET / HTTP/1.1" 200 896 "-" "Wget" "-"
web-svc.1.ddb4t1u19ak6@docker-desktop    | 10.0.1.6 - - [03/Sep/2026:15:09:40 +0000] "GET / HTTP/1.1" 200 896 "-" "Wget" "-"
web-svc.1.ddb4t1u19ak6@docker-desktop    | 10.0.1.6 - - [03/Sep/2026:15:10:24 +0000] "GET / HTTP/1.1" 200 896 "-" "Wget" "-"
web-svc.1.ddb4t1u19ak6@docker-desktop    | 10.0.1.6 - - [03/Sep/2026:15:10:24 +0000] "GET / HTTP/1.1" 200 896 "-" "Wget" "-"
web-svc.3.rdpzwmmi5b4a@docker-desktop    | 10.0.1.6 - - [03/Sep/2026:15:10:24 +0000] "GET / HTTP/1.1" 200 896 "-" "Wget" "-"
web-svc.3.rdpzwmmi5b4a@docker-desktop    | 10.0.1.6 - - [03/Sep/2026:15:10:24 +0000] "GET / HTTP/1.1" 200 896 "-" "Wget" "-"

$ docker exec overlay-client ip -4 -o addr show | awk '{print $2, $4}'
lo 127.0.0.1/8
eth0 10.0.1.7/24
eth1 172.22.0.6/16

$ docker network inspect app-overlay --format 'Driver={{.Driver}} Scope={{.Scope}} Subnet={{range .IPAM.Config}}{{.Subnet}}{{end}} Attachable={{.Attachable}} VXLAN_ID={{index .Options "com.docker.network.driver.overlay.vxlanid_list"}}'
Driver=overlay Scope=swarm Subnet=10.0.1.0/24 Attachable=true VXLAN_ID=4097

$ docker network inspect app-overlay --format '{{range $k,$v := .Containers}}{{$v.Name}} {{$v.IPv4Address}}{{println}}{{end}}'
web-svc.2.7brkvc5i9c8zwivrc8xo9dsq0 10.0.1.4/24
web-svc.3.rdpzwmmi5b4ap1ygvnk0855za 10.0.1.5/24
web-svc.1.ddb4t1u19ak6sy7sah3z9n554 10.0.1.3/24
overlay-client 10.0.1.7/24
app-overlay-endpoint 10.0.1.6/24

$ docker network ls
NETWORK ID     NAME              DRIVER    SCOPE
vj4pyhw09lsv   app-overlay       overlay   swarm
b23ab390af35   backend-net       bridge    local
f97de1351b5c   bridge            bridge    local
9fe062829511   database-net      bridge    local
971c6a1189b9   docker_gwbridge   bridge    local
d435c52ad299   frontend-net      bridge    local
4321bfb79d1e   grr_default       bridge    local
1e633e39c71a   host              host      local
kdcslalpw03d   ingress           overlay   swarm
91d8a28dc325   none              null      local

$ docker network inspect ingress --format 'ingress: Driver={{.Driver}} Scope={{.Scope}} Subnet={{range .IPAM.Config}}{{.Subnet}}{{end}}'
ingress: Driver=overlay Scope=swarm Subnet=10.0.0.0/24
```

### Results

| Observation | Evidence |
|---|---|
| Swarm went from `inactive` to `active`, one manager node `docker-desktop` | `docker info`, `docker node ls` |
| `app-overlay` is `Driver=overlay Scope=swarm`, subnet 10.0.1.0/24, VNI 4097, attachable | `docker network inspect app-overlay` |
| `docker network ls` shows two scopes: overlay networks are `swarm`, bridges are `local` | `docker network ls` |
| `web-svc` converged to 3/3 replicas | `docker service ls` / `service ps` |
| Service name resolves to one VIP (10.0.1.2); `tasks.web-svc` resolves to the three task IPs (10.0.1.3, .4, .5) | `nslookup` against embedded DNS 127.0.0.11 |
| Requests to the VIP are spread across replicas | `docker service logs` shows hits on web-svc.1, .2 and .3 |
| A standalone container can join the overlay because it is `--attachable` | `overlay-client` got 10.0.1.7 on `eth0`, plus 172.22.0.6 on `docker_gwbridge` (`eth1`) for external access |

Two small details I noticed: musl's `getent hosts` prints only the first record, which is why I used `nslookup` to see all three task addresses; and nginx logs the client as 10.0.1.6, the `app-overlay-endpoint` address, because IPVS source-NATs traffic that goes through the VIP.

### What I understood

An overlay network is what turns a group of Docker hosts into one flat network for containers: VXLAN carries the frames between hosts, and swarm's Raft store and gossip protocol make sure every host knows which container address lives where. Without swarm mode I cannot even create one, which showed me that the overlay driver is really a cluster feature rather than a local one. The two-level DNS (VIP for the service, `tasks.` for individual replicas) plus IPVS explained how a client can just call `http://web-svc` and be balanced across replicas without any extra load balancer. I also saw that swarm init silently created `ingress` and `docker_gwbridge`, which is how overlay containers still reach the outside world. On multiple machines the same commands would apply as long as the three swarm ports are open between them.

---

## Cleanup

I removed everything I created (containers, service, overlay network, the three bridge networks and the swarm itself) and verified that only pre-existing items remain. Images were kept.

```bash
docker rm -f overlay-client
docker service rm web-svc
docker network rm app-overlay
docker swarm leave --force
docker info --format 'Swarm: {{.Swarm.LocalNodeState}}'
docker network rm docker_gwbridge          # created as a side effect of swarm init
docker rm -f frontend backend database apache-host apache-published nginx-bind
docker network rm frontend-net backend-net database-net
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Networks}}'
docker network ls
```

```text
$ docker rm -f overlay-client
overlay-client

$ docker service rm web-svc
web-svc

$ docker network rm app-overlay
app-overlay

$ docker swarm leave --force
Node left the swarm.

$ docker info --format 'Swarm: {{.Swarm.LocalNodeState}}'
Swarm: inactive

$ docker network rm docker_gwbridge
docker_gwbridge

$ docker rm -f frontend backend database apache-host apache-published nginx-bind
frontend
backend
database
apache-host
apache-published
nginx-bind

$ docker network rm frontend-net backend-net database-net
frontend-net
backend-net
database-net

$ docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Networks}}'
NAMES                                    IMAGE                                                                                    STATUS                     PORTS                                         NETWORKS
multi-stage-app                          multi-stage-app                                                                          Up 2 minutes               0.0.0.0:8080->3000/tcp, [::]:8080->3000/tcp   bridge
hello-nginx                              hello-nginx                                                                              Up 6 minutes               0.0.0.0:8083->80/tcp, [::]:8083->80/tcp       bridge
hello-react                              hello-react                                                                              Up 6 minutes               0.0.0.0:8082->80/tcp, [::]:8082->80/tcp       bridge
hello-apache                             hello-apache                                                                             Up 6 minutes               0.0.0.0:8081->80/tcp, [::]:8081->80/tcp       bridge
hello-java                               hello-java                                                                               Up 6 minutes               0.0.0.0:8084->8080/tcp, [::]:8084->8080/tcp   bridge
hello-python                             hello-python                                                                             Up 6 minutes               0.0.0.0:5001->5000/tcp, [::]:5001->5000/tcp   bridge
hello-nodejs                             hello-nodejs                                                                             Up 6 minutes               0.0.0.0:3000->3000/tcp, [::]:3000->3000/tcp   bridge
linux-lab                                linux-lab                                                                                Up 9 minutes                                                             bridge
[... two exited containers from unrelated work on this machine removed from this listing ...]
buildx_buildkit_multiplatform-builder0   moby/buildkit:buildx-stable-1                                                            Up 10 days                                                               bridge

$ docker network ls
NETWORK ID     NAME          DRIVER    SCOPE
f97de1351b5c   bridge        bridge    local
4321bfb79d1e   grr_default   bridge    local
1e633e39c71a   host          host      local
91d8a28dc325   none          null      local

$ docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' | grep -E 'REPOSITORY|^nginx |^httpd |^mysql |^alpine '
REPOSITORY                                                                        TAG                      SIZE
nginx                                                                             alpine                   102MB
httpd                                                                             2.4                      207MB
httpd                                                                             2.4-alpine               107MB
alpine                                                                            latest                   13.6MB
mysql                                                                             8.0                      1.09GB
nginx                                                                             1.27-alpine              76.8MB

```

The remaining containers (`buildx_buildkit_multiplatform-builder0`, the `hello-*` containers and the two exited ones) and the `grr_default` network belong to other work on this machine and were not touched. `bridge`, `host` and `none` are Docker's built-in networks.

---

## Summary

| Requirement | Done | Evidence |
|---|---|---|
| T1: 3 containers (frontend, backend, database) with Nginx/Alpine + MySQL images | Yes | `docker ps` in Task 1 (nginx:alpine x2, mysql:8.0) |
| T1: 3 Docker networks | Yes | `docker network ls`: frontend-net, backend-net, database-net |
| T1: backend on 2 networks | Yes | `docker inspect backend`: frontend-net 172.19.0.3 + database-net 172.21.0.2 |
| T1: connectivity checked | Yes | 10-row results table: backend reaches both tiers, frontend and database cannot reach each other |
| T2: pull Apache2 image | Yes | `docker pull httpd:2.4` |
| T2: Apache container on host network | Yes | `NetworkMode=host`, empty PORTS column |
| T2: access on port 80 | Yes, inside the Docker VM; refused from macOS | HTTP 200 via `--network host` helper; macOS curl 000/exit 7 explained; browser-reachable fallback on 8095 |
| T3: folder + index.html "Hello students" | Yes | `bind-mount/html/index.html` |
| T3: bind mount into Nginx and verify | Yes | `docker inspect .Mounts`, `curl` returns `<h1>Hello students</h1>` |
| T3: modify and verify without restart | Yes | new content served, `StartedAt`/`RestartCount`/`Pid` unchanged, propagation measured at 0.025 s |
| T4: overlay research (problem, mechanism, use cases, multi-host) | Yes | research section + overlay vs bridge table |
| T4: hands-on demo | Yes | single-node swarm, attachable overlay, 3-replica service, VIP + tasks DNS, load balancing |
| Cleanup, swarm inactive again | Yes | `outputs/cleanup.txt` |
