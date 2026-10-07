# Session 14: Kubernetes Troubleshooting - Homework

**Name:** Rudhar Bajaj
**Environment:** macOS (Apple Silicon), Docker Desktop, kind v0.33.0 (single node `hw-b`, Kubernetes v1.37.0,
containerd 2.3.4, CNI kindnet), kubectl v1.36.1, metrics-server (latest release, `--kubelet-insecure-tls`)

Every output block below is real output from commands I ran on 2026-10-07. Full untrimmed transcripts
are in `outputs/`. Where I shortened a listing I say so. Times in my polling loops are local (IST),
Kubernetes timestamps are UTC.

## Files

| File | What it is |
|---|---|
| `outputs/01-kubectl-basics.txt` | Task 1: get, describe, logs, exec, events, explain, top, `-o wide` on the 01-05 demo pods |
| `outputs/02-crashloopbackoff.txt` | 06-crashloopbackoff + scenario-1 |
| `outputs/03-imagepullbackoff.txt` | 07-imagepullbackoff (ErrImagePull -> ImagePullBackOff) + scenario-2 |
| `outputs/04-pending.txt` | 08-pending-pods + scenario-3 |
| `outputs/05-containercreating.txt` | my own: missing ConfigMap volume |
| `outputs/06-service-connectivity.txt` | 09 service with wrong selector (+ a broken instructor image) |
| `outputs/07-dns.txt` | CoreDNS basics, scenario-4, cross-namespace short names, a busybox nslookup gotcha |
| `outputs/08a-pod-networking-localhost.txt` | my own: app bound to 127.0.0.1 |
| `outputs/08b-pod-networking-targetport.txt` | my own: Service targetPort mismatch |
| `outputs/09-configuration.txt` | my own: wrong ConfigMap key, wrong command |
| `outputs/10-oomkilled.txt` | scenario-5 |
| `outputs/11-triage-gauntlet.txt` | `scenarios/triage_all.sh` run as-is, then all five fixes |
| `outputs/12-real-incident-control-plane.txt` | an unplanned, real incident on my cluster (host out of memory) |
| `outputs/13-mini-project.txt` | the mini project |
| `fixes/` | fixed copies of instructor files (scenarios 1-5, 09 service, 09 dns-test pod) |
| `own-issues/` | broken + fixed YAMLs I wrote for issues with no instructor files |
| `mini-project/` | fixed broken pod + the wrong-selector Service for the mini project |

Notes on how I ran things:
- The kind cluster config is `../../session-13-storage-hpa-probes/homework/kind-hw-b.yaml` (one cluster for sessions 13-15).
- The Docker VM is shared with other people's clusters and it ran out of memory several times while I worked
  (see the last section). My transcript helper retries a command when the API server itself can't be
  reached and prints `# (API server unreachable ... retry N)` when it does. Twice it mis-fired on an event
  message that happened to contain "connection refused"; I marked those spots in the transcripts.

---

## Task 1 - the basic commands

All from `outputs/01-kubectl-basics.txt`, using the pods in `01-kubectl-get` ... `05-events`.

| Command | What it tells me | Example I ran |
|---|---|---|
| `kubectl get` | one line per object: status, ready count, restarts, age | `kubectl get pods`, `--show-labels`, `-l app=get-demo`, `-o jsonpath`, `-o custom-columns`, `-o yaml` |
| `kubectl get -o wide` | adds pod IP, node, nominated node | `kubectl get pods -o wide` |
| `kubectl describe` | the full picture of one object, incl. container state, last state, exit code, probes, mounts and **Events** | `kubectl describe pod describe-demo`, `kubectl describe node hw-b-control-plane` |
| `kubectl logs` | the container's stdout/stderr | `--tail=2`, `--timestamps`, `--since=10s`, `-l app=...`, `--previous` |
| `kubectl exec` | run a command inside a running container | `hostname`, `cat /etc/resolv.conf`, `curl localhost` |
| events | what the control plane and kubelet did, with reasons | `kubectl get events --field-selector involvedObject.name=...`, `kubectl events --for pod/...` |
| `kubectl explain` | the API docs for a field, offline from the server schema | `kubectl explain pod.spec.restartPolicy` |
| `kubectl top` | live CPU/memory from metrics-server | `kubectl top nodes`, `kubectl top pods -A --sort-by=cpu`, `--containers` |

