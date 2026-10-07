# Session 20: Monitoring, Observability & GitOps - Homework

**Name:** Rudhar Bajaj
**Environment:** macOS (Apple Silicon), Docker Desktop (Engine 29.6.1), kind v0.33.0 (single node `hw-e`, Kubernetes v1.37.0, arm64), kubectl v1.36.1, Helm v4.3.0, kube-prometheus-stack chart 92.1.0 (Prometheus Operator v0.94.1, Grafana 13.2.3), Argo CD v3.5.4 (server and CLI), podinfo 6.7.1

Every output block below is real output from commands I ran on 2026-10-07/08, roughly 23:39 to 00:08 IST. Full untrimmed transcripts are in `outputs/`. Where I shortened a listing I say so.

## Where everything is

| Part | File |
|---|---|
| **Task 1: Monitoring** (demo) | this file, below |
| **Task 2: Observability** (documentation) | [`observability/README.md`](observability/README.md) |
| **Task 3: GitOps** (demo + 08-mini-project) | [`gitops/README.md`](gitops/README.md) |
| kind cluster config | [`kind-hw-e.yaml`](kind-hw-e.yaml) |
| Helm values, app, ServiceMonitor, PrometheusRule, load generator | [`monitoring/`](monitoring/) |
| GitOps manifests, Application, mini-project copy | [`gitops/`](gitops/) |

Transcripts (these replace screenshots):

| File | Contents |
|---|---|
| `outputs/01-cluster-and-monitoring-install.txt` | kind cluster, `helm install` of kube-prometheus-stack, pods and services |
| `outputs/02-podinfo-app.txt` | podinfo Deployment/Service, ServiceMonitor, PrometheusRule, curl of `/`, `/healthz`, `/readyz` |
| `outputs/03-loadgen.txt` | in-cluster load generator pod |
| `outputs/04-promql-queries.txt` | PromQL through `/api/v1/query`: up, CPU, memory, request rate, latency, readiness, probes |
| `outputs/05-logs-and-events.txt` | `kubectl logs` (JSON request logs), events |
| `outputs/06-alert-pending-firing-resolved.txt` | PodinfoDown alert: inactive, pending, firing, Alertmanager, resolved |
| `outputs/07-grafana.txt` | Grafana `/api/health`, datasources, datasource health, dashboards, a query through Grafana |
| `outputs/08-argocd-install.txt` ... `outputs/15-mini-project.txt` | Task 3 (see `gitops/README.md`) |
| `outputs/16-repo-history-and-footprint.txt` | demo Git repo history, memory per namespace |
| `outputs/17-restarts-check.txt` | why Grafana and kube-scheduler restarted during the run |
| `outputs/18-cleanup.txt` | cluster and helper container deleted |

---

## Setup

### Cluster

One single-node kind cluster, `hw-e`. NodePorts are mapped to host ports so I didn't have to keep port-forwards alive ([`kind-hw-e.yaml`](kind-hw-e.yaml)):

| Service | NodePort | On my Mac |
|---|---|---|
| Grafana | 30100 | http://localhost:8084 |
| Prometheus | 30101 | http://localhost:8085 |
| Argo CD (https) | 30102 | https://localhost:8086 |
| podinfo (sample app) | 30103 | http://localhost:8087 |
| Alertmanager | 30104 | http://localhost:30104 |

### kube-prometheus-stack (trimmed)

```bash
kind create cluster --config kind-hw-e.yaml
kubectl create namespace monitoring
helm install kps oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack \
  -n monitoring -f monitoring/kube-prometheus-stack-values.yaml --wait --timeout 15m
```

What I changed in [`monitoring/kube-prometheus-stack-values.yaml`](monitoring/kube-prometheus-stack-values.yaml), and why:

- **Disabled** scraping of kube-etcd, kube-scheduler, kube-controller-manager and kube-proxy, and their default rule groups. On kind these components listen on 127.0.0.1 inside the node, so the targets would just show up as `down` and fire alerts that mean nothing here.
- Prometheus: `retention: 2h`, requests 100m/256Mi, limit 768Mi. Alertmanager is on but tiny (32Mi request, 64Mi limit).
- `serviceMonitorSelectorNilUsesHelmValues: false` (also for rules and podMonitors). Without this, Prometheus only picks up ServiceMonitors and PrometheusRules that carry the Helm release label, and my `podinfo` ones don't.
- No metrics-server. I read CPU and memory from cAdvisor through Prometheus instead, so `kubectl top` wasn't needed.

