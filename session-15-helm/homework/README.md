# Session 15: Helm - Homework

**Name:** Rudhar Bajaj
**Environment:** macOS (Apple Silicon), Docker Desktop, Helm v4.3.0, kubectl v1.36.1, kind v0.33.0 (single
node `hw-b`, Kubernetes v1.37.0). NodePorts 30090/30091 are mapped to my Mac by the kind config
(`../../session-13-storage-hpa-probes/homework/kind-hw-b.yaml`), so I could `curl localhost:3009x`.

Every output block below is real output from commands I ran on 2026-10-07. Full untrimmed transcripts
are in `outputs/`. Where I shortened a listing I say so.

## Files

| Path | What it is |
|---|---|
| `webapp/` | my chart, made with `helm create webapp` and then changed (see Task 1) |
| `values/v2.yaml`, `values/v3.yaml` | override files for upgrade 1 and upgrade 2 |
| `mini-project/notes-chart/` | the Notes chart from the mini project |
| `outputs/01-helm-create.txt` | `helm create`, generated files |
| `outputs/02-helm-repo-search.txt` | `helm repo add/list/update`, `helm search repo`, `helm search hub` |
| `outputs/03-helm-lint-template.txt` | `helm lint`, `helm template`, what each one does and doesn't catch |
| `outputs/04-helm-install-upgrade-rollback.txt` | Task 2: install -> upgrade -> upgrade -> rollback, plus `list/status/get/history` |
| `outputs/05a-helm-atomic-uninstall-first-run.txt` | first try of the failed-upgrade test (it exposed a bug in my chart) |
| `outputs/05b-helm-atomic-uninstall.txt` | failed upgrade with automatic rollback, `helm list` filters, `uninstall` (with and without `--keep-history`) |
| `outputs/06-mini-project-notes-chart.txt` | the mini project, steps 8-15 |

Helm's config/cache directories pointed at a private scratch folder while I worked
(`HELM_CONFIG_HOME` etc.), so the repos I added didn't change my normal Helm setup.

---

## Task 1 - the Helm commands

### `helm create` - scaffold a chart

```text
$ helm create webapp
Creating webapp
$ find webapp -type f
webapp/Chart.yaml
webapp/.helmignore
webapp/templates/deployment.yaml
webapp/templates/httproute.yaml
webapp/templates/NOTES.txt
webapp/templates/ingress.yaml
webapp/templates/tests/test-connection.yaml
webapp/templates/service.yaml
webapp/templates/hpa.yaml
webapp/templates/serviceaccount.yaml
webapp/templates/_helpers.tpl
webapp/values.yaml
```

It writes a working nginx chart. `Chart.yaml` is the chart's metadata (name, chart `version`,
`appVersion`). `values.yaml` holds the defaults. `templates/` are Go templates. `_helpers.tpl` holds
named templates such as `webapp.fullname` and the standard labels. `NOTES.txt` is printed after install.
In Helm 4 the scaffold also includes an `httproute.yaml` (Gateway API), next to the older `ingress.yaml`.

**What I changed in `webapp/`** so each revision is visibly different:

| File | Change |
|---|---|
| `Chart.yaml` | description, `appVersion: "1.27-alpine"` |
| `values.yaml` | `image.tag: "1.26-alpine"`, `service.type: NodePort` + `nodePort: 30091`, small `resources`, new `page.message` / `page.color` |
| `templates/_helpers.tpl` | `webapp.pageHtml` (the HTML page) and `webapp.pageConfigMapName` (name + 8-char hash of the page) |
| `templates/configmap.yaml` | new: ConfigMap with `index.html` |
| `templates/deployment.yaml` | mounts that ConfigMap at `/usr/share/nginx/html` |
| `templates/service.yaml` | sets `nodePort` when the type is NodePort |

The page prints the release, revision, image and replica count, so `curl` shows which revision is live.
I named the ConfigMap with a hash of its content after the first run (see "a bug my first run found" below).

### `helm lint` and `helm template`