```text
$ kubectl get pods -o wide
NAME            READY   STATUS    RESTARTS   AGE   IP            NODE                 NOMINATED NODE   READINESS GATES
describe-demo   1/1     Running   0          1s    10.244.0.111   hw-b-control-plane   <none>           <none>
events-demo     1/1     Running   0          1s    10.244.0.112   hw-b-control-plane   <none>           <none>
exec-demo       1/1     Running   0          1s    10.244.0.114   hw-b-control-plane   <none>           <none>
get-demo        1/1     Running   0          2s    10.244.0.110   hw-b-control-plane   <none>           <none>
logs-demo       1/1     Running   0          1s    10.244.0.113   hw-b-control-plane   <none>           <none>
$ kubectl get pod get-demo -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image,QOS:.status.qosClass
NAME       IMAGE        QOS
get-demo   nginx:1.27   BestEffort

$ kubectl logs logs-demo --timestamps --tail=3
2026-10-07T17:26:09.040747798Z Database connection successful
2026-10-07T17:26:09.040749298Z Application is running
2026-10-07T17:26:09.040749881Z Application is healthy

$ kubectl exec exec-demo -- cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5

$ kubectl explain pod.spec.restartPolicy
FIELD: restartPolicy <string>
ENUM:
    Always
    Never
    OnFailure
DESCRIPTION:
    Restart policy for all containers within the pod. One of Always, OnFailure,
    Never. ... Default to Always.

$ kubectl top pod exec-demo --containers
POD         NAME    CPU(cores)   MEMORY(bytes)
exec-demo   nginx   26m          22Mi
```

**What I noticed:**
- `kubectl top` right after creating a pod says `metrics not available yet` / `NotFound`. metrics-server
  needs a couple of 15 s scrapes first. A minute later it worked.
- `kubectl get events --sort-by=.lastTimestamp` was not in time order on this cluster (newer events fill
  `eventTime` instead). `kubectl events` sorts properly, so I prefer it.
- I used one-shot `kubectl exec pod -- cmd` instead of `-it ... sh` so the output could be saved. It's the
  same mechanism without a TTY.

---

## Task 2 - troubleshooting each issue

Same method for every issue: **identify** (get), **investigate** (describe/events/logs/exec), **root
cause**, **fix**, **verify**. The summary table is first, details after.