```text
$ kubectl get pods -n monitoring
NAME                                                    READY   STATUS    RESTARTS   AGE
alertmanager-kps-kube-prometheus-stack-alertmanager-0   2/2     Running   0          3m
kps-grafana-5487f66dbc-bt8gw                            3/3     Running   0          3m17s
kps-kube-prometheus-stack-operator-7cbcc744b6-56g74     1/1     Running   0          3m17s
kps-kube-state-metrics-5f69fb89b6-cr5bt                 1/1     Running   0          3m17s
kps-prometheus-node-exporter-kj8lw                      1/1     Running   0          3m17s
prometheus-kps-kube-prometheus-stack-prometheus-0       2/2     Running   0          2m59s
```

---

## Task 1: Monitoring

### 1.1 Sample app that exposes metrics, and the ServiceMonitor

I used **podinfo** (`ghcr.io/stefanprodan/podinfo:6.7.1`, multi-arch). The instructor's `k8s-demo` is a busybox loop that prints text and has no `/metrics`, so Prometheus has nothing to scrape there. podinfo exposes:

- `/metrics`: Prometheus metrics, including `http_requests_total` and the `http_request_duration_seconds` histogram;
- `/healthz` and `/readyz`, which I wired up as the liveness and readiness probes;
- JSON logs. At `--level=debug` it writes one log line per request.

Files: [`monitoring/podinfo-app.yaml`](monitoring/podinfo-app.yaml) (Namespace, Deployment with 2 replicas and probes, NodePort Service), [`monitoring/podinfo-servicemonitor.yaml`](monitoring/podinfo-servicemonitor.yaml), [`monitoring/podinfo-prometheusrule.yaml`](monitoring/podinfo-prometheusrule.yaml).

The ServiceMonitor is the key piece. It tells the Prometheus Operator to scrape every endpoint of a Service labelled `app=podinfo`, on the port named `http`, every 15s. I never edit `prometheus.yml` by hand: the operator generates the scrape config from this object.

```text
$ kubectl -n podinfo get deploy,pods,svc,endpoints -o wide      (trimmed)
pod/podinfo-ff5c6b4f-bjffk   1/1     Running   0          32s   10.244.0.13
pod/podinfo-ff5c6b4f-mgzg6   1/1     Running   0          32s   10.244.0.12
service/podinfo   NodePort   10.96.145.27   <none>        9898:30103/TCP
endpoints/podinfo   10.244.0.12:9898,10.244.0.13:9898

$ curl -s http://localhost:8087/      (trimmed)
  "hostname": "podinfo-ff5c6b4f-mgzg6",
  "message": "greetings from podinfo v6.7.1",
  "goarch": "arm64",
GET /healthz -> HTTP 200
GET /readyz  -> HTTP 200
```

Prometheus picked up both pods as targets without any restart:

```text
podinfo http://10.244.0.12:9898/metrics up
podinfo http://10.244.0.13:9898/metrics up
```

To get a non-zero request rate, I ran a small busybox pod, [`monitoring/loadgen.yaml`](monitoring/loadgen.yaml), that requests `/` and `/api/info` in a loop for 10 minutes.

### 1.2 Metrics: PromQL through the Prometheus HTTP API

All queries went to `curl -s http://localhost:8085/api/v1/query --data-urlencode 'query=...'`. A small helper prints the result as one line per series, and drops noisy labels such as `endpoint`, `service`, `id` and `image`. The values are not changed. Full output: [`outputs/04-promql-queries.txt`](outputs/04-promql-queries.txt).