```text
$ helm lint webapp
==> Linting webapp
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed

$ helm template web webapp | sed -n '/configmap.yaml/,/serviceaccount.yaml/p'    (trimmed)
kind: ConfigMap
metadata:
  name: web-webapp-page-68b647ba
data:
  index.html: |
    <html><body style="font-family:sans-serif;color:#2b6cb0">
    <h1>Hello from webapp - v1</h1>
    <p>release=web revision=1 image=nginx:1.26-alpine replicas=1</p>
...
spec:
  type: NodePort
  ports:
    - port: 80
      targetPort: http
      nodePort: 30091
```

`lint` checks the chart's structure and that it renders. `template` renders the YAML locally, with no
cluster needed. Neither one knows Kubernetes types, though. I rendered `--set service.port=abc`: lint and
template were happy, and so was `helm install --dry-run=server`. The API server rejected it:

```text
$ helm template bad webapp --set service.port=abc | kubectl apply --dry-run=server -f -
Error from server (BadRequest): ... json: cannot unmarshal string into Go struct field ServicePort.spec.ports.port of type int32
$ helm install bad webapp --set service.port=abc
Error: INSTALLATION FAILED: server-side apply failed for object default/bad-webapp /v1, Kind=Service: ...
.spec.ports[port="abc",protocol="TCP"].port: expected numeric (int or float), got string
```

The failed install still left a ServiceAccount and a ConfigMap behind (created before the Service failed)
and a `failed` release record. `helm uninstall bad` cleaned all of it up.

### `helm install`, `list`, `status`

```text
$ helm install web webapp
NAME: web
LAST DEPLOYED: Wed Oct  7 23:16:52 2026
NAMESPACE: default
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
NOTES:
1. Get the application URL by running these commands:
  export NODE_PORT=$(kubectl get --namespace default -o jsonpath="{.spec.ports[0].nodePort}" services web-webapp)
  ...
$ helm list
NAME	NAMESPACE	REVISION	UPDATED                             	STATUS  	CHART       	APP VERSION
web 	default  	1       	2026-10-07 23:16:52.857364 +0530 IST	deployed	webapp-0.1.0	1.27-alpine
$ helm status web     (NOTES part trimmed)
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
RESOURCES:
==> v1/ServiceAccount
web-webapp   1s
==> v1/ConfigMap
web-webapp-page-68b647ba   1      1s
==> v1/Service
web-webapp   NodePort   10.96.4.131   <none>        80:30091/TCP   1s
==> v1/Deployment
web-webapp   0/1     1            0           0s
==> v1/Pod(related)
web-webapp-85c759d8df-zkj9s   0/1     ContainerCreating   0          0s
```

- `install` renders the chart with values and creates the objects. It records revision 1 as a Secret
  `sh.helm.release.v1.web.v1` in the namespace.
- `list` shows the releases in the namespace.
- `status` shows the release state. In Helm 4 it also lists the live resources.

### `helm get` - what Helm stored for a release

```text
$ helm get values web
USER-SUPPLIED VALUES:
null
$ helm get values web --all    (trimmed)
COMPUTED VALUES:
image:
  pullPolicy: IfNotPresent
  repository: nginx
  tag: 1.26-alpine
page:
  color: '#2b6cb0'
  message: Hello from webapp - v1
replicaCount: 1
service:
  nodePort: 30091
  port: 80
  type: NodePort
$ helm get manifest web | grep -E '^kind:|^# Source:|replicas:|image:'
# Source: webapp/templates/serviceaccount.yaml
kind: ServiceAccount
# Source: webapp/templates/configmap.yaml
kind: ConfigMap
# Source: webapp/templates/service.yaml
kind: Service
# Source: webapp/templates/deployment.yaml
kind: Deployment
  replicas: 1
          image: "nginx:1.26-alpine"
$ helm get notes web
NOTES:
1. Get the application URL by running these commands: ...
$ helm get metadata web
NAME: web
CHART: webapp
VERSION: 0.1.0
APP_VERSION: 1.27-alpine
...
REVISION: 1
STATUS: deployed
APPLY_METHOD: server-side apply
```