| # | Issue | Status I saw | Where I found the cause | Root cause | Fix |
|---|---|---|---|---|---|
| 1 | CrashLoopBackOff (06) | `Error`, restarts climbing, `BackOff` events | `logs`, `describe` (Exit Code 1) | command exits 1 | `fixed-pod.yaml` keeps running |
| 1b | CrashLoopBackOff (scenario-1) | `Error`, then `Completed`, restarts climbing | `logs`: `DATABASE_URL ... MISSING` | env var missing; also script exits 0 | add env + keep process alive |
| 2 | ImagePullBackOff / ErrImagePull (07) | `ErrImagePull` then `ImagePullBackOff` | describe Events: `not found` | tag doesn't exist | `kubectl set image ... nginx:1.27` |
| 2b | ImagePull (scenario-2) | same | Events: `pull access denied, repository does not exist` | repo doesn't exist on Docker Hub | real image |
| 2c | ImagePull (instructor's `dns-test` pod) | `ImagePullBackOff` | Events + registry tag list | `dnsutils:1.3` no longer published | busybox:1.36 |
| 3 | Pending (08) | `Pending`, node `<none>` | Events: `didn't match Pod's node affinity/selector` | nodeSelector for a missing node | drop nodeSelector |
| 3b | Pending (scenario-3) | `Pending` | Events: `Insufficient cpu, Insufficient memory` | requests 500 CPU / 1000Gi | sane requests |
| 4 | ContainerCreating (own) | `ContainerCreating` forever | Events: `FailedMount ... configmap "site-content" not found` | missing ConfigMap | create it |
| 5 | Service connectivity (09) | `wget ... Connection refused` | `describe svc`: `Endpoints:` empty, selector `app=web-ahsgdf` | selector doesn't match pod labels | selector `app: web` |
| 6 | DNS (scenario-4) | pod Running, app fails silently | `curl -sS`: `Could not resolve host` + nslookup NXDOMAIN | wrong hostname, and the DB didn't exist | create `postgres-db` + right name |
| 6b | DNS (cross-namespace) | `wget: bad address 'web-service'` | `resolv.conf` search list | short name resolves in the caller's namespace | `web-service.default` |
| 7 | Pod networking (own) | endpoint exists, `Connection refused` | `/proc/net/tcp` shows `0100007F:1F90` | app bound to 127.0.0.1 | bind 0.0.0.0 (+ readiness probe) |
| 7b | Pod networking (own) | `download timed out` / refused | endpoints show `:8080` | Service targetPort 8080, nginx on 80 | targetPort 80 |
| 8 | Configuration (own) | `CreateContainerConfigError` | Events: `couldn't find key LOGLEVEL` | wrong ConfigMap key | key `LOG_LEVEL` |
| 8b | Configuration (own) | `RunContainerError`, `StartError` exit 128 | describe: `exec: "ngnix": executable file not found` | typo in `command` | `nginx` |
| 9 | OOMKilled (scenario-5) | `OOMKilled`, exit 137 | describe Last State, Limits `20Mi` | holds ~1000 MiB with a 20Mi limit | stream chunks + 64Mi limit |

### 1. CrashLoopBackOff

**Problem:** `06-crashloopbackoff/broken-pod.yaml` keeps restarting.

```text
22:30:11 crash-demo   0/1   Pending   0     0s
22:30:16 crash-demo   0/1   Error   1 (4s ago)   5s
22:30:26 crash-demo   0/1   Error   2 (13s ago)   15s
22:30:47 crash-demo   0/1   Error   2 (34s ago)   36s

$ kubectl logs crash-demo
Application starting...
Something went wrong!

$ kubectl get pod crash-demo -o jsonpath={.status.containerStatuses[0].lastState.terminated}
{"containerID":"containerd://e19651324708dca0ad2b4cfe9398d486142fa88d24464e117288d79f22caacd9","exitCode":1,"finishedAt":"2026-10-07T17:00:25Z","reason":"Error","startedAt":"2026-10-07T17:00:25Z"}

Events:     (one line shown)
  Warning  BackOff    3s (x3 over 39s)  kubelet            spec.containers{app}: Back-off restarting failed container app in pod crash-demo_default(3d11127d-dcfd-4f9d-a8cf-0f0d4f7dd16b)
```

**Root cause:** the command prints an error and `exit 1`. With `restartPolicy: Always` the kubelet restarts
it, waiting longer each time (10 s, 20 s, 40 s ... up to 5 min). That waiting is the "BackOff".
**Fix / verify:** the instructor's `fixed-pod.yaml` keeps the process alive; pod `1/1 Running`, 0 restarts.

**Scenario 1** (python app):

```text
$ kubectl logs fail-1-crashloop-pod
[FATAL ERROR]: DATABASE_URL environment variable is MISSING!

$ kubectl describe pod fail-1-crashloop-pod | sed -n '/State:/,/Restart Count/p;/Environment/,/Mounts/p'
    State:          Terminated
      Reason:       Error
      Exit Code:    1
    ...
    Restart Count:  2
    Environment:    <none>
```

I first added only `DATABASE_URL` (`fixes/scenario-1-env-only.yaml`). It still looped, now as `Completed`:

```text
22:31:29 fail-1-crashloop-pod   0/1   Completed   1 (4s ago)   5s
22:31:39 fail-1-crashloop-pod   0/1   Completed   2 (14s ago)   15s
    State:          Terminated
      Reason:       Completed
      Exit Code:    0
```

The script prints "started successfully" and then ends. A Pod with `restartPolicy: Always` restarts a
process that exits, whatever the exit code. The full fix (`fixes/scenario-1-crashloop-fixed.yaml`) sets
the env var (a fake demo connection string) **and** keeps the process running. Result: `1/1 Running`, 0 restarts.

`kubectl logs --previous` returned `unable to retrieve container logs` every time on this cluster. The
kubelet had already removed the older dead container. Plain `kubectl logs` on a crashing pod still showed
the last run's output, and that was enough.

### 2. ImagePullBackOff / ErrImagePull

```text
22:32:44 image-demo   0/1   ContainerCreating   0     11s
22:32:46 image-demo   0/1   ErrImagePull   0     13s
...
    State:          Waiting
      Reason:       ImagePullBackOff
Events:     (long message wrapped onto a second line)
  Warning  Failed     15s               kubelet            spec.containers{app}: Failed to pull image "nginx:this-image-does-not-exist": rpc error: code = NotFound desc = failed to pull and unpack image
           "docker.io/library/nginx:this-image-does-not-exist": failed to resolve reference "docker.io/library/nginx:this-image-does-not-exist": docker.io/library/nginx:this-image-does-not-exist: not found
  Warning  Failed     15s               kubelet            spec.containers{app}: Error: ErrImagePull
  Normal   BackOff    14s               kubelet            spec.containers{app}: Back-off pulling image "nginx:this-image-does-not-exist"
  Warning  Failed     14s               kubelet            spec.containers{app}: Error: ImagePullBackOff

$ docker exec hw-b-control-plane crictl pull nginx:this-image-does-not-exist
... level=fatal msg="pulling image: rpc error: code = NotFound ... not found"
```

`ErrImagePull` is the failed attempt itself. `ImagePullBackOff` is the kubelet waiting before it tries
again. **Root cause:** that tag isn't published. **Fix:** `image` is one of the few Pod fields you can
change in place, so `kubectl set image pod/image-demo app=nginx:1.27`. The pod went `1/1 Running` and
the events show `Pulled ... nginx:1.27`, `Started`.

**Scenario 2** gives a different message:

```text
Failed to pull image "yatri-api-service:v999-invalid-tag-does-not-exist": ... docker.io/library/yatri-api-service:...:
pull access denied, repository does not exist or may require authorization: server message: insufficient_scope
```

No registry prefix means Docker Hub `library/`. The repo doesn't exist, and Docker Hub says the same thing
for a private repo without credentials. So I check the name first, then `imagePullSecrets`. There's no
published image for this app, so `fixes/scenario-2-imagepull-fixed.yaml` uses a real one (`nginx:alpine`).

**A real one in the instructor's files:** `09-service-dns-troubleshooting/dns-test-pod.yaml` uses
`registry.k8s.io/e2e-test-images/dnsutils:1.3`, and it sat in `ImagePullBackOff`:

```text
Failed to pull image "registry.k8s.io/e2e-test-images/dnsutils:1.3": rpc error: code = NotFound ... not found
$ docker manifest inspect registry.k8s.io/e2e-test-images/dnsutils:1.3
no such manifest: registry.k8s.io/e2e-test-images/dnsutils:1.3
$ curl -sL https://registry.k8s.io/v2/e2e-test-images/dnsutils/tags/list
{"child":[],"manifest":{},"name":"k8s-artifacts-prod/images/e2e-test-images/dnsutils","tags":[]}
```

`fixes/dns-test-pod-fixed.yaml` uses `busybox:1.36` (it has `nslookup` and `wget`).

### 3. Pending

```text
$ kubectl get pod pending-demo -o wide
NAME           READY   STATUS    RESTARTS   AGE   IP       NODE     ...
pending-demo   0/1     Pending   0          9s    <none>   <none>
Events:
  Warning  FailedScheduling  9s  default-scheduler  0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector. ...
$ kubectl get nodes --show-labels
hw-b-control-plane   Ready   control-plane   ...   kubernetes.io/hostname=hw-b-control-plane,...
```

**Root cause:** `nodeSelector: kubernetes.io/hostname: node-that-does-not-exist`. The scheduler never
assigns the pod (NODE `<none>`), so there are no kubelet events or logs. Only the scheduler's
`FailedScheduling`. **Fix:** the instructor's `fixed-pod.yaml` without the selector -> `Running` on
`hw-b-control-plane`.

**Scenario 3:**

```text
Warning  FailedScheduling  9s  default-scheduler  0/1 nodes are available: 1 Insufficient cpu, 1 Insufficient memory. ...
Allocatable:
  cpu:                15
  memory:             8125796Ki
```

It requests `cpu: "500"` and `memory: 1000Gi`. Requests are what the scheduler reserves, and nothing has
that much. `fixes/scenario-3-pending-fixed.yaml` asks for 100m / 64Mi (limits 250m / 128Mi) -> `Running`.

### 4. ContainerCreating (my own files)

`own-issues/containercreating-broken.yaml` mounts ConfigMap `site-content`, which doesn't exist.

```text
$ kubectl get pod cc-demo -o wide
NAME      READY   STATUS              RESTARTS   AGE   IP       NODE                 ...
cc-demo   0/1     ContainerCreating   0          41s   <none>   hw-b-control-plane
Events:
  Normal   Scheduled    40s               default-scheduler  Successfully assigned default/cc-demo to hw-b-control-plane
  Warning  FailedMount  9s (x7 over 41s)  kubelet            MountVolume.SetUp failed for volume "site" : configmap "site-content" not found
```

Difference from Pending: this pod **was** scheduled (it has a node). The kubelet can't set up the volume,
so the container is never created. **Fix:** create the ConfigMap (`own-issues/containercreating-fixed.yaml`).
I didn't recreate the pod because the kubelet keeps retrying the mount:

```text
$ kubectl apply -f own-issues/containercreating-fixed.yaml
configmap/site-content created
$ kubectl wait --for=condition=Ready pod/cc-demo --timeout=180s
pod/cc-demo condition met
$ kubectl exec cc-demo -- curl -s http://localhost/
<h1>served from ConfigMap site-content</h1>
```

### 5. Service connectivity

The instructor's `09-.../service.yaml` turned out to be broken as shipped:

```text
$ kubectl exec dns-test -- wget -qO- -T 3 http://web-service
wget: can't connect to remote host (10.96.114.245): Connection refused

$ kubectl get pods -o wide --show-labels
web-557577df75-j27wp   1/1     Running   0          48s   10.244.0.72   hw-b-control-plane   <none>           <none>            app=web,pod-template-hash=557577df75
$ kubectl describe service web-service
Selector:                 app=web-ahsgdf
Endpoints:
$ kubectl get endpoints web-service
NAME          ENDPOINTS   AGE
web-service   <none>      48s
```

DNS worked (the name resolved to the ClusterIP), but the Service had no endpoints. **Root cause:**
selector `app=web-ahsgdf` vs pod label `app=web`. **Fix:** `fixes/web-service-fixed.yaml`:

```text
Selector:                 app=web
Endpoints:                10.244.0.73:80,10.244.0.72:80
$ kubectl exec dns-test -- wget -qO- -T 3 http://web-service
<!DOCTYPE html> ... <title>Welcome to nginx!</title>
```

`broken-service.yaml` (selector `app: does-not-exist`) gave the same `<none>` endpoints.

### 6. DNS

How it works here: every pod's `/etc/resolv.conf` points at `10.96.0.10` (the `kube-dns` Service, backed
by two CoreDNS pods) with search domains `<ns>.svc.cluster.local svc.cluster.local cluster.local` and
`ndots:5`. A Service gets the name `<svc>.<ns>.svc.cluster.local`.

