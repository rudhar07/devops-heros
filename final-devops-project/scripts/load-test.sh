#!/usr/bin/env bash
# Short load test to make the backend HPA scale out.
#
# Starts a throw-away curl pod INSIDE the cluster with $WORKERS parallel loops
# hitting the backend Service for $DURATION seconds (in-cluster, so the laptop
# network and the Ingress are not the bottleneck). The instructor's version
# looped 500 sequential curls from the laptop, which is not enough CPU for the
# HPA to react.
#
#   NAMESPACE=taskboard DURATION=150 WORKERS=8 scripts/load-test.sh
#   watch: kubectl -n taskboard get hpa -w
set -euo pipefail
NAMESPACE="${NAMESPACE:-taskboard}"
SERVICE="${SERVICE:-taskboard-backend}"
PORT="${PORT:-8000}"
DURATION="${DURATION:-150}"
WORKERS="${WORKERS:-8}"
TARGET="http://${SERVICE}.${NAMESPACE}.svc:${PORT}"

kubectl -n "$NAMESPACE" delete pod loadgen --ignore-not-found --wait=true >/dev/null
kubectl -n "$NAMESPACE" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: loadgen
  labels: {app: loadgen}
spec:
  restartPolicy: Never
  securityContext: {runAsNonRoot: true, runAsUser: 100}
  containers:
    - name: loadgen
      image: curlimages/curl:8.5.0
      resources:
        requests: {cpu: 50m, memory: 32Mi}
        limits: {cpu: "1", memory: 64Mi}
      command: ["sh", "-c"]
      args:
        - |
          end=\$((\$(date +%s) + ${DURATION}))
          for w in \$(seq 1 ${WORKERS}); do
            ( n=0
              while [ \$(date +%s) -lt \$end ]; do
                curl -s -o /dev/null ${TARGET}/api/tasks
                curl -s -o /dev/null "${TARGET}/api/tasks?q=helm&status=DONE"
                curl -s -o /dev/null ${TARGET}/api/tasks/stats
                n=\$((n+3))
              done
              echo "worker \$w sent \$n requests" ) &
          done
          wait
          echo "load test finished"
YAML
echo "loadgen pod started: ${WORKERS} workers x ${DURATION}s against ${TARGET}"