| Subcommand | Shows |
|---|---|
| `get values` | only the values I passed (`-f`/`--set`). `null` = none. Add `--all` for the merged result |
| `get manifest` | the exact YAML Helm sent to the cluster for that revision |
| `get notes` | the rendered `NOTES.txt` |
| `get all` | everything above plus hooks, in one dump |
| `get metadata` | chart, version, revision, status. In Helm 4 also `APPLY_METHOD: server-side apply` |

All of them take `--revision N`.

### `helm upgrade`, `history`, `rollback`, `uninstall`

These are covered by Task 2 below and `outputs/05b-...`. In short:
- `upgrade` renders again with new values or a new chart, applies the difference, and records a new revision.
- `history` lists the revisions.
- `rollback <rel> N` re-applies revision N's stored manifest as a **new** revision.
- `uninstall` deletes the objects and the release Secrets. With `--keep-history` it keeps the records,
  so `helm history` still works and the release shows up under `helm list --uninstalled`.

### `helm repo` and `helm search`

```text
$ helm repo list
no repositories to show
$ helm repo add bitnami https://charts.bitnami.com/bitnami
"bitnami" has been added to your repositories
$ helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
"ingress-nginx" has been added to your repositories
$ helm repo update
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "bitnami" chart repository
Update Complete. ⎈Happy Helming!⎈
$ helm search repo nginx
NAME                            	CHART VERSION	APP VERSION	DESCRIPTION
bitnami/nginx                   	25.2.1       	1.31.6     	NGINX Open Source is a web server that can be a...
bitnami/nginx-ingress-controller	12.0.7       	1.13.1     	NGINX Ingress Controller is an Ingress controll...
bitnami/nginx-intel             	2.1.15       	0.4.9      	DEPRECATED NGINX Open Source for Intel is a lig...
ingress-nginx/ingress-nginx     	4.15.1       	1.15.1     	Ingress controller for Kubernetes using NGINX a...
$ helm search hub nginx --max-col-width 50 | head -12     (header + first 4 rows shown)
URL                                               	CHART VERSION  	APP VERSION	DESCRIPTION
https://artifacthub.io/packages/helm/cloudpirat...	0.16.12        	1.31.6     	Nginx is a high-performance HTTP server and rev...
https://artifacthub.io/packages/helm/quench-ngi...	0.0.15         	1.30.5     	High-performance web server, reverse proxy, and...
https://artifacthub.io/packages/helm/krakazyabr...	1.0.0          	1.19.0     	Nginx Helm chart for Kubernetes
https://artifacthub.io/packages/helm/dhinesh/nginx	25.2.1         	1.31.6     	NGINX Open Source is a web server that can be a...
$ helm search hub nginx | wc -l
     305
```

`repo add` saves a repo URL. `repo update` downloads each repo's `index.yaml`. `search repo` searches
those local indexes (offline, only repos I added; `--versions` lists all versions). `search hub` asks
Artifact Hub online and searches every public chart.

### Helm v4 differences I ran into

| v3 | v4.3 (what I saw) |
|---|---|
| `helm upgrade --atomic` | still accepted but prints `Flag --atomic has been deprecated, use --rollback-on-failure instead` |
| `helm list -a` / `--all` | **removed**: `Error: unknown shorthand flag: 'a' in -a`. `helm list --help`: "By default, it lists all releases in any status", with filters `--deployed --failed --uninstalled ...` |
| client-side apply (3-way merge) | server-side apply by default (`helm get metadata` shows `APPLY_METHOD: server-side apply`, `--server-side` flag) |
| `--force` | `--force-replace` (and `--force-conflicts` for SSA) |
| `--wait` boolean | `--wait` takes a strategy: `watcher` (default when given), `hookOnly` (default when omitted), `legacy` |
| `helm search hub` | unchanged, still works |
| `helm create` | the scaffold now includes `templates/httproute.yaml` |

