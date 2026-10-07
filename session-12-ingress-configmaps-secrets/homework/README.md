# Ingress, ConfigMaps & Secrets - Homework

**Name:** Rudhar Bajaj
**Environment:** macOS 26.5.2 (Apple Silicon), Docker Desktop (Engine 29.6.1), kind v0.33.0 single-node cluster `hw-a` (Kubernetes v1.37.0), ingress-nginx controller v1.12.1 (kind manifest), MetalLB v0.16.1, kubectl v1.36.1, gitleaks 8.30.1

Every output block below is real output from commands I ran on 2026-10-07. Full untrimmed transcripts are in `outputs/`. Where I shortened a listing I say so.

**All passwords in this folder are fake demo values** (`demo-password-123`, `mypassword`, and the instructor's `secretpassword`).

Cluster: the `hw-a` kind cluster from session 10 (`../../session10-k8s-core-objects/homework/cluster/kind-hw-a.yaml`). The node's port 80 is published on my Mac as **`localhost:30081`**, not 8081 as planned, because port 8081 was already taken by another container on my Docker Desktop (`Bind for 0.0.0.0:8081 failed: port is already allocated`). Port 443 is published as `localhost:8444`.

| File | Contents |
|---|---|
| `outputs/01-configmap.txt` | ConfigMap: create, inject as env + volume, verify, live update of file vs env |
| `outputs/02-secret.txt` | Secret: create, inject as env + files, verify, base64 decode, plaintext in etcd, gitleaks, .gitignore check |
| `outputs/03-ingress-without-controller.txt` | app + Ingress applied with **no** controller: ADDRESS empty, nothing answers |
| `outputs/04-ingress-controller-path-routing.txt` | install ingress-nginx, same Ingress gets an address, path-based routing, generated nginx.conf |
| `outputs/05-ingress-host-routing.txt` | host-based routing to two backends, host + path |
| `outputs/06a-troubleshoot-secret-base64.txt` | trailing-newline Secret bug with a real PostgreSQL |
| `outputs/06b-troubleshoot-broken-image-rollback.txt` | session 10 `broken-image.yaml`: stuck rollout, rollback |
| `outputs/06c-troubleshoot-selector-mismatch.txt` | session 10 `selector-mismatch.yaml`: rejected by the API server |
| `outputs/06d-troubleshoot-empty-endpoints.txt` | session 11 `empty-endpoints.yaml`: Service with no endpoints |
| `outputs/99-cleanup.txt` | final state and `kind delete cluster --name hw-a` |

| YAML | What |
|---|---|
| `configmap/app-config.yaml` | ConfigMap `yatri-app-config` (instructor's keys + a file-style key `app.properties`) |
| `configmap/configmap-demo-pod.yaml` | Pod using it via `envFrom`, `configMapKeyRef` and a volume |
| `secret/db-secret.yaml` | Secret `yatri-db-secret` (fake values) |
| `secret/secret-demo-pod.yaml` | Pod using it via `secretKeyRef` env vars and a read-only volume |
| `ingress/full-demo/*.yaml` | copy of the instructor's `04-full-demo` (backend, frontend, ConfigMap, Secret, path-based Ingress) |
| `ingress/host-based.yaml` | my two `http-echo` backends + host-based Ingress |
| `troubleshooting/*.yaml` | reproduction + fixed versions for Task 5 |
| `.gitignore` | ignore patterns for real secret files |

## Contents

1. [Task 1 - ConfigMap](#task-1---configmap)
2. [Task 2 - Secret](#task-2---secret) (and [why Secrets don't belong in Git](#why-a-secret-must-not-be-committed-to-git))
3. [Task 3 - Ingress](#task-3---ingress)
4. [Task 4 - Ingress vs Ingress Controller](#task-4---ingress-vs-ingress-controller)
5. [Task 5 - Troubleshooting](#task-5---troubleshooting)

---

## Task 1 - ConfigMap

**Create it and store config values.** `configmap/app-config.yaml`:

```yaml
data:
  ENVIRONMENT: "production"
  LOG_LEVEL: "INFO"
  PORT: "5000"
  DEFAULT_CURRENCY: "INR"
  MAX_BOOKING_DAYS: "30"
  app.properties: |
    feature.seat-map=enabled
    feature.upi-payments=enabled
    cache.ttl.seconds=120
```

```text
$ kubectl apply -f configmap/app-config.yaml
configmap/yatri-app-config created

$ kubectl get configmap yatri-app-config
NAME               DATA   AGE
yatri-app-config   6      1s
```

(The same can be done without YAML: `kubectl create configmap quick-config --from-literal=THEME=dark ...`. The `--dry-run=client -o yaml` output is in the transcript.)

**Inject it into a Pod.** `configmap/configmap-demo-pod.yaml` uses it in three ways:

```yaml
envFrom:
  - configMapRef: {name: yatri-app-config}           # every key -> env var
env:
  - name: APP_LOG_LEVEL                               # one key, renamed
    valueFrom: {configMapKeyRef: {name: yatri-app-config, key: LOG_LEVEL}}
volumeMounts:
  - {name: config, mountPath: /etc/yatri, readOnly: true}
volumes:
  - name: config
    configMap: {name: yatri-app-config}               # every key -> file
```

**Verify inside the container:**

```text
$ kubectl exec configmap-demo -- sh -c 'env | grep -E "^(ENVIRONMENT|LOG_LEVEL|PORT|DEFAULT_CURRENCY|MAX_BOOKING_DAYS|APP_LOG_LEVEL)=" | sort'
APP_LOG_LEVEL=INFO
DEFAULT_CURRENCY=INR
ENVIRONMENT=production
LOG_LEVEL=INFO
MAX_BOOKING_DAYS=30
PORT=5000

$ kubectl exec configmap-demo -- ls -la /etc/yatri      (trimmed)
drwxr-xr-x    2 root     root          4096 Oct  7 17:54 ..2026_10_07_17_54_54.2401834985
lrwxrwxrwx    1 root     root            32 Oct  7 17:54 ..data -> ..2026_10_07_17_54_54.2401834985
lrwxrwxrwx    1 root     root            23 Oct  7 17:54 DEFAULT_CURRENCY -> ..data/DEFAULT_CURRENCY
lrwxrwxrwx    1 root     root            16 Oct  7 17:54 LOG_LEVEL -> ..data/LOG_LEVEL
lrwxrwxrwx    1 root     root            21 Oct  7 17:54 app.properties -> ..data/app.properties
...

$ kubectl exec configmap-demo -- cat /etc/yatri/app.properties
feature.seat-map=enabled
feature.upi-payments=enabled
cache.ttl.seconds=120
```

**Then I changed a value while the pod was running:**

```text
$ kubectl patch configmap yatri-app-config --type merge -p '{"data":{"LOG_LEVEL":"DEBUG"}}'
configmap/yatri-app-config patched
# (polled the file until it changed: took about 88s - the kubelet syncs ConfigMap volumes periodically)

$ kubectl exec configmap-demo -- cat /etc/yatri/LOG_LEVEL
DEBUG
$ kubectl exec configmap-demo -- sh -c 'echo "env LOG_LEVEL=$LOG_LEVEL  APP_LOG_LEVEL=$APP_LOG_LEVEL"'
env LOG_LEVEL=INFO  APP_LOG_LEVEL=INFO

# after deleting and re-creating the pod:
env LOG_LEVEL=DEBUG  APP_LOG_LEVEL=DEBUG
```

**What I observed.**
- Each key becomes either an env var or a file. File-style keys like `app.properties` are the natural fit for whole config files.
- The volume is a set of symlinks into a timestamped directory (`..data -> ..2026_10_07_...`). The kubelet writes a new directory and then swaps the `..data` link atomically, so the app never reads a half-written file.
- **Mounted files follow ConfigMap changes** (here after 88 s; the kubelet's sync period plus its cache). **Env vars do not**: they are copied into the process when the container starts. To pick up new env values, the pod must be recreated (`kubectl rollout restart` for a Deployment). The app also has to re-read its files to benefit from the live update.

## Task 2 - Secret

**Create it.** `secret/db-secret.yaml` (fake values). I generated the base64 with `kubectl create secret generic ... --dry-run=client -o yaml`, so there is no trailing-newline risk (see Task 5):

```yaml
type: Opaque
data:
  POSTGRES_DB: eWF0cmlfZGVtb19kYg==
  POSTGRES_PASSWORD: ZGVtby1wYXNzd29yZC0xMjM=
  POSTGRES_USER: eWF0cmlfYWRtaW4=
```

```text
$ kubectl apply -f secret/db-secret.yaml
secret/yatri-db-secret created

$ kubectl describe secret yatri-db-secret      (trimmed)
Type:  Opaque
Data
====
POSTGRES_DB:        13 bytes
POSTGRES_PASSWORD:  17 bytes
POSTGRES_USER:      11 bytes
```

**Inject it into a Pod** (`secret/secret-demo-pod.yaml`): two env vars via `secretKeyRef`, and the whole Secret as files in `/etc/db-creds` with `defaultMode: 0400`.

**Verify inside the container:**

```text
$ kubectl exec secret-demo -- sh -c 'echo "DB_USER=$DB_USER"; echo "DB_PASSWORD=$DB_PASSWORD"'
DB_USER=yatri_admin
DB_PASSWORD=demo-password-123

$ kubectl exec secret-demo -- ls -laL /etc/db-creds      (trimmed)
-r--------    1 root     root            13 Oct  7 17:57 POSTGRES_DB
-r--------    1 root     root            17 Oct  7 17:57 POSTGRES_PASSWORD
-r--------    1 root     root            11 Oct  7 17:57 POSTGRES_USER

$ kubectl exec secret-demo -- cat /etc/db-creds/POSTGRES_PASSWORD
demo-password-123

$ kubectl exec secret-demo -- mount      (only the db-creds line shown)
tmpfs on /etc/db-creds type tmpfs (ro,relatime,size=8125796k,noswap)
```

**What I observed.** Inside the container the values are plain text, as the app needs. A Secret volume is a **tmpfs** (RAM, never written to the node's disk), mounted read-only, and my files are mode `0400`. `describe` only shows sizes, not values. That is about all the protection a Secret adds over a ConfigMap by default.

### Why a Secret must not be committed to Git

**1. base64 is an encoding, not encryption.** Anyone who can read the YAML or has `get secret` permission has the password:

```text
$ sh -c 'echo ZGVtby1wYXNzd29yZC0xMjM= | base64 -d; echo'
demo-password-123

$ kubectl get secret yatri-db-secret -o go-template='{{range $k,$v := .data}}{{$k}}={{$v | base64decode}}{{"\n"}}{{end}}'
POSTGRES_DB=yatri_demo_db
POSTGRES_PASSWORD=demo-password-123
POSTGRES_USER=yatri_admin
```

**2. On a default cluster it is not even encrypted at rest.** I read the Secret straight out of etcd (non-printable protobuf bytes shown as dots, trimmed):

```text
$ kubectl -n kube-system exec etcd-hw-a-control-plane -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=... --cert=... --key=... get /registry/secrets/default/yatri-db-secret --print-value-only | LC_ALL=C tr -c '[:print:]\n' '.'
k8s.
.v1..Secret...
.yatri-db-secret....default".*$606dda35-...
...
.POSTGRES_DB..yatri_demo_db.&
.POSTGRES_PASSWORD..demo-password-123..
.POSTGRES_USER..yatri_admin..Opaque..".

$ sh -c 'kubectl get pod kube-apiserver-hw-a-control-plane -n kube-system -o yaml | grep -c encryption-provider-config'
0
```

**3. Secret scanners treat it as a leak.** gitleaks flags even my demo file:

```text
$ gitleaks dir secret/db-secret.yaml --no-banner --redact=100 --no-color -v      (trimmed)
Finding:     POSTGRES_PASSWORD: REDACTED
RuleID:      generic-api-key
File:        secret/db-secret.yaml
Line:        16
...
RuleID:      kubernetes-secret-yaml
Tags:        [decoded:base64 decode-depth:1]
...
11:28PM WRN leaks found: 3
```

So a Secret manifest with real values in a repo means the password is in the Git history for good, on every clone and fork. Rotating the password is the only real fix after that. Note the `decoded:base64` tag: the scanner decoded the base64 itself.

**What to do instead:**

| Option | How it works |
|---|---|
| **Sealed Secrets** (Bitnami) | `kubeseal` encrypts the Secret with the cluster's public key into a `SealedSecret` that is safe to commit; only the controller in the cluster can decrypt it. |
| **External Secrets Operator** | Git holds only an `ExternalSecret` that *points* at a key in AWS Secrets Manager / Vault / GCP / Azure; the operator creates the Kubernetes Secret at runtime. |
| **SOPS** (+ age/KMS) | Encrypts only the values in the YAML (keys stay readable for review); decrypted at deploy time (e.g. by Flux, Argo CD plugin, helm-secrets). |
| **Create at deploy time** | `kubectl create secret ... --from-literal` from CI secrets (e.g. GitHub Actions secrets), never written to the repo. |
| **etcd encryption at rest** | `--encryption-provider-config` on the API server (or a KMS plugin) so point 2 above no longer applies. |
| **RBAC** | Limit `get/list secrets`. Anyone who can create a pod in the namespace can mount the Secret anyway. |
| **`.gitignore`** + pre-commit scanning | Keep local secret files out of Git by name, and run gitleaks before each commit. |

My `.gitignore` for this folder:

```gitignore
*.secret.yaml
*.secret.yml
.env
*.env
```

```text
$ git check-ignore -v secret/prod.secret.yaml secret/.env
session-12-ingress-configmaps-secrets/homework/.gitignore:2:*.secret.yaml	secret/prod.secret.yaml
session-12-ingress-configmaps-secrets/homework/.gitignore:5:*.env	secret/.env

$ git check-ignore -v secret/db-secret.yaml
(no output: the fake demo manifest is deliberately not ignored)
```

`secret/db-secret.yaml` is committed **only because its values are fake demo values**, as the homework asks for a Secret YAML. A real one would be named `*.secret.yaml` (ignored) or replaced by one of the options above.

## Task 3 - Ingress

I used the instructor's full demo app (`ingress/full-demo/`): a Python **backend** that prints values it got from the ConfigMap and Secret, an nginx **frontend**, ClusterIP Services for both, and the Ingress `yatri-ingress`:

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
    - host: yatri.local
      http:
        paths:
          - path: /api(/|$)(.*)       # -> yatri-backend-service:80 (pods :5000)
            pathType: ImplementationSpecific
          - path: /                   # -> yatri-frontend-service:80
            pathType: Prefix
```

**1. Deploy the app and the Services** (before any controller exists, see Task 4):

```text
$ kubectl apply -f ingress/full-demo/configmap.yaml -f ingress/full-demo/secret.yaml -f ingress/full-demo/backend.yaml -f ingress/full-demo/frontend.yaml
configmap/yatri-app-config configured
secret/yatri-db-secret configured
deployment.apps/yatri-backend created
service/yatri-backend-service created
deployment.apps/yatri-frontend created
service/yatri-frontend-service created

$ kubectl get deploy,svc -l 'app in (yatri-backend,yatri-frontend)'
NAME                             READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/yatri-backend    2/2     2            2           2s
deployment.apps/yatri-frontend   2/2     2            2           2s

NAME                             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/yatri-backend-service    ClusterIP   10.96.231.226   <none>        80/TCP    2s
service/yatri-frontend-service   ClusterIP   10.96.217.57    <none>        80/TCP    2s
```

**2. Install the ingress controller.** I used the kind-specific ingress-nginx manifest. It runs the controller with `hostPort` 80/443 on the node, which my kind config forwards to `localhost:30081`/`8444`:

```text
$ kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml
$ kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=240s
pod/ingress-nginx-controller-7c467b649f-6tszt condition met

$ kubectl get pods,svc -n ingress-nginx      (trimmed)
pod/ingress-nginx-admission-create-m8jdz        0/1     Completed   0
pod/ingress-nginx-admission-patch-4w6wf         0/1     Completed   1 (12s ago)
pod/ingress-nginx-controller-7c467b649f-6tszt   1/1     Running     0
service/ingress-nginx-controller             LoadBalancer   10.96.97.23     172.18.203.200   80:32704/TCP,443:31850/TCP
service/ingress-nginx-controller-admission   ClusterIP      10.96.225.171   <none>           443/TCP

$ kubectl get ingressclass
NAME    CONTROLLER             PARAMETERS   AGE
nginx   k8s.io/ingress-nginx   <none>       13s
```

(The controller's Service is type LoadBalancer, so MetalLB from session 11 gave it `172.18.203.200`. In this kind setup my traffic comes in through the hostPort instead.)

**3. Access the app through the Ingress and verify path-based routing:**

```text
$ kubectl get ingress yatri-ingress
NAME            CLASS   HOSTS         ADDRESS     PORTS   AGE
yatri-ingress   nginx   yatri.local   localhost   80      44s

$ curl -s -o /dev/null -w 'GET yatri.local/ -> HTTP %{http_code}\n' -H 'Host: yatri.local' http://localhost:30081/
GET yatri.local/ -> HTTP 200
$ sh -c "curl -s -H 'Host: yatri.local' http://localhost:30081/ | grep -o '<title>.*</title>'"
<title>Welcome to nginx!</title>

$ curl -s -H 'Host: yatri.local' http://localhost:30081/api/
Yatri Backend API
=================
ENVIRONMENT     : production
LOG_LEVEL       : INFO
DEFAULT_CURRENCY: INR
POSTGRES_USER   : yatri_admin
POSTGRES_DB     : yatri_production_db

$ curl -s -o /dev/null -w 'unknown host -> HTTP %{http_code}\n' -H 'Host: other.local' http://localhost:30081/
unknown host -> HTTP 404

$ sh -c 'curl -s --resolve yatri.local:30081:127.0.0.1 http://yatri.local:30081/api/ | head -3'
Yatri Backend API
=================
ENVIRONMENT     : production
```

The controller's access log names the backend that served each request:

```text
$ kubectl logs -n ingress-nginx ingress-nginx-controller-7c467b649f-6tszt --tail=6      (trimmed)
"GET / HTTP/1.1" 200 615 ... [default-yatri-frontend-service-80] [] 10.244.0.29:80 ...
"GET /api/ HTTP/1.1" 200 178 ... [default-yatri-backend-service-80] [] 10.244.0.30:5000 ...
"GET /api/bookings HTTP/1.1" 200 178 ... [default-yatri-backend-service-80] [] 10.244.0.28:5000 ...
```

**4. Host-based routing to two backends** (`ingress/host-based.yaml`: two `hashicorp/http-echo` Deployments and one Ingress with hosts `blue.local`, `green.local`, plus `apps.local/blue` and `apps.local/green`):

```text
$ kubectl get ingress
NAME            CLASS   HOSTS                               ADDRESS     PORTS   AGE
echo-hosts      nginx   blue.local,green.local,apps.local   localhost   80      42s
yatri-ingress   nginx   yatri.local                         localhost   80      96s

$ kubectl describe ingress echo-hosts      (trimmed)
Rules:
  Host         Path  Backends
  blue.local   /   echo-blue:80 (10.244.0.35:5678)
  green.local  /   echo-green:80 (10.244.0.36:5678)
  apps.local   /blue    echo-blue:80 (10.244.0.35:5678)
               /green   echo-green:80 (10.244.0.36:5678)

$ curl -s -H 'Host: blue.local' http://localhost:30081/
hello from BLUE backend
$ curl -s -H 'Host: green.local' http://localhost:30081/
hello from GREEN backend
$ curl -s -H 'Host: apps.local' http://localhost:30081/blue
hello from BLUE backend
$ curl -s -H 'Host: apps.local' http://localhost:30081/green
hello from GREEN backend
$ curl -s -o /dev/null -w 'apps.local/purple -> HTTP %{http_code}\n' -H 'Host: apps.local' http://localhost:30081/purple
apps.local/purple -> HTTP 404

$ sh -c 'for h in blue.local green.local; do for i in $(seq 1 10); do curl -s -H "Host: $h" http://localhost:30081/; done; done | sort | uniq -c'
  10 hello from BLUE backend
  10 hello from GREEN backend
```

**What I observed.**
- One entry point (`localhost:30081`, one controller) serves many apps. The controller picks the backend by the **Host header** first, then by the **path**. A host or path with no rule gets nginx's default 404.
- `rewrite-target: /$2` strips `/api` before the request reaches the backend. That is why `/api/` and `/api/bookings` both work on a backend that knows nothing about `/api`.
- The backend's reply proves the ConfigMap (`ENVIRONMENT`, `LOG_LEVEL`, `DEFAULT_CURRENCY`) and the Secret (`POSTGRES_USER`, `POSTGRES_DB`) reached the app as env vars. Applying the full demo replaced my Task 1/2 `yatri-app-config` and `yatri-db-secret` with the instructor's versions, which is why the DB name is `yatri_production_db` here.
- I used `-H 'Host: ...'` instead of editing `/etc/hosts`, which needs sudo. `curl --resolve` is the other no-sudo way and sends the right Host automatically.

## Task 4 - Ingress vs Ingress Controller

**What I did:** I created the Ingress **before** installing any controller (`outputs/03-ingress-without-controller.txt`), then installed ingress-nginx and looked at the same object again (`outputs/04-...`).

Before (no controller in the cluster):

```text
$ kubectl get ingressclass
No resources found
$ kubectl get pods -A -l app.kubernetes.io/name=ingress-nginx
No resources found

$ kubectl apply -f ingress/full-demo/ingress.yaml
ingress.networking.k8s.io/yatri-ingress created

$ kubectl get ingress yatri-ingress        (15 s later)
NAME            CLASS   HOSTS         ADDRESS   PORTS   AGE
yatri-ingress   nginx   yatri.local             80      15s

$ kubectl describe ingress yatri-ingress      (trimmed)
Address:
Ingress Class:    nginx
Rules:
  yatri.local
               /api(/|$)(.*)   yatri-backend-service:80 (10.244.0.28:5000,10.244.0.30:5000)
               /               yatri-frontend-service:80 (10.244.0.29:80,10.244.0.31:80)
Events:        <none>

$ curl -s -m 5 -o /dev/null -w 'http://localhost:30081/ -> HTTP %{http_code}\n' -H 'Host: yatri.local' http://localhost:30081/
http://localhost:30081/ -> HTTP 000
```

After installing the controller, the **same, unchanged** Ingress:

```text
$ kubectl get ingress yatri-ingress
NAME            CLASS   HOSTS         ADDRESS     PORTS   AGE
yatri-ingress   nginx   yatri.local   localhost   80      44s

Events:
  Type    Reason  Age                From                      Message
  Normal  Sync    10s (x2 over 10s)  nginx-ingress-controller  Scheduled for sync

$ curl -s -o /dev/null -w 'GET yatri.local/ -> HTTP %{http_code}\n' -H 'Host: yatri.local' http://localhost:30081/
GET yatri.local/ -> HTTP 200

$ kubectl exec -n ingress-nginx ingress-nginx-controller-7c467b649f-6tszt -- grep -n -E 'server_name yatri.local|location ~\*? "?\^/' /etc/nginx/nginx.conf
335:		server_name yatri.local ;
348:		location ~* "^/api(/|$)(.*)" {
444:		location ~* "^/" {
```

| | Ingress | Ingress Controller |
|---|---|---|
| What it is | a Kubernetes **API object** (`networking.k8s.io/v1`, kind `Ingress`): routing **rules** | a **program running in pods** (here nginx + a Go controller) that implements those rules |
| Who provides it | built into Kubernetes, like Service or ConfigMap | installed separately: ingress-nginx, Traefik, HAProxy, cloud ones (AWS ALB, GKE) |
| Contains | hosts, paths, backend Services, TLS secret names, annotations | the actual reverse proxy, TLS termination, load balancing |
| On its own | does nothing; it is just data stored in etcd (`ADDRESS` empty, no events, no listener) | with no Ingress objects it serves only the default 404 |
| Connection | `spec.ingressClassName: nginx` picks a controller | the `IngressClass` `nginx` says `controller: k8s.io/ingress-nginx`; the controller watches Ingresses of its class and writes them into `nginx.conf` |
| Analogy | the routing table | the router |

**Why both are needed.** Kubernetes deliberately ships only the API (the "what") and leaves the data plane (the "how") to pluggable controllers, the same split as with LoadBalancer Services and cloud controllers. The Ingress is portable: the same YAML works with any controller that supports its class. The controller does the real work. My test shows it directly: before the controller there was no address, no event and nothing answered. With the controller, the identical object got `ADDRESS localhost`, a `Sync` event, `server_name yatri.local` and `location` blocks in `nginx.conf`, and HTTP 200.

## Task 5 - Troubleshooting

### 5.1 Secret with a trailing newline (`troubleshooting/secret-base64-gotcha.md`)

I reproduced the incident with a **real PostgreSQL** (`troubleshooting/base64-gotcha-postgres.yaml`). The DB server's password is `mypassword` (fake). The "application" pod (`app-db-client.yaml`) connects with the password from `app-db-secret`, prints how many bytes it received, and runs `psql`.

**Problem (before):** the developer encoded the password with `echo "mypassword" | base64` -> `bXlwYXNzd29yZAo=` (`app-secret-broken.yaml`).

```text
$ kubectl get pod app-db-client
NAME            READY   STATUS   RESTARTS   AGE
app-db-client   0/1     Error    0          3s

$ kubectl logs app-db-client
password length seen by the app: 11 bytes
0000000   m   y   p   a   s   s   w   o   r   d  \n
0000013
psql: error: connection to server at "yatri-postgres" (10.96.122.248), port 5432 failed: FATAL:  password authentication failed for user "yatri_admin"

$ kubectl logs yatri-postgres --tail=3      (trimmed)
... FATAL:  password authentication failed for user "yatri_admin"
... DETAIL:  Connection matched file "/var/lib/postgresql/data/pg_hba.conf" line 128: "host all all all scram-sha-256"
```

**Troubleshooting commands:** the password "looks right" in `kubectl get secret`, so look at the bytes:

```text
$ sh -c "kubectl get secret app-db-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d | xxd"
00000000: 6d79 7061 7373 776f 7264 0a              mypassword.

$ sh -c 'echo "mypassword" | xxd'
00000000: 6d79 7061 7373 776f 7264 0a              mypassword.
$ sh -c 'echo "mypassword" | base64'
bXlwYXNzd29yZAo=
```

**Root cause:** `echo` adds a newline (`0a`). The Secret stores `mypassword\n`, 11 bytes, and PostgreSQL compares all 11, so authentication fails. The base64 ending `Ao=` instead of `A==` gives it away.

**A second trap I found on macOS.** The fix in the doc is `echo -n`, but:

```text
$ sh -c 'echo -n "mypassword" | base64'
LW4gbXlwYXNzd29yZAo=
$ sh -c 'echo -n "mypassword" | xxd'
00000000: 2d6e 206d 7970 6173 7377 6f72 640a       -n mypassword.

$ sh -c 'printf "%s" "mypassword" | base64'
bXlwYXNzd29yZA==
$ zsh -c 'echo -n "mypassword" | base64'
bXlwYXNzd29yZA==
$ bash -c 'echo -n "mypassword" | base64'
bXlwYXNzd29yZA==
```

macOS `/bin/sh` is bash in POSIX mode, where `echo` does not accept `-n`. It printed the literal text `-n mypassword` **plus** the newline. In a Makefile or a `sh` script, the "fixed" command would produce a third wrong password. `printf '%s'` works the same in every shell, and `kubectl create secret --from-literal` or `stringData:` avoid the problem altogether.

**Fix (after):** `app-secret-fixed.yaml` with `bXlwYXNzd29yZA==`, then recreate the pod (env vars are read at start):

```text
$ kubectl apply -f troubleshooting/app-secret-fixed.yaml
secret/app-db-secret configured
$ sh -c "kubectl get secret app-db-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d | xxd"
00000000: 6d79 7061 7373 776f 7264                 mypassword

$ kubectl get pod app-db-client
NAME            READY   STATUS      RESTARTS   AGE
app-db-client   0/1     Completed   0          2s

$ kubectl logs app-db-client
password length seen by the app: 10 bytes
0000000   m   y   p   a   s   s   w   o   r   d
0000012
 current_user |                                            version
--------------+------------------------------------------------------------------------------------------------
 yatri_admin  | PostgreSQL 16.15 on aarch64-unknown-linux-musl, compiled by gcc (Alpine 15.2.0) 15.2.0, 64-bit
(1 row)
```

### 5.2 Rollout stuck on a bad image (`session10-k8s-core-objects/troubleshooting/broken-image.yaml`)

**Starting point:** `yatri-backend` from Task 3 is healthy and `/api` returns 200 through the Ingress.

**Problem (before):**

```text
$ kubectl apply -f .../session10-k8s-core-objects/troubleshooting/broken-image.yaml
deployment.apps/yatri-backend configured
$ kubectl rollout status deployment/yatri-backend --timeout=60s
error: timed out waiting for the condition

$ kubectl get rs -l app=yatri-backend -o wide      (trimmed)
NAME                       DESIRED   CURRENT   READY   IMAGES
yatri-backend-6c58cb99c7   3         3         3       python:3.11-alpine3.19
yatri-backend-77dbb657cd   1         1         0       yatri-backend:non-existent-tag-v999

$ kubectl get pods -l app=yatri-backend -L version
NAME                             READY   STATUS             RESTARTS   AGE     VERSION
yatri-backend-6c58cb99c7-2n689   1/1     Running            0          5m54s
yatri-backend-6c58cb99c7-5zm2j   1/1     Running            0          5m54s
yatri-backend-6c58cb99c7-xcpxm   1/1     Running            0          62s
yatri-backend-77dbb657cd-rk7kb   0/1     ImagePullBackOff   0          62s     broken-v3

$ curl -s -o /dev/null -w 'yatri.local/api/ -> HTTP %{http_code}\n' -H 'Host: yatri.local' http://localhost:30081/api/
yatri.local/api/ -> HTTP 200
```

**Troubleshooting:**

```text
$ kubectl describe pod yatri-backend-77dbb657cd-rk7kb | sed -n '/^Events/,$p'      (trimmed)
  Warning  Failed     9s (x3 over 54s)   kubelet  ... Failed to pull image "yatri-backend:non-existent-tag-v999": ... "docker.io/library/yatri-backend:non-existent-tag-v999": pull access denied, repository does not exist or may require authorization ...

$ kubectl get deploy yatri-backend -o 'jsonpath={range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
Available=True MinimumReplicasAvailable: Deployment has minimum availability.
Progressing=True ReplicaSetUpdated: ReplicaSet "yatri-backend-77dbb657cd" is progressing.
```

**Root cause:** the image `yatri-backend:non-existent-tag-v999` does not exist (without a registry prefix it means Docker Hub `library/yatri-backend`, which is not a repository). Thanks to `maxSurge: 1, maxUnavailable: 0`, only one surge pod was created, and the old pods kept serving. Note also that the manifest changed `replicas` from 2 to 3, so the **old** ReplicaSet was scaled up to 3 as well.

**Fix (after):**

```text
$ kubectl rollout undo deployment/yatri-backend
deployment.apps/yatri-backend rolled back
$ kubectl rollout status deployment/yatri-backend --timeout=180s
deployment "yatri-backend" successfully rolled out
$ kubectl get rs -l app=yatri-backend -o wide      (trimmed)
yatri-backend-6c58cb99c7   3         3         3       python:3.11-alpine3.19
yatri-backend-77dbb657cd   0         0         0       yatri-backend:non-existent-tag-v999
$ curl -s -H 'Host: yatri.local' http://localhost:30081/api/
Yatri Backend API
...
```

`rollout undo` restores only the pod template, not `replicas`, so I re-applied the original `backend.yaml` to get back to 2 replicas (`yatri-backend   2/2`). In real life the proper fix is a corrected manifest in Git (a real image tag) rather than an undo that drifts from what Git says.

### 5.3 Selector does not match the template (`session10-k8s-core-objects/troubleshooting/selector-mismatch.yaml`)

**Problem (before):**

```text
$ kubectl apply -f .../session10-k8s-core-objects/troubleshooting/selector-mismatch.yaml
The Deployment "selector-error-demo" is invalid: spec.template.metadata.labels: Invalid value: {"app":"wrong-app-name"}: `selector` does not match template `labels`
$ kubectl get deploy selector-error-demo
Error from server (NotFound): deployments.apps "selector-error-demo" not found
```

**Troubleshooting:**

```text
$ grep -n -A2 -E 'matchLabels|labels:' .../selector-mismatch.yaml
13:    matchLabels:
14-      app: correct-app-name
--
17:      labels:
18:        # BUG: Label does not match selector.matchLabels above!
19-        app: wrong-app-name
```

**Root cause:** `spec.selector.matchLabels` must select the pods the Deployment creates from its template. Here it would select none of them, so the API server rejects the object at validation and nothing is created.

**Fix (after):** `troubleshooting/selector-mismatch-fixed.yaml` (template label `app: correct-app-name`):

```text
$ kubectl apply -f troubleshooting/selector-mismatch-fixed.yaml
deployment.apps/selector-error-demo created
$ kubectl get deploy,pods -l app=correct-app-name
NAME                                       READY   STATUS    RESTARTS   AGE
pod/selector-error-demo-54996d6787-k5bbc   1/1     Running   0          1s

# and the selector cannot be changed later:
$ kubectl patch deployment selector-error-demo --type merge -p '{"spec":{"selector":{"matchLabels":{"app":"something-else"}},"template":{"metadata":{"labels":{"app":"something-else"}}}}}'
The Deployment "selector-error-demo" is invalid: spec.selector: Invalid value: {"matchLabels":{"app":"something-else"}}: field is immutable
```

### 5.4 Service with empty endpoints (`session-11-kubernetes-services/troubleshooting/empty-endpoints.yaml`)

**Problem (before):**

```text
$ kubectl apply -f .../session-11-kubernetes-services/troubleshooting/empty-endpoints.yaml
service/broken-backend-service created
$ kubectl exec tclient -- curl -s -m 5 -o /dev/null -w 'http://broken-backend-service -> HTTP %{http_code}\n' http://broken-backend-service
http://broken-backend-service -> HTTP 000
command terminated with exit code 7
```

**Troubleshooting:**

```text
$ kubectl get endpoints broken-backend-service
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                     ENDPOINTS   AGE
broken-backend-service   <none>      1s

$ kubectl describe svc broken-backend-service      (trimmed)
Selector:                 app=wrong-backend-name
TargetPort:               5000/TCP
Endpoints:

$ kubectl get pods -l app=wrong-backend-name
No resources found in default namespace.
$ kubectl get pods --show-labels -l 'app in (yatri-backend,yatri-frontend)'      (trimmed)
yatri-backend-6c58cb99c7-2n689   1/1     Running   ...   app=yatri-backend,pod-template-hash=6c58cb99c7
```

**Root cause:** the selector `app=wrong-backend-name` matches no pod, so the EndpointSlice is empty and kube-proxy has nothing to forward to (curl exit 7 = connection refused). The DNS name and the ClusterIP exist, which makes this one easy to miss.

**Fix (after):** `troubleshooting/empty-endpoints-fixed.yaml` with `selector: app: yatri-backend` (targetPort 5000 was already right):

```text
$ kubectl apply -f troubleshooting/empty-endpoints-fixed.yaml
service/broken-backend-service configured
$ kubectl get endpoints broken-backend-service
NAME                     ENDPOINTS                           AGE
broken-backend-service   10.244.0.28:5000,10.244.0.30:5000   1s
$ kubectl get endpointslices -l kubernetes.io/service-name=broken-backend-service
NAME                           ADDRESSTYPE   PORTS   ENDPOINTS                             AGE
broken-backend-service-csp4v   IPv4          5000    10.244.0.30,10.244.0.28,10.244.0.47   1s
$ kubectl exec tclient -- curl -s http://broken-backend-service
Yatri Backend API
=================
ENVIRONMENT     : production
...
```

The EndpointSlice briefly listed a third address (`10.244.0.47`). That was the extra backend pod from 5.2, which was still terminating (`xcpxm`, shown as `Terminating` in the label listing). EndpointSlices keep terminating pods with `ready: false`, while the old Endpoints API only shows the 2 ready ones.

### Troubleshooting summary

| Case | Symptom | Key command | Root cause | Fix |
|---|---|---|---|---|
| 5.1 base64 newline | `password authentication failed` | `base64 -d \| xxd` (trailing `0a`) | `echo` without `-n` (and `sh`'s echo ignores `-n` on macOS) | `printf '%s'` / `--from-literal` / `stringData` |
| 5.2 bad image | rollout never finishes, 1 pod `ImagePullBackOff` | `describe pod` events | tag doesn't exist | `rollout undo`, then fix the manifest |
| 5.3 selector mismatch | `apply` rejected, nothing created | read the error + compare labels | template labels don't match selector | make labels match; selector is immutable |
| 5.4 empty endpoints | Service resolves but connection refused | `get endpoints` / EndpointSlices, `--show-labels` | selector typo | selector = real pod label |
