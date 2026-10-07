#!/usr/bin/env bash
# Timestamped polling loop: prints HPA target/replicas and pod count every N seconds.
# usage: watch-hpa.sh <hpa-name> <label-selector> <seconds-total> [interval] [namespace]
HPA=$1; SEL=$2; TOTAL=$3; INT=${4:-15}; NS=${5:-default}
end=$(( $(date +%s) + TOTAL ))
printf "%-8s %-12s %-9s %-14s %s\n" TIME TARGET REPLICAS PODS_READY POD_CPU
while [ "$(date +%s)" -lt "$end" ]; do
  cur=$(kubectl -n "$NS" get hpa "$HPA" -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)
  tgt=$(kubectl -n "$NS" get hpa "$HPA" -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}')
  rep=$(kubectl -n "$NS" get hpa "$HPA" -o jsonpath='{.status.currentReplicas}/{.status.desiredReplicas}')
  ready=$(kubectl -n "$NS" get pods -l "$SEL" --no-headers 2>/dev/null | awk '{split($2,a,"/"); if(a[1]==a[2] && $3=="Running") r++; t++} END{printf "%d/%d", r, t}')
  cpu=$(kubectl -n "$NS" top pods -l "$SEL" --no-headers 2>/dev/null | awk '{printf "%s ", $2}')
  printf "%-8s %-12s %-9s %-14s %s\n" "$(date +%H:%M:%S)" "${cur:-?}%/${tgt}%" "$rep" "$ready" "$cpu"
  sleep "$INT"
done
