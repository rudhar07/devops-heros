# monitoring/

| File | Purpose |
|---|---|
| `kube-prometheus-stack-values.yaml` | Trimmed kube-prometheus-stack 92.1.0: Prometheus (NodePort 30112), Grafana (NodePort 30111, FAKE admin password), Alertmanager, kube-state-metrics, node-exporter. Selects ServiceMonitors/PrometheusRules from all namespaces. |
| `grafana-dashboard-taskboard.json` | Dashboard "TaskBoard - API overview" (10 panels: targets up, req/s, 5xx ratio, replicas, req/s by handler, status codes, p50/p95/p99 latency, task write operations, CPU per pod vs request, HPA desired/current). Loaded by the Grafana sidecar from a ConfigMap labelled `grafana_dashboard=1`. |
| `servicemonitor.yaml` | Standalone copy of the ServiceMonitor the chart renders (scrape `http` port `/metrics` every 15 s). |
| `alert-rules.yaml` | Standalone copy of the chart's PrometheusRule: `TaskboardBackendDown` (critical), `TaskboardHighErrorRate` (5xx > 5 %), `TaskboardHighLatencyP95` (> 500 ms). |

The chart only renders the ServiceMonitor and PrometheusRule when the `monitoring.coreos.com/v1` API
exists, so it still installs on a cluster without the Prometheus Operator (the CI kind cluster).

```bash
helm upgrade --install kps oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack \
  --version 92.1.0 -n monitoring --create-namespace -f monitoring/kube-prometheus-stack-values.yaml
kubectl -n monitoring create configmap taskboard-dashboard \
  --from-file=monitoring/grafana-dashboard-taskboard.json --dry-run=client -o yaml \
  | kubectl label --local -f - grafana_dashboard=1 -o yaml | kubectl apply -f -
```