---

## Task 2 - rollback workflow: install -> upgrade -> verify -> upgrade -> verify -> rollback -> verify

Revisions (`values/v2.yaml`, `values/v3.yaml`):

| Revision | How | replicas | image | page |
|---|---|---|---|---|
| 1 | `helm install web webapp` | 1 | nginx:1.26-alpine | "v1", blue |
| 2 | `helm upgrade web webapp -f values/v2.yaml` | 2 | nginx:1.27-alpine | "v2", green |
| 3 | `helm upgrade web webapp -f values/v3.yaml` | 3 | nginx:1.28-alpine | "v3", red |
| 4 | `helm rollback web 2` | 2 | nginx:1.27-alpine | "v2" |

After each step I ran `kubectl rollout status`, the deployment's replicas/image, the pods, four `curl`s
from my Mac, and `helm history`. From `outputs/04-...`:

```text
# revision 1
web-webapp   1          1       nginx:1.26-alpine
<h1>Hello from webapp - v1</h1>
<p>release=web revision=1 image=nginx:1.26-alpine replicas=1</p>

# revision 2
web-webapp   2          2       nginx:1.27-alpine
<h1>Hello from webapp - v2</h1>
<p>release=web revision=2 image=nginx:1.27-alpine replicas=2</p>

# revision 3
web-webapp   3          3       nginx:1.28-alpine
<h1>Hello from webapp - v3</h1>
<p>release=web revision=3 image=nginx:1.28-alpine replicas=3</p>

# after `helm rollback web 2`
$ helm rollback web 2
Rollback was a success! Happy Helming!
web-webapp   2          2       nginx:1.27-alpine
<h1>Hello from webapp - v2</h1>
<p>release=web revision=2 image=nginx:1.27-alpine replicas=2</p>

$ helm history web
REVISION	UPDATED                 	STATUS    	CHART       	APP VERSION	DESCRIPTION
1       	Wed Oct  7 23:16:52 2026	superseded	webapp-0.1.0	1.27-alpine	Install complete
2       	Wed Oct  7 23:17:06 2026	superseded	webapp-0.1.0	1.27-alpine	Upgrade complete
3       	Wed Oct  7 23:17:22 2026	superseded	webapp-0.1.0	1.27-alpine	Upgrade complete
4       	Wed Oct  7 23:17:42 2026	deployed  	webapp-0.1.0	1.27-alpine	Rollback to 2

$ helm get values web
USER-SUPPLIED VALUES:
image:
  tag: 1.27-alpine
page:
  color: '#2f855a'
  message: Hello from webapp - v2
replicaCount: 2

$ helm get values web --revision 3
USER-SUPPLIED VALUES:
image:
  tag: 1.28-alpine
page:
  color: '#c53030'
  message: Hello from webapp - v3
replicaCount: 3
```

**What I observed:**
- Rollback doesn't delete revision 3. It adds revision 4 ("Rollback to 2"), so the history is append-only.
- The page after rollback still says `revision=2`. I expected 4. `diff` of `helm get manifest --revision 2`
  and `--revision 4` was **empty**: rollback re-applies the stored manifest of revision 2. It does not
  render the templates again with revision 4's data.
- One Secret per revision: `sh.helm.release.v1.web.v1` ... `v4` (`kubectl get secrets -l owner=helm,name=web`).

### Failed upgrade with automatic rollback (`outputs/05b-...`)