| What | PromQL | Real result |
|---|---|---|
| Targets up | `up{namespace="podinfo"}` | 2 series, both `1` |
| Up targets per job | `count by (job) (up == 1)` | 10 jobs, e.g. `podinfo` 2, `kubelet` 3, `node-exporter` 1 |
| **CPU** (cores) | `sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="podinfo", container!=""}[2m]))` | podinfo pods `0.0025` and `0.0023`, loadgen `0.0059` |
| **Memory** (bytes) | `sum by (pod) (container_memory_working_set_bytes{namespace="podinfo", container!=""})` | `17375232` and `16781312` (about 16.5 MiB each) |
| Memory as % of limit | working set / `kube_pod_container_resource_limits{resource="memory"}` * 100 | `25.9 %` and `25.0 %` of 64Mi |
| **Request rate** | `sum by (status) (rate(http_requests_total{namespace="podinfo"}[2m]))` | `{"status":"200"} => 2.12` req/s |
| p95 latency | `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="podinfo"}[2m])))` | `0.0048` s |
| **Health: ready** | `kube_pod_status_ready{namespace="podinfo", condition="true"}` | `1` for both podinfo pods (and loadgen) |
| **Health: probes** | `prober_probe_total{namespace="podinfo", result="successful"}` | Liveness 8 and 8, Readiness 15 and 17 successful probes per pod |
| Restarts | `kube_pod_container_status_restarts_total{namespace="podinfo"}` | `0` |
| Node CPU busy | `1 - avg(rate(node_cpu_seconds_total{mode="idle"}[2m]))` | `0.30` |
| Node memory free | `node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes` | `0.50` |

Example of the raw call:

```text
$ curl -s http://localhost:8085/api/v1/query --data-urlencode 'query=sum by (status) (rate(http_requests_total{namespace="podinfo"}[2m]))'
status: success | resultType: vector | series: 1
   {"status":"200"} => 2.115866527777778

$ curl -s http://localhost:8085/api/v1/query --data-urlencode 'query=kube_pod_status_ready{namespace="podinfo", condition="true"}'
status: success | resultType: vector | series: 3
   {"__name__":"kube_pod_status_ready","condition":"true",...,"pod":"podinfo-ff5c6b4f-mgzg6"} => 1
   {"__name__":"kube_pod_status_ready","condition":"true",...,"pod":"podinfo-ff5c6b4f-bjffk"} => 1
   {"__name__":"kube_pod_status_ready","condition":"true",...,"pod":"loadgen"} => 1
```

**What I observed.** These numbers come from four different exporters, all scraped by the same Prometheus:

- CPU and memory per container come from **cAdvisor**, through the kubelet `/metrics/cadvisor` target.
- Readiness and restarts come from **kube-state-metrics**, which reports what the Kubernetes API *says* about objects.
- Probe counts come from the kubelet's own **`/metrics/probes`**.
- Request rate and latency come from **the app itself**.

Node numbers come from **node-exporter**. That split is the main thing I took away from this part. The request rate was only about 2 req/s, not the roughly 10 req/s I'd planned, because busybox `wget` plus a 0.2s sleep is slow. It was still clearly non-zero, and that's all the query needed to show.

### 1.3 Logs

podinfo at the default `info` level only logs its two startup lines. To get useful logs, I switched it to `--level=debug`, which writes one JSON line per request, and re-applied it ([`outputs/05-logs-and-events.txt`](outputs/05-logs-and-events.txt)):

```text
$ kubectl -n podinfo logs deploy/podinfo --tail=6      (first 3 lines)
Found 2 pods, using pod/podinfo-8bc664d66-bfbqv
{"level":"debug","ts":"2026-10-07T18:16:35.955Z","caller":"http/logging.go:21","msg":"request started","proto":"HTTP/1.1","uri":"/","method":"GET","remote":"10.244.0.14:45312","user-agent":"Wget"}
{"level":"debug","ts":"2026-10-07T18:16:36.376Z","caller":"http/logging.go:21","msg":"request started","proto":"HTTP/1.1","uri":"/api/info","method":"GET","remote":"10.244.0.14:45352","user-agent":"Wget"}

$ kubectl -n podinfo logs -l app=podinfo --prefix --tail=2      (first line)
[pod/podinfo-8bc664d66-grd6d/podinfo] {"level":"debug",...,"msg":"request started","uri":"/","method":"GET","remote":"10.244.0.14:45420","user-agent":"Wget"}

$ kubectl -n podinfo logs deploy/podinfo --since=1m | python3 -c "<count lines by msg>"
   52  request started
    1  Starting podinfo
    1  Starting HTTP Server.
```

The events in the same namespace turned out to be just as useful. They show two real problems from this run that metrics alone would hide: transient image-pull failures from ghcr.io/Docker Hub (Docker Desktop was slow), and a readiness 503 while an old pod was shutting down during the rollout:

```text
$ kubectl -n podinfo get events --sort-by=.lastTimestamp --field-selector type=Warning      (trimmed)
2m22s  Warning  Failed     pod/podinfo-ff5c6b4f-mgzg6  Failed to pull image "ghcr.io/stefanprodan/podinfo:6.7.1": ... failed to do request: Head "https://ghcr.i...
90s    Warning  Failed     pod/loadgen                 Failed to pull image "busybox:1.36": ... failed to do request: Head "https://registry-1.docker.io/...
10s    Warning  Unhealthy  pod/podinfo-ff5c6b4f-bjffk  Readiness probe failed: HTTP probe failed with statuscode: 503
```

**Where a log stack fits.** `kubectl logs` only reads the current (and `--previous`) container log files on the node. Those files disappear when the pod is deleted, and you can only search one pod or label selector at a time. A log stack fixes that:

- An agent on each node (Promtail/Grafana Alloy, Fluent Bit or Fluentd) tails `/var/log/pods/*`, adds Kubernetes labels (namespace, pod, container) and ships the lines to a store.
- **Loki** stores them cheaply, indexing only the labels, and you query it from the same Grafana with LogQL, e.g. `{namespace="podinfo"} |= "request started" | json | uri="/api/info"`.
- **EFK** (Elasticsearch + Fluentd/Fluent Bit + Kibana) indexes the full text. That makes search more powerful, but it costs far more RAM.

I did **not** install Loki. The cluster shared roughly 5 GB with other clusters, and Grafana was already OOMKilled once (see notes). The spec marks Loki as optional.

### 1.4 Alerts: PrometheusRule, pending, firing, resolved

[`monitoring/podinfo-prometheusrule.yaml`](monitoring/podinfo-prometheusrule.yaml) has two alerts:

```yaml
- alert: PodinfoDown
  expr: sum(up{namespace="podinfo", job="podinfo"}) == 0 or absent(up{namespace="podinfo", job="podinfo"})
  for: 30s
  labels: {severity: critical}
- alert: PodinfoHighCPU
  expr: sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="podinfo", container="podinfo"}[2m])) > 0.2
  for: 1m
  labels: {severity: warning}
```

I needed `absent()` for this demo. When the Deployment is scaled to 0, the targets don't report `up=0`. They disappear, so `sum(up) == 0` alone would return nothing and never fire.

I triggered **PodinfoDown** for real by scaling to 0, then fixed it by scaling back to 2. Every poll is in [`outputs/06-alert-pending-firing-resolved.txt`](outputs/06-alert-pending-firing-resolved.txt):

```text
$ curl -s localhost:8085/api/v1/rules ...
  group=podinfo.rules alert=PodinfoDown state=inactive health=ok for=30s
  group=podinfo.rules alert=PodinfoHighCPU state=inactive health=ok for=60s

### Break the app: scale podinfo to 0 (23:46:55)
$ kubectl -n podinfo scale deploy/podinfo --replicas=0
--- poll 4 at 23:47:26
  (no Podinfo alerts active)
--- poll 5 at 23:47:36
   PodinfoDown state=pending activeAt=2026-10-07T18:17:34.271241937Z value=1e+00
--- poll 7 at 23:47:56
   PodinfoDown state=pending activeAt=2026-10-07T18:17:34.271241937Z value=1e+00
--- poll 8 at 23:48:06
   PodinfoDown state=firing activeAt=2026-10-07T18:17:34.271241937Z value=1e+00

### Firing, check Alertmanager (23:48:06)
$ curl -s localhost:30104/api/v2/alerts?filter=alertname=~"Podinfo.*"
   PodinfoDown severity=critical state=active startsAt=2026-10-07T18:18:04.271Z endsAt=2026-10-07T18:22:04.271Z summary=podinfo has no healthy scrape targets

### Fix: scale back to 2 (23:48:07)
--- poll 1 at 23:48:13
   PodinfoDown state=firing ...
--- poll 2 at 23:48:23
  (no Podinfo alerts active)

### Alertmanager after resolve (23:48:23)
  (Alertmanager has no Podinfo alerts)
```

**What I observed.**

- It took about 40s from the scale to `pending`. Prometheus first has to notice that the targets are gone (service discovery and scrape interval), then the rule has to be evaluated (15s interval).
- `pending` turned into `firing` exactly 30s after `activeAt` (18:17:34 → 18:18:04). That 30s is the `for:` duration, which keeps a single bad scrape from paging someone.
- Alertmanager's `startsAt` equals the moment the alert started firing.
- `endsAt` is 4 minutes ahead. Prometheus keeps re-sending the alert and pushing that time forward. If Prometheus died, the alert would expire by itself.
- After the fix, the alert disappeared from both APIs within about 15s.
- No receiver is configured (the chart default is the `null` receiver), so no notification was actually sent. In a real setup, the Alertmanager `route` would send `severity=critical` to Slack or PagerDuty.
- I did **not** trigger PodinfoHighCPU: podinfo at about 0.002 cores is far below 0.2. The rule is loaded (`health=ok`, see above), and it would fire the same way under a CPU stress test.