**Scenario 4.** The pod is `1/1 Running` and its log looks harmless because `curl -s` hides errors:

```text
$ kubectl logs fail-4-dns-failure-pod
Attempting connection to internal database...
Process sleeping...
$ kubectl exec fail-4-dns-failure-pod -- curl -sS --connect-timeout 3 http://postgres-db-wrong-name.production.svc.cluster.local:5432
curl: (6) Could not resolve host: postgres-db-wrong-name.production.svc.cluster.local
$ kubectl exec dns-test -- nslookup postgres-db-wrong-name.production.svc.cluster.local
** server can't find postgres-db-wrong-name.production.svc.cluster.local: NXDOMAIN
$ kubectl get ns production
Error from server (NotFound): namespaces "production" not found
```

**Root cause:** wrong hostname, and the database it should reach didn't exist at all. CoreDNS was fine;
NXDOMAIN is the correct answer for a name that doesn't exist. **Fix:** `fixes/postgres-db.yaml` (namespace
`production`, a postgres:16-alpine Deployment with a fake demo password, Service `postgres-db`) and
`fixes/scenario-4-dns-fixed.yaml` with the right name. Postgres doesn't speak HTTP, so the fixed pod uses `nc`:

```text
$ kubectl logs fail-4-dns-failure-pod
Attempting connection to internal database...
Name:	postgres-db.production.svc.cluster.local
Address: 10.96.187.120
postgres-db.production.svc.cluster.local (10.96.187.120:5432) open
Process sleeping...
```

