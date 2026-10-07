# Task 2: Observability

**Name:** Rudhar Bajaj

This page is mostly documentation, but I tie every section back to something I actually ran in Task 1 ([`../README.md`](../README.md)), with the transcript that shows it. Traces stay conceptual: I didn't deploy a tracing backend (reasons at the end).

## 1. Monitoring vs observability

| | Monitoring | Observability |
|---|---|---|
| Question | "Is something wrong?" | "*Why* is it wrong, and where?" |
| You need to know in advance | which failure to watch for (you write the alert) | nothing: you explore the data after the fact |
| Typical output | dashboards, threshold alerts | ad-hoc queries that join metrics, logs and traces |
| Good at | known failure modes | new, never-seen-before failures |
| Example from my run | `PodinfoDown` went pending → firing when I scaled podinfo to 0 (`outputs/06`) | working out *why* Grafana restarted: restart count (metric) → `OOMKilled`, exit 137 (pod status) → scheduler log `"Leaderelection lost"` at the same second (logs) → the node was busy pulling Argo CD (timeline). See `outputs/17` |

**Why observability is needed on top of monitoring.** A monitoring alert can only fire for something someone predicted. With microservices on Kubernetes, many failures are combinations nobody predicted: pods move between nodes, IPs change, one slow dependency makes five services look slow. Observability means the system emits enough well-labelled data (metrics, logs, traces) that you can ask a *new* question without shipping new code. The two work together: monitoring tells you to look, observability tells you where.

## 2. The three pillars

| Pillar | What it is | Shape | Best for | Weak at | What I ran in Task 1 |
|---|---|---|---|---|---|
| **Metrics** | Numbers sampled over time, with labels | `http_requests_total{status="200"} 1234 @ t` | trends, rates, percentiles, alerting; cheap to keep | the *details* of a single request | Prometheus scraping podinfo through a ServiceMonitor; `rate(http_requests_total[2m])` = 2.12 req/s, p95 = 4.8 ms (`outputs/04`) |
| **Logs** | Timestamped event records, ideally structured (JSON) | `{"ts":"…","msg":"request started","uri":"/api/info"}` | what exactly happened, error messages, audit | aggregates over time (expensive to compute from logs) | `kubectl logs -l app=podinfo` with one JSON line per request; counted 52 `request started` lines in 1 minute (`outputs/05`) |
| **Traces** | The path of one request through every service, as a tree of timed *spans* that share a trace ID | `trace 4bf9… : api 500ms → users 200ms → db 1.2s` | latency breakdown across services, finding the slow hop | needs instrumentation in every service; usually sampled | not run (conceptual, see 2.1) |

How they connect in practice: an alert fires on a **metric**, an exemplar or trace ID on that metric jumps to the slow **trace**, and the trace ID in the span takes you to the exact **log** lines. Grafana does this with Prometheus + Tempo + Loki, and Datadog and New Relic do it in one product.

### 2.1 Traces in a bit more detail

- A **trace** = one request end to end. A **span** = one operation inside it (an HTTP handler, a DB query), with a start time, a duration and attributes.
- The trace context is passed between services in an HTTP header (W3C `traceparent: 00-<trace-id>-<span-id>-01`), so each service adds its spans to the same trace.
- **OpenTelemetry** is the vendor-neutral standard for this: SDKs that create spans, plus the **OTel Collector**, which receives, batches and exports them to Jaeger, Tempo, Datadog and so on.
- podinfo actually has OpenTelemetry support built in (`--otel-service-name`, which exports over OTLP), so the next step from my demo would be an OTel Collector plus Jaeger all-in-one. I left that out to save memory.

## 3. Common tools