```text
$ helm upgrade web webapp -f values/v2.yaml --set image.tag=does-not-exist --atomic --timeout 45s
Flag --atomic has been deprecated, use --rollback-on-failure instead
level=WARN msg="upgrade failed" name=web error="resource Deployment/default/web-webapp not ready. status: InProgress, message: Updated: 1/2\ncontext deadline exceeded"
Error: UPGRADE FAILED: release web failed, and has been rolled back due to rollback-on-failure being set: ...

$ helm upgrade web webapp -f values/v2.yaml --set image.tag=does-not-exist --rollback-on-failure --timeout 45s
Error: UPGRADE FAILED: release web failed, and has been rolled back due to rollback-on-failure being set: ...

$ helm history web     (trimmed to rows 4-8 and the REVISION, STATUS, DESCRIPTION columns)
4    superseded  Rollback to 2
5    failed      Upgrade "web" failed: resource Deployment/default/web-webapp not ready. ...
6    superseded  Rollback to 4
7    failed      Upgrade "web" failed: ...
8    deployed    Rollback to 6

<h1>Hello from webapp - v2</h1>
<p>release=web revision=2 image=nginx:1.27-alpine replicas=2</p>
```

Each failed attempt costs two revisions (the failed one plus the automatic rollback). The site stayed on v2.

### A bug my first run found (`outputs/05a-...`)

In my first version of the chart the ConfigMap had a fixed name (`web-webapp-page`). After the same failed
upgrade and automatic rollback, `curl` returned:

```text
<h1>Hello from webapp - v2</h1>
<p>release=web revision=7 image=nginx:does-not-exist replicas=2</p>
```

That's the **failed** revision's page, served by the healthy old pods. The cause: the failed upgrade
overwrote the shared ConfigMap, and the kubelet copies ConfigMap changes into already-running pods'
volumes. Helm rolled the ConfigMap object back, but the files in the pods update only on the kubelet's
next sync, so for a while the old pods served the bad content. The fix is the hashed name
(`web-webapp-page-<sha256 of page>`): every distinct page is its own ConfigMap, and pods never see
another revision's content. After the change, the rerun above (`05b`) served the correct v2 page right
after the rollback. (My first run also had image pulls failing on a DNS error in the shared Docker VM.
After that I pre-pulled the nginx tags into the node with `crictl pull`.)

### Uninstall

```text
$ helm uninstall web --keep-history
release "web" uninstalled
$ helm list --uninstalled
NAME	NAMESPACE	REVISION	UPDATED                             	STATUS     	CHART       	APP VERSION
web 	default  	8       	2026-10-07 23:19:41.550729 +0530 IST	uninstalled	webapp-0.1.0	1.27-alpine
$ helm history web     (last line)
8       	Wed Oct  7 23:19:41 2026	uninstalled	webapp-0.1.0	1.27-alpine	Uninstallation complete
$ helm uninstall web
release "web" uninstalled
$ kubectl get secrets -l owner=helm,name=web
No resources found in default namespace.
$ helm history web
Error: release: not found
```

---

## Task 3 - Mini project: notes-chart (`outputs/06-mini-project-notes-chart.txt`)

`mini-project/notes-chart/` has exactly the files the mini-project README describes (Chart.yaml,
values.yaml, values-prod.yaml, configmap/deployment/service templates). I copied them from
`../mini-project/notes-chart/` and ran steps 8-15 from `homework/mini-project/`.

**Steps 8-9, lint and render:**

```text
$ helm lint notes-chart
==> Linting notes-chart
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
$ helm template notes-dev notes-chart | grep -c '{{'
0
```

**Step 10, install (development):**

```text
$ helm install notes-dev notes-chart --wait --timeout 3m
STATUS: deployed
REVISION: 1
$ kubectl get pods
notes-dev-deploy-74956bd987-bjfsq   1/1     Running   0          2s
$ kubectl get services
notes-dev-svc   NodePort    10.96.162.157   <none>        80:30090/TCP   2s
$ kubectl get configmaps
notes-dev-config   2      2s
$ kubectl exec notes-dev-deploy-74956bd987-bjfsq -- sh -c 'echo APP_NAME=$APP_NAME ENVIRONMENT=$ENVIRONMENT; nginx -v'
APP_NAME=notes-app ENVIRONMENT=development
nginx version: nginx/1.24.0
$ curl -sI http://localhost:30090/ | grep -i '^server'
Server: nginx/1.24.0
```

**Step 11, upgrade with values-prod.yaml:**