**Cross-namespace short names.** From a pod in `production`:

```text
$ kubectl -n production exec dns-client -- cat /etc/resolv.conf
search production.svc.cluster.local svc.cluster.local cluster.local
$ kubectl -n production exec dns-client -- wget -qO- -T 3 http://web-service
wget: bad address 'web-service'
$ kubectl -n production exec dns-client -- wget -qO- -T 3 http://web-service.default | head -4
<!DOCTYPE html> ... <title>Welcome to nginx!</title>
```

`web-service` expands to `web-service.production.svc.cluster.local` first, which doesn't exist. Use
`<svc>.<namespace>`.

**A gotcha I hit:** `busybox nslookup kubernetes.default` and `nslookup web-service.default` said
NXDOMAIN while `wget http://web-service.default` worked. busybox's nslookup doesn't apply the search list
to names that already contain a dot. With the FQDN it works (`nslookup kubernetes.default.svc.cluster.local`
-> `10.96.0.1`). So I only use FQDNs with busybox nslookup, or test with the real client.

### 7. Pod networking

kind's default CNI (kindnet) does **not** enforce NetworkPolicy, so a deny policy would have no effect
here. I used two real pod-network faults instead.

**7a. App listening on 127.0.0.1 only** (`own-issues/net-localhost-*.yaml`, python http.server `--bind 127.0.0.1`):