| Tool | Pillar(s) | Role | Notes |
|---|---|---|---|
| **Prometheus** | metrics | pull-based scraper + time-series DB + PromQL + rule engine | I used it through the Prometheus Operator (ServiceMonitor, PrometheusRule CRDs) |
| **Alertmanager** | (alerts) | dedupes, groups, silences and routes alerts from Prometheus to Slack, PagerDuty or email | my `PodinfoDown` showed up there as `state=active` |
| **Grafana** | all (UI) | dashboards and exploration over many datasources | I queried it via `/api/ds/query`; it came with 25 dashboards |
| **Loki** | logs | log store that indexes only labels; LogQL; cheap | needs an agent (Promtail/Alloy/Fluent Bit) |
| **ELK / EFK** | logs | Elasticsearch (store + full-text index), Logstash or Fluentd/Fluent Bit (ship), Kibana (UI) | powerful search, but heavy on RAM and disk |
| **Jaeger** | traces | trace collector, store and UI (CNCF) | all-in-one image for labs |
| **Grafana Tempo** | traces | trace store on cheap object storage, links to Loki and Prometheus | |
| **OpenTelemetry** | all three | standard APIs, SDKs and the Collector; not a backend itself | avoids vendor lock-in in your code |
| **Datadog / New Relic** | all three (SaaS) | hosted agents, APM, dashboards, alerting in one place | no ops work, but you pay per host, GB or span |

## 4. Kubernetes observability: who provides what

These four sources are easy to confuse. In Task 1 every one of them except metrics-server answered a real query:

| Component | Runs as | What it measures | Used by | In my run |
|---|---|---|---|---|
| **cAdvisor** | built into the kubelet (`/metrics/cadvisor`) | *actual* container usage: CPU seconds, memory working set, network, filesystem | Prometheus | `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes` (`outputs/04`, queries 2 and 3) |
| **metrics-server** | Deployment in kube-system | a *short-lived* in-memory summary of CPU and memory, read from the kubelets | `kubectl top`, HPA, VPA | not installed: I read the same data from cAdvisor through Prometheus, and nothing needed `kubectl top` or an HPA |
| **kube-state-metrics** | Deployment | the *state of API objects*: desired vs available replicas, pod phase and readiness, restarts, resource requests and limits | Prometheus | `kube_pod_status_ready`, `kube_pod_container_status_restarts_total`, `kube_pod_container_resource_limits` (queries 3b, 5, 5c) |
| **node-exporter** | DaemonSet (host network) | the *node's OS*: CPU modes, memory, disk, filesystem, network | Prometheus | `node_cpu_seconds_total`, `node_memory_MemAvailable_bytes` (query 6) |

The rule of thumb I use: cAdvisor and metrics-server tell you **how much a container uses**, kube-state-metrics tells you **what Kubernetes thinks the object's state is**, and node-exporter tells you **how the machine is doing**.

Other Kubernetes signals:

| Signal | What it tells you | In my run |
|---|---|---|
| **Events** (`kubectl get events`) | short-lived (about 1h) records of what controllers and the kubelet did: scheduling, image pulls, probe failures, scaling | `Failed to pull image ... ghcr.io`, `Readiness probe failed: ... 503` (`outputs/05`); `ScalingReplicaSet` during the GitOps rollout (`outputs/12`) |
| **Probes** (liveness, readiness, startup) | the kubelet's health checks; failed readiness removes the pod from the Service endpoints, failed liveness restarts the container | podinfo `/healthz` and `/readyz`; `prober_probe_total` from `/metrics/probes`; the 503 during shutdown is podinfo marking itself not-ready before exit |
| **Pod status / lastState** | why a container died: `OOMKilled`, `Error`, exit codes | Grafana `lastState=OOMKilled exit=137` (`outputs/17`) |
| **Control-plane metrics** | API server latency, etcd, scheduler | `apiserver` and `coredns` targets up; scheduler/controller-manager/etcd scraping disabled on kind (see Setup in the main README) |
| **Container logs** | stdout/stderr of each container | `kubectl logs`, which a log agent would ship to Loki or EFK |

## 5. What I would add for full observability of podinfo

1. **Logs:** Loki + Grafana Alloy (or Promtail) as a DaemonSet, so logs survive pod deletion and are searchable next to the metrics in Grafana.
2. **Traces:** start podinfo with `--otel-service-name=podinfo`, run an OTel Collector, and export to Tempo or Jaeger.
3. **Links between them:** put the trace ID in the log lines, and enable exemplars on the latency histogram so a Grafana panel jumps from a slow bucket to an example trace.
4. **SLO alerts** on error rate and latency (e.g. 99% of requests under 100ms), instead of only "is it up".

I didn't add these here because the kind node shared about 5 GB of RAM with two other clusters. Grafana was already OOMKilled once at a 256Mi limit, and Loki + Tempo + a Collector would have added several hundred MB more.
