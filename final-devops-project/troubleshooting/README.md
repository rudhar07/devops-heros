# troubleshooting/ - final troubleshooting challenge

Six faults across six layers, each broken on purpose, then found, explained, fixed and verified.
The two `instructor-*.yaml` files are unchanged copies of `session21-python/troubleshooting/`.

| # | Layer | File | Symptom | Root cause | Fix | Transcript |
|---|---|---|---|---|---|---|
| 1 | Config | `case1-wrong-db-host.values.yaml` | new pod stuck `Init:0/2`, `helm --wait` times out | `DB_HOST=taskboard-postgress` (typo) -> NXDOMAIN | `helm rollback` | `outputs/15-...` |
| 2 | Image | `case2-bad-image-tag.values.yaml` (+ `instructor-broken-image.yaml`) | `Init:ImagePullBackOff` | tag `v2.0.1-typo` never built | `helm rollback` | `outputs/16-...` |
| 3 | Service | `case3-service-selector.patch.json` (+ `instructor-broken-service.yaml`) | API 503, pods all Ready, alert `TaskboardBackendDown` fires | selector `component=api`, pods are `component=backend` -> 0 endpoints | `helm upgrade --force-conflicts` | `outputs/17-...` |
| 4 | Ingress | `case4-broken-ingress.yaml` | 503 on `/api` and `/` | Service port 8080 (real: 8000) and a Service name that does not exist | named port `http`, correct Service | `outputs/18-...` |
| 5 | Probes | `case5-bad-liveness-path.values.yaml` | `CrashLoopBackOff`, full outage | liveness on `/healthz` (nginx path), backend answers 404 | `helm rollback` | `outputs/19-...` |
| 6 | Autoscaling | `case6-hpa-no-requests.yaml` / `case6-hpa-fixed.yaml` | HPA `cpu: <unknown>/50%` | no CPU request -> utilisation cannot be computed | add `resources.requests` | `outputs/20-...` |