### 1.5 Grafana

The admin password is read from the `kps-grafana` Secret into a shell variable and passed with `curl -u`. It's never printed or written to a file; I grepped the transcript for it afterwards and found 0 matches ([`outputs/07-grafana.txt`](outputs/07-grafana.txt)).

```text
$ curl -s localhost:8084/api/health
{
  "database": "ok",
  "version": "13.2.3",
  ...
}
$ curl -s -u admin:$GPW localhost:8084/api/datasources
   uid=alertmanager name=Alertmanager type=alertmanager url=http://kps-kube-prometheus-stack-alertmanager.monitoring:9093/ isDefault=False
   uid=prometheus name=Prometheus type=prometheus url=http://kps-kube-prometheus-stack-prometheus.monitoring:9090/ isDefault=True

$ curl -s -u admin:$GPW localhost:8084/api/datasources/uid/prometheus/health
{"details":{"application":"Prometheus","features":{"rulerApiEnabled":false}},"message":"Successfully queried the Prometheus API.","status":"OK"}

$ curl -s -u admin:$GPW "localhost:8084/api/search?type=dash-db" | count + a few titles
   dashboards provisioned: 25
    - Alertmanager / Overview  uid=alertmanager-overview
    - Kubernetes / Compute Resources / Namespace (Pods)  uid=85a562078cdf77779eaa1add43ccec1e
    - Kubernetes / Compute Resources / Pod  uid=6581e46e4e5c7ba40a07646395ef7b23
    - Node Exporter / Nodes  uid=7d57716318ee0dddbac5a7f451fb7753
```

A dashboard panel query run *through Grafana*: Grafana's `/api/ds/query` sends it to the Prometheus datasource. This is the same path a panel takes:

```text
$ curl -s -u admin:$GPW -H 'Content-Type: application/json' -X POST localhost:8084/api/ds/query -d '{... "expr":"sum by (pod) (rate(container_cpu_usage_seconds_total{namespace=\"podinfo\",container=\"podinfo\"}[2m]))" ... "expr":"sum(rate(http_requests_total{namespace=\"podinfo\"}[2m]))" ...}'
  refId=A status=200
     labels={"pod": "podinfo-8bc664d66-xdfqb"} value= [0.0017409865479151858]
     labels={"pod": "podinfo-8bc664d66-hxbzl"} value= [0.0018627608662373015]
  refId=B status=200
     labels={} value= [0.1792261620067861]
```

**What I observed.** The chart provisions both datasources and 25 dashboards by itself, through the sidecars: no clicking needed. The request rate through Grafana (0.18 req/s) is lower than the 2.1 req/s in 1.2 because I ran it right after the alert demo. The new pods had been up for less than a minute, so the 2m `rate()` window only covered a few samples. This is something to remember when reading dashboards right after a restart.

---

## Notes and differences from the spec

- **App choice:** podinfo instead of the instructor's busybox `k8s-demo`, because the demo has no `/metrics` endpoint and no HTTP server, even though its Service points at port 8080.
- **Disabled components:** etcd, scheduler, controller-manager and kube-proxy scraping are disabled for kind, as explained in the Setup section. No metrics-server, no Loki.
- **Real problems during the run** ([`outputs/17-restarts-check.txt`](outputs/17-restarts-check.txt)): at 18:21 UTC, while the Argo CD images were being pulled, Grafana was `OOMKilled` (exit 137) at my 256Mi limit, twice. At the same moment, kube-scheduler and kube-controller-manager exited with `"Leaderelection lost"`, because the API server/etcd was too slow on the overloaded node. All of them restarted by themselves, and nothing I measured was affected (the Grafana checks had already run at 23:48). Next time I would give Grafana 384Mi; I added a comment in the values file.
- The transient image-pull errors in the events (1.3) are also real, not staged.
- Teardown: `kind delete cluster --name hw-e` and `docker rm -f hw-e-gitd` ([`outputs/18-cleanup.txt`](outputs/18-cleanup.txt)).