```text
$ kubectl get endpoints api
api    10.244.0.92:8080   0s
$ kubectl exec client -- wget -qO- -T 3 http://10.244.0.92:8080
wget: can't connect to remote host (10.244.0.92): Connection refused
$ kubectl exec api-f96b66575-vv5cm -- python3 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8080/').status)"
200
$ kubectl exec api-f96b66575-vv5cm -- cat /proc/net/tcp
   0: 0100007F:1F90 00000000:0000 0A ...
```

`0100007F:1F90` is 127.0.0.1:8080 in LISTEN (`0A`) state. Every pod has its own network namespace, so
loopback is only reachable from inside that pod. Traffic from other pods arrives on the pod IP. **Fix:**
`--bind 0.0.0.0`, and I added a `tcpSocket` readiness probe (the kubelet probes the pod IP, so it would
also have marked the broken version not-ready). After: `00000000:1F90` (0.0.0.0:8080) and
`wget http://api` returns the directory listing.

**7b. Service targetPort mismatch** (`own-issues/net-targetport-*.yaml`):

```text
$ kubectl exec client -- wget -qO- -T 3 http://shop
wget: download timed out
$ kubectl get endpoints shop
shop   10.244.0.84:8080,10.244.0.85:8080
$ kubectl exec client -- wget -qO- -T 3 http://10.244.0.85:8080
wget: can't connect to remote host (10.244.0.85): Connection refused
$ kubectl exec client -- wget -qO- -T 3 http://10.244.0.85:80 | head -4
<!DOCTYPE html> ... <title>Welcome to nginx!</title>
```

The selector was fine (endpoints exist) but they point at port 8080 and nginx listens on 80. **Fix:**
`targetPort: 80`, applied in place -> endpoints `...:80`, `wget http://shop` works.

### 8. Configuration issues

**8a. Wrong ConfigMap key:**

```text
22:49:33 config-key-demo   0/1   CreateContainerConfigError   0     3s
Events:
  Warning  Failed     11s (x2 over 12s)  kubelet            spec.containers{app}: Error: couldn't find key LOGLEVEL in ConfigMap default/app-config
$ kubectl logs config-key-demo
Error from server (BadRequest): container "app" in pod "config-key-demo" is waiting to start: CreateContainerConfigError
```

The ConfigMap has `LOG_LEVEL`; the pod asks for `LOGLEVEL`. The container is never created, so there are
no logs and describe is the only place to look. Fixed key -> `LOG_LEVEL=debug APP_MODE=demo` in the logs.

**8b. Wrong command:**

```text
22:49:48 config-cmd-demo   0/1   RunContainerError   1 (3s ago)   4s
    Last State:     Terminated
      Reason:       StartError
      Message:      ... exec: "ngnix": executable file not found in $PATH
      Exit Code:    128
```

The image pulled fine. The runtime couldn't exec the typo'd binary. `command: ["nginx", ...]` -> `Running`, `curl localhost` = 200.

### 9. OOMKilled (scenario 5)

```text
22:50:13 fail-5-oomkilled-pod   0/1   OOMKilled   1 (4s ago)   4s
    State:          Terminated
      Reason:       OOMKilled
      Exit Code:    137
    Limits:
      memory:  20Mi
```

**Root cause:** the loop appends 100 x 10 MiB chunks to a list (about 1000 MiB, not the 200 MB the
comment says) under a 20Mi limit. The cgroup OOM killer sends SIGKILL (137 = 128 + 9). **Fix**
(`fixes/scenario-5-oomkilled-fixed.yaml`): process one chunk at a time instead of holding them all, and
use a realistic 64Mi limit (20Mi is too small for CPython plus a 10 MiB buffer). Raising the limit to
1Gi would only hide the leak.

```text
$ kubectl logs fail-5-oomkilled-pod
Processing 100 chunks one at a time...
Done, processed 1000 MiB without holding it all
$ kubectl get pod fail-5-oomkilled-pod
fail-5-oomkilled-pod   1/1     Running   0          15s
```

