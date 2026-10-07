#!/usr/bin/env bash
# Copy of ../../hpa/load_generator.sh with three changes so it runs on my Mac:
#  1. local port 30093 instead of 5000 (macOS AirPlay Receiver already listens on 5000)
#  2. namespace is configurable (NS env var, default "yatri")
#  3. DURATION env var: stop by itself after N seconds (default 0 = run until Ctrl+C)
# Default target is "/" because python http.server has no /healthz route (it returns 404,
# which still costs CPU, but "/" is a real page).
set -euo pipefail
NS="${NS:-yatri}"
LPORT=30093
TARGET_URL="${1:-http://localhost:${LPORT}/}"
DURATION="${DURATION:-0}"

echo "=================================================="
echo "      KUBERNETES HPA TRAFFIC LOAD GENERATOR       "
echo "=================================================="
echo "Pounding target endpoint: $TARGET_URL"

PIDS=()
cleanup(){ kill "${PIDS[@]}" 2>/dev/null || true; }
trap cleanup EXIT

if ! curl -s -f "$TARGET_URL" > /dev/null 2>&1; then
    echo "Starting port-forward to yatri-backend-service in namespace $NS on port $LPORT..."
    kubectl -n "$NS" port-forward svc/yatri-backend-service ${LPORT}:80 > /dev/null 2>&1 &
    PIDS+=($!)
    sleep 2
fi

for i in {1..10}; do
    ( while true; do curl -s "$TARGET_URL" > /dev/null || true; done ) &
    PIDS+=($!)
done
echo "Traffic load active with 10 curl workers."

if [ "$DURATION" -gt 0 ]; then sleep "$DURATION"; echo "Stopping after ${DURATION}s"; else wait; fi
