# kubernetes/ - raw manifests

The same application as the Helm chart, written out by hand (no templating), so each object is
easy to read. The Helm chart in `../helm/taskboard` is what I actually deploy and what ArgoCD syncs;
these files show the objects underneath.

| File | Objects |
|---|---|
| `kind-hw-f.yaml` | kind cluster config (single node, host ports 30110-30113) |
| `00-namespace.yaml` | Namespace `taskboard` (used by the Helm release) |
| `01-configmap.yaml` | ConfigMap: APP_ENV, LOG_LEVEL, DB_HOST, DB_PORT, DB_NAME |
| `02-secret.example.yaml` | Secret template with a FAKE password (DB_USER / DB_PASSWORD) |
| `10-postgres.yaml` | PVC (1Gi) + Deployment (Recreate) + Service for PostgreSQL |
| `20-backend.yaml` | Backend Deployment (2 replicas, initContainers, probes, requests) + Service |
| `30-frontend.yaml` | Frontend Deployment (2 replicas, probes) + Service |
| `40-ingress.yaml` | Ingress: `/` -> frontend, `/api` -> backend (host `taskboard-raw.localhost`) |
| `50-hpa.yaml` | HPA for the backend, CPU 50%, 2-4 replicas |

The manifests have no `metadata.namespace`, so they go wherever `-n` points:

```bash
kubectl create namespace taskboard-raw
for f in kubernetes/[0-9]*.yaml; do args="$args -f $f"; done
kubectl apply -n taskboard-raw --dry-run=server $args   # validated by the API server, nothing stored
kubectl apply -n taskboard-raw $args
```

`kubernetes/[0-9]*.yaml` skips `kind-hw-f.yaml` (a kind config, not a Kubernetes object). The
Namespace in `00-namespace.yaml` is cluster-scoped, so `-n` does not affect it. Real run:
`../outputs/11-raw-manifests.txt`.