### The triage gauntlet (`scenarios/triage_all.sh`)

I ran the script as-is, then looked at all five at once:

```text
NAME                     PHASE     WAITING            LAST        EXIT     RESTARTS
fail-1-crashloop-pod     Running   <none>             Error       1        2
fail-2-imagepull-pod     Pending   ImagePullBackOff   <none>      <none>   0
fail-3-pending-pod       Pending   <none>             <none>      <none>   <none>
fail-4-dns-failure-pod   Running   <none>             <none>      <none>   0
fail-5-oomkilled-pod     Running   <none>             OOMKilled   137      2
```

Scenario 4 is the only one that looks healthy from `get`. You only find it by reading logs or testing the
dependency. After applying the five fixes all five were `1/1 Running`, 0 restarts.

---

## A real incident while I worked (`outputs/12-real-incident-control-plane.txt`)

Not planned. About 20 minutes in, `kubectl top` started saying `Metrics API not available`, a new pod got
`ErrImagePull` with `lookup auth.docker.io ... server misbehaving`, and later even `kubectl` itself timed
out (`TLS handshake timeout`). I troubleshot it the same way:

```text
kube-controller-manager-hw-b-control-plane   0/1     CrashLoopBackOff   3 (14s ago)   18m
kube-scheduler-hw-b-control-plane            0/1     CrashLoopBackOff   3 (10s ago)   18m
E1007 16:41:55.628634       1 server.go:337] "Leaderelection lost"
E1007 16:41:48.147379       1 leaderelection.go:473] "Error retrieving lease lock" err="context deadline exceeded"
{"level":"warn",...,"msg":"apply request took too long","took":"4.022963002s","expected-duration":"100ms",...}
$ docker exec hw-b-control-plane sh -c 'cat /proc/loadavg; free -m'
64.86 64.20 31.44 1/1902 419686
               total        used        free      shared  buff/cache   available
Mem:            7935        7761          79          30         317         173
Swap:           1023        1023           0
Warning   SystemOOM   node/hw-b-control-plane   System OOM encountered, victim process: local-path-prov, pid: 71512
```