```text
$ helm upgrade notes-dev notes-chart -f notes-chart/values-prod.yaml --wait --timeout 3m
Release "notes-dev" has been upgraded. Happy Helming!
REVISION: 2
notes-dev-deploy-bbcc464b4-7pgrd   true    Running   <none>    nginx:1.25
notes-dev-deploy-bbcc464b4-rqpzw   true    Running   <none>    nginx:1.25
notes-dev-deploy-bbcc464b4-xf6mz   true    Running   <none>    nginx:1.25
APP_NAME=notes-app ENVIRONMENT=production
Server: nginx/1.25.5
```

**Step 12, history:** revision 1 `superseded / Install complete`, revision 2 `deployed / Upgrade complete`.

**Step 13, bad upgrade** (the README's exact command):

```text
$ helm upgrade notes-dev notes-chart --set image.tag=broken-tag-does-not-exist
STATUS: deployed
REVISION: 3
$ kubectl get pods
notes-dev-deploy-79b4dbdffd-sdjq2   0/1     ImagePullBackOff   0          41s
notes-dev-deploy-bbcc464b4-rqpzw    1/1     Running            0          51s
$ helm get values notes-dev
USER-SUPPLIED VALUES:
image:
  tag: broken-tag-does-not-exist
$ kubectl get deploy notes-dev-deploy -o jsonpath=...     (jsonpath shortened here; full command in the transcript)
1 replicas, labels: {"app":"notes-dev","app.kubernetes.io/managed-by":"Helm","environment":"development"}
```

Two things the README's expected output doesn't show:
1. Helm reported **`STATUS: deployed`** for the broken upgrade. Without `--wait`/`--rollback-on-failure`,
   Helm only checks that the API server accepted the objects, not that the pods became healthy.
2. The command has no `-f values-prod.yaml`, so revision 3 went back to the **chart defaults** plus the
   one `--set`: 1 replica, `environment: development`. Helm doesn't carry over the previous `-f` values
   unless you pass them again or use `--reuse-values`. With 1 replica and the default 25% max-unavailable,
   the Deployment kept one old healthy pod running, so the site stayed up on nginx 1.25.

**Step 14, rollback to revision 2:**

```text
$ helm rollback notes-dev 2 --wait --timeout 3m
Rollback was a success! Happy Helming!
notes-dev-deploy-bbcc464b4-4pknd   true    Running   <none>    nginx:1.25
notes-dev-deploy-bbcc464b4-m6drv   true    Running   <none>    nginx:1.25
notes-dev-deploy-bbcc464b4-rqpzw   true    Running   <none>    nginx:1.25
APP_NAME=notes-app ENVIRONMENT=production
Server: nginx/1.25.5
$ helm history notes-dev     (only REVISION, STATUS, DESCRIPTION columns)
1   superseded  Install complete
2   superseded  Upgrade complete
3   superseded  Upgrade complete
4   deployed    Rollback to 2
```

The pod hash `bbcc464b4` is the same as in revision 2. The rollback brought back the exact pod template,
so the Deployment went back to the old ReplicaSet instead of making a new one.

**Step 15, clean up:**

```text
$ helm uninstall notes-dev
release "notes-dev" uninstalled
$ kubectl get pods
No resources found in default namespace.
$ kubectl get configmaps
kube-root-ca.crt   1      88m
```

### What I practiced

- [x] Created a chart (`helm create webapp`, plus notes-chart from the README)
- [x] values.yaml + override files (`values/v2.yaml`, `values/v3.yaml`, `values-prod.yaml`)
- [x] `helm lint`, `helm template`, and what they can't catch
- [x] install, upgrade x2, rollback, with `curl` to check each revision
- [x] a bad upgrade, manual rollback and automatic rollback (`--rollback-on-failure`)
- [x] `helm get values/manifest/notes/all/metadata`, `status`, `list`, `history`
- [x] `helm repo add/list/update`, `helm search repo/hub`
- [x] `helm uninstall`, with and without `--keep-history`