**Root cause:** the Docker Desktop VM (shared with other people's clusters and containers) ran out of RAM
and swap. etcd writes took seconds, so the scheduler and controller-manager couldn't renew their leader
leases in time and exited on purpose ("Leaderelection lost"). The kubelet restarted them, so they showed
as CrashLoopBackOff. The `SystemOOM` events come from the VM's shared kernel, so OOM kills in other
containers show up on my node too. One of them is from before any of my python pods existed.
**What I did:** I stopped my extra load test, kept my pods small, and set `--leader-elect=false` on the
scheduler and controller-manager static pods (one replica each on one node, so there is nobody to fail over
to). After that they stayed up. My cluster used about 640-700 MiB of the VM the whole time. Once the
other memory was freed (`available` back to 4.9 GB), the problem went away.

---

## Task 3 - Mini project (`outputs/13-mini-project.txt`)

Steps 1-4 (deploy, check app, check service, endpoints):

```text
$ kubectl exec troubleshooting-app-59d4957864-pn7nh -- bash -c curl -s localhost | head -4
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
$ kubectl describe service troubleshooting-service
Selector:                 app=troubleshooting-app
TargetPort:               80/TCP
Endpoints:                10.244.0.104:80,10.244.0.105:80
```

Steps 5-6 (broken pod, investigated before touching YAML):

```text
22:53:53 project-broken-pod   0/1   ErrImagePull   0     6s
22:54:05 project-broken-pod   0/1   ImagePullBackOff   0     19s
Events:
  Warning  Failed     5s (x2 over 21s)  kubelet            spec.containers{app}: Failed to pull image "nginx:this-tag-does-not-exist": rpc error: code = NotFound desc = failed to pull and unpack image ... not found
$ kubectl logs project-broken-pod
Error from server (BadRequest): container "app" in pod "project-broken-pod" is waiting to start: trying and failing to pull image
```

### Step 7 answers

1. **Pod status?** `ErrImagePull` first, then `ImagePullBackOff`. Phase `Pending`, `0/1`, 0 restarts.
2. **Actual error?** `Failed to pull image "nginx:this-tag-does-not-exist": rpc error: code = NotFound ... docker.io/library/nginx:this-tag-does-not-exist: not found`.
3. **Which command found it?** `kubectl describe pod project-broken-pod` (the Events section). `kubectl get events --field-selector involvedObject.name=project-broken-pod` shows the same. `kubectl logs` can't help because no container ever started.
4. **What's wrong with the image?** The repository `nginx` exists, but the tag `this-tag-does-not-exist` doesn't.
5. **Fix?** Use a real tag. I applied `mini-project/broken-pod-fixed.yaml` (`nginx:1.27`); `kubectl set image pod/project-broken-pod app=nginx:1.27` would also work. Result `1/1 Running`.

Steps 8-9 (selector challenge, `mini-project/service-wrong-selector.yaml`):

```text
$ kubectl get endpoints troubleshooting-service
troubleshooting-service   <none>
$ kubectl exec client -- wget -qO- -T 3 http://troubleshooting-service
wget: can't connect to remote host (10.96.210.99): Connection refused
$ kubectl get pods --show-labels
troubleshooting-app-59d4957864-pn7nh   1/1   Running   ...   app=troubleshooting-app,pod-template-hash=59d4957864
$ kubectl describe service troubleshooting-service
Selector:                 app=wrong-app
Endpoints:
```

Re-applying the original `service.yaml` brought the endpoints back (`10.244.0.104:80,10.244.0.105:80`)
and `wget` returned the nginx page. The error was `Connection refused` from the ClusterIP
`10.96.210.99`, so the name had resolved. `nslookup troubleshooting-service.default.svc.cluster.local`
returned that same IP. DNS was fine; only the selector was wrong.

### Step 11 table

| Problem | What I Saw | Command I Used | Root Cause | Fix |
| :--- | :--- | :--- | :--- | :--- |
| **Broken Pod** | `0/1 ErrImagePull` -> `ImagePullBackOff`, 0 restarts, no logs | `kubectl describe pod project-broken-pod` (Events) | image tag doesn't exist | real tag `nginx:1.27` |
| **Service Problem** | `wget` connection refused, endpoints `<none>` | `kubectl describe service`, `kubectl get endpoints`, `kubectl get pods --show-labels` | selector `app=wrong-app` matches no pod | selector `app: troubleshooting-app` |
| **Image Problem** | `Failed to pull image ... not found` | `kubectl get events --field-selector involvedObject.name=...`, `crictl pull` on the node | `nginx:this-tag-does-not-exist` not published | change the image (delete+apply or `kubectl set image`) |

### Step 12 questions

1. **What does `kubectl get` tell us?** The current state in one line per object: phase/status, ready
   containers, restarts, age. With `-o wide` also pod IP and node. It's the "what is wrong" view.
2. **`get` vs `describe`?** `get` is the summary. `describe` is one object in detail: container state and
   last state with exit codes and reasons, probes, mounts, conditions, and the recent Events. Most root
   causes I found today were in `describe`.
3. **Why `kubectl logs`?** To see what the application itself printed. It's how I found
   `DATABASE_URL ... MISSING`. It only helps once a container has actually started.
4. **When `kubectl exec`?** To test from inside: curl localhost, read `/etc/resolv.conf`, run nslookup,
   check which address a process listens on (`/proc/net/tcp`). It tells "app broken" apart from "network broken".
5. **CrashLoopBackOff?** The container keeps exiting and the kubelet keeps restarting it, waiting longer
   each time. The cause is whatever made the process exit. Even exit code 0 counts under `restartPolicy: Always`.
6. **ImagePullBackOff?** The kubelet couldn't pull the image (wrong name/tag, private repo without
   credentials, registry unreachable) and is waiting before retrying. `ErrImagePull` is the failed attempt itself.
7. **Why Pending?** The scheduler can't place it: no node matches its nodeSelector/affinity/taints, not
   enough allocatable CPU/memory for its requests, or an unbound PVC. Look for `FailedScheduling` in the events.
8. **Why can a Service have no endpoints?** Its selector matches no pod labels, or the matching pods aren't
   Ready (failed readiness probe), or there are no pods at all.
9. **Selector vs labels?** The Service's selector is a label query. Every Ready pod whose labels contain
   all of the selector's key/values becomes an endpoint. One wrong character and nothing matches.
10. **What is Kubernetes DNS?** CoreDNS running in `kube-system` behind the `kube-dns` Service
    (`10.96.0.10` here). It gives every Service a name `<svc>.<ns>.svc.cluster.local`. Each pod's
    `resolv.conf` points at it with search domains, so a short name works inside the same namespace.
