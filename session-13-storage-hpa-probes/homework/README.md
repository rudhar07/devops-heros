# Session 13: Storage, HPA & Probes - Homework

**Name:** Rudhar Bajaj
**Environment:** macOS (Apple Silicon), Docker Desktop, kind v0.33.0 (single node `hw-b`, Kubernetes v1.37.0,
containerd 2.3.4), kubectl v1.36.1, metrics-server v0.9.0 (with `--kubelet-insecure-tls`), default
StorageClass `standard` = rancher.io/local-path

Every output block below is real output from commands I ran on 2026-10-07. Full untrimmed transcripts
are in `outputs/`. Where I shortened a listing I say so. Times in my polling loops are local (IST),
Kubernetes timestamps are UTC.

## Files

| Path | What it is |
|---|---|
| `kind-hw-b.yaml` | the kind cluster config (one node, NodePorts 30090-30092 mapped to the Mac). Also used for sessions 14 and 15 |
| `01-kubernetes-volumes/README.md` | **Task 1 deliverable:** emptyDir, hostPath, PV, PVC, StorageClass, dynamic provisioning, with real demos |
| `01-kubernetes-volumes/*.yaml` | `emptydir-shared.yaml` (2 containers), `static-pvc.yaml` (PVC that binds to the static PV), `dynamic-pod.yaml` |
| `02-hpa/hpa.yaml` | HPA (copy of `../04-hpa/hpa.yaml` + a 60 s scale-down window) |
| `02-hpa/load-generator.yaml` | in-cluster load generator (busybox wget loop, as a Deployment so I can scale it) |
| `02-hpa/load_generator.sh` | my copy of `../hpa/load_generator.sh`, changed so it runs on my Mac |
| `02-hpa/yatri-backend-deployment.yaml` | the Deployment that `../hpa/` expects (from session 10) |
| `02-hpa/watch-hpa.sh` | timestamped polling loop: HPA target, replicas, ready pods, per-pod CPU |
| `03-probes/*.yaml` | Service for the readiness demo, slow-start app with good and too-short startup probes |
| `mini-project/` | `hpa-30.yaml` (bonus 1), `load-generator.yaml` |
| `outputs/00-cluster-setup.txt` | versions, metrics-server install, StorageClass |
| `outputs/01..04-*.txt` | volume demos (see the volumes README) |
| `outputs/05-hpa-setup.txt`, `06-hpa-load-test.txt` | HPA steps 1-8 |
| `outputs/06b-hpa-yatri-backend.txt` | second HPA run with the instructor's `hpa/` files and `load_generator.sh` |
| `outputs/07-probes.txt` | liveness, readiness, startup |
| `outputs/08..12-mini-project-*.txt` | the mini project |

---

## Task 1 - Kubernetes volumes

The full write-up is in [`01-kubernetes-volumes/README.md`](01-kubernetes-volumes/README.md). Short version of what I ran:

| Demo | Result |
|---|---|
| emptyDir (`../01-volumes/emptydir-pod.yaml`) | file lives under `/var/lib/kubelet/pods/<uid>/volumes/kubernetes.io~empty-dir/`; deleting the pod deletes it |
| emptyDir shared by 2 containers (`emptydir-shared.yaml`) | busybox appends lines, nginx in the same pod serves them over HTTP |
| hostPath (`../01-volumes/hostpath-pod.yaml`) | file visible on the node (`docker exec hw-b-control-plane cat /tmp/hostpath-data/note.txt`), survives pod delete |
| static PV + PVC (`../02-persistent-storage/`) | instructor's PVC got the default class and did **not** bind to `student-pv`; my copy with `storageClassName: ""` bound; data survived pod deletion; `Retain` -> PV `Released` |
| dynamic provisioning (`../03-storageclass/pvc.yaml`) | PVC `Pending` (WaitForFirstConsumer) until a pod used it, then `pvc-ba4558a4-...` was created by `rancher.io/local-path`; deleting the PVC deleted the PV (`Delete`) |

---

## Task 2 - HPA hands-on

### Image choice

`registry.k8s.io/hpa-example` is amd64-only (its manifest is a single v2 schema image, no arm64). So I
used the instructor's own `04-hpa` app: `nginx:1.27` with `requests.cpu: 100m`, `limits.cpu: 200m`. A
busybox `wget` loop against nginx is enough to push it past 50% of 100m.

### Steps 1-3: deploy, configure, verify (`outputs/05-hpa-setup.txt`, `06-hpa-load-test.txt`)

```text
$ kubectl apply -f ../04-hpa/deployment.yaml -f ../04-hpa/service.yaml
deployment.apps/hpa-demo created
service/hpa-demo-service created
$ kubectl apply -f 02-hpa/hpa.yaml
horizontalpodautoscaler.autoscaling/hpa-demo created
$ kubectl get hpa
NAME       REFERENCE             TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
hpa-demo   Deployment/hpa-demo   cpu: <unknown>/50%   1         5         0          0s
```

`<unknown>` for the first ~30 s is normal: metrics-server needs a couple of scrapes. Then:

```text
$ kubectl get hpa hpa-demo
NAME       REFERENCE             TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
hpa-demo   Deployment/hpa-demo   cpu: 5%/50%   1         5         1          31s
$ kubectl top pods -l app=hpa-demo
NAME                        CPU(cores)   MEMORY(bytes)
hpa-demo-5d6676989b-f9cgn   5m           24Mi
$ kubectl describe hpa hpa-demo     (trimmed)
Metrics:                                               ( current / target )
  resource cpu on pods  (as a percentage of request):  5% (5m) / 50%
Behavior:
  Scale Up:
    Stabilization Window: 0 seconds
    Policies:
      - Type: Pods     Value: 4    Period: 15 seconds
      - Type: Percent  Value: 100  Period: 15 seconds
  Scale Down:
    Stabilization Window: 60 seconds
    Policies:
      - Type: Percent  Value: 100  Period: 15 seconds
```

**My one change to the HPA:** `behavior.scaleDown.stabilizationWindowSeconds: 60` (the default is 300).
The default 5-minute scale-down is shown for real in the mini project below.

### Steps 4-7: load generator, more load, CPU, pod scaling

`02-hpa/load-generator.yaml` is the README's busybox loop as a Deployment:
`while true; do wget -q -O- http://hpa-demo-service > /dev/null; done`. I started it with 1 pod, then
scaled it to 3. `02-hpa/watch-hpa.sh` printed one line every ~15 s:

```text
# 4. Deploy the load generator (1 busybox pod in a wget loop) at 21:58:40
TIME     TARGET       REPLICAS  PODS_READY     POD_CPU
21:58:41 5%/50%       1/1       1/1            5m
21:59:11 33%/50%      1/1       1/1            33m
21:59:27 48%/50%      1/1       1/1            48m
21:59:57 50%/50%      1/1       1/1            50m
22:00:12 51%/50%      1/1       1/1            51m
22:00:58 50%/50%      1/1       1/1            50m
# 5. Increase load: scale the load generator to 3 pods at 22:01:13
22:01:14 52%/50%      1/1       1/1            52m
22:01:46 132%/50%     1/3       1/3            132m
22:02:02 159%/50%     3/3       3/3            159m
22:02:24 159%/50%     3/3       3/3            23m 21m 29m
22:03:02 17%/50%      3/3       3/3            18m 19m 15m
22:03:17 47%/50%      3/3       3/3            51m 58m 34m
22:03:33 57%/50%      3/4       4/4            57m 58m 56m
22:03:49 57%/50%      4/4       4/4            56m 58m 58m
# Stop the load at 22:04:21
22:04:23 45%/50%      4/4       4/4            47m 47m 39m 40m
22:05:09 42%/50%      4/4       4/4            18m 42m 40m 27m
22:05:26 31%/50%      4/4       4/4            0m 0m 0m 27m
22:05:57 0%/50%       4/4       4/4            0m 0m 0m 0m
22:06:12 0%/50%       4/3       3/3            0m 0m 0m
22:06:27 0%/50%       3/1       1/1            0m
22:06:43 0%/50%       1/1       1/1            0m
```

(`REPLICAS` is current/desired. Some rows removed. The full timeline is in the transcript.)

### Step 8: captured state under load (22:04:19)

```text
$ kubectl get hpa hpa-demo
NAME       REFERENCE             TARGETS        MINPODS   MAXPODS   REPLICAS   AGE
hpa-demo   Deployment/hpa-demo   cpu: 45%/50%   1         5         4          6m11s

$ kubectl get pods -o wide     (columns trimmed)
NAME                              READY   STATUS    RESTARTS   AGE     IP
hpa-demo-5d6676989b-7zsxt         1/1     Running   0          2m38s   10.244.0.27
hpa-demo-5d6676989b-9mmwh         1/1     Running   0          2m38s   10.244.0.26
hpa-demo-5d6676989b-f9cgn         1/1     Running   0          6m12s   10.244.0.17
hpa-demo-5d6676989b-m24df         1/1     Running   0          53s     10.244.0.28
load-generator-866cd7486d-chngx   1/1     Running   0          5m40s   10.244.0.18
load-generator-866cd7486d-w27sg   1/1     Running   0          3m7s    10.244.0.24
load-generator-866cd7486d-wgg4j   1/1     Running   0          3m7s    10.244.0.23

$ kubectl top pods
NAME                              CPU(cores)   MEMORY(bytes)
hpa-demo-5d6676989b-7zsxt         47m          11Mi
hpa-demo-5d6676989b-9mmwh         47m          12Mi
hpa-demo-5d6676989b-f9cgn         39m          12Mi
hpa-demo-5d6676989b-m24df         40m          11Mi
load-generator-866cd7486d-chngx   431m         5Mi
load-generator-866cd7486d-w27sg   497m         5Mi
load-generator-866cd7486d-wgg4j   493m         4Mi

$ kubectl describe hpa hpa-demo | sed -n '/Events:/,$p'     (metric warm-up warnings removed)
  Normal   SuccessfulRescale             2m39s  horizontal-pod-autoscaler  New size: 3; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             54s    horizontal-pod-autoscaler  New size: 4; reason: cpu resource utilization (percentage of request) above target
```

After the load stopped (`outputs/06-hpa-load-test.txt`, end):

```text
  Normal   SuccessfulRescale             3m40s  horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
  Normal   SuccessfulRescale             3m25s  horizontal-pod-autoscaler  New size: 1; reason: All metrics below target
```

**What I observed:**
- **The math:** desired = ceil(current replicas x current% / target%). At 159% with 1 pod:
  my poll just before the first scale-up showed `132%`, and ceil(1 x 132/50) = 3, which matches the first
  step 1 -> 3. Later, 57% with 3 pods gives ceil(3 x 57/50) = 4, which matches the second step.
- **Tolerance:** with one load pod the CPU sat at 48-52% for over a minute and nothing happened. The
  HPA ignores changes within 10% of the target (0.9-1.1x), so 51/50 is "close enough".
- **4 replicas, not 5:** with 3 load pods each load pod hit its own 500m CPU limit (`431m/497m/493m` in
  `top`). The load generator was the bottleneck: the 4 nginx pods used 47+47+39+40 = 173m in total. Divided over 4
  nginx pods that's ~45%, under the target, so it settled at 4.
- **Scale-down:** the load really ended about a minute after I deleted the load generator, because busybox
  `sh` ignores SIGTERM and the pods waited out the 30 s grace period. The HPA then went 4 -> 3 -> 1
  within ~60 s, as I configured.

### Second run with the `hpa/` folder (`outputs/06b-hpa-yatri-backend.txt`)

The instructor's `hpa/` files target a `yatri-backend` Deployment (python http.server on :5000) that only
exists in session 10, so I copied it (`02-hpa/yatri-backend-deployment.yaml`, replicas 2 to match
`minReplicas: 2`) and applied it with `../hpa/backend-service.yaml` and `../hpa/hpa-backend.yaml` in a
namespace `yatri`. Then I ran my copy of `load_generator.sh` for 150 s. My changes: local port 30093
(macOS AirPlay already uses 5000), namespace variable, `DURATION` auto-stop, target `/` (python
http.server has no `/healthz`).

```text
TIME     TARGET       REPLICAS  PODS_READY     POD_CPU
22:57:14 35%/50%      2/2       2/2            73m 2m
22:58:15 33%/50%      2/2       2/2            66m 1m
22:59:01 36%/50%      2/2       2/2            72m 1m
# Who got the traffic? (python http.server logs one line per request)
pod/yatri-backend-cbc55c649-vzgsh requests logged: 4000
pod/yatri-backend-cbc55c649-xr8w7 requests logged: 0
```

**It did not scale, and the reason is the method:** `kubectl port-forward svc/...` picks **one** pod and
tunnels everything to it. It doesn't load-balance through the Service. One pod at ~70m and one idle pod
average 35%, under the target. Port-forward is fine to test that a service works, but not to load test an
HPA. For that the load has to come from inside the cluster (my busybox Deployment) or through a real
Service/Ingress.

### Probes (`05-probes/`, `outputs/07-probes.txt`)

All in namespace `probes`.

**Liveness** (`../05-probes/liveness.yaml`). I broke it by deleting nginx's `index.html`, so `GET /` returns 403:

```text
$ kubectl -n probes exec liveness-demo -- curl -s -o /dev/null -w '%{http_code}' http://localhost/
403
22:00:00 liveness-demo   1/1   Running   0     13s
22:00:03 liveness-demo   1/1   Running   1 (1s ago)   16s
Events:
  Warning  Unhealthy  16s (x3 over 26s)  kubelet  spec.containers{nginx}: Liveness probe failed: HTTP probe failed with statuscode: 403
  Normal   Killing    16s                kubelet  spec.containers{nginx}: Container nginx failed liveness probe, will be restarted
# After the restart the container's writable layer is fresh, so index.html is back:
200
```

3 failures x 5 s period, then a restart. The restart "fixed" it because a new container starts from the image again.

**Readiness** (`../05-probes/readiness.yaml` + my `03-probes/readiness-service.yaml`). Same 403 trick:

```text
$ kubectl -n probes get endpointslices -l kubernetes.io/service-name=readiness-svc
readiness-svc-dtj77   IPv4          80      10.244.0.20   6s
22:00:37 readiness-demo   1/1   Running   0     18s
22:00:41 readiness-demo   0/1   Running   0     22s
10.244.0.20 ready=false
$ kubectl -n probes get endpoints readiness-svc
NAME            ENDPOINTS   AGE
readiness-svc               25s
  Warning  Unhealthy  4s (x4 over 14s)  kubelet  spec.containers{nginx}: Readiness probe failed: HTTP probe failed with statuscode: 403
# Fix it: put index.html back (no restart needed)
readiness-demo   1/1     Running   0          26s
readiness-svc   10.244.0.20:80   26s
```

No restart (RESTARTS stayed 0). The pod was only taken out of the Service and put back.

**Startup.** The instructor's `startup.yaml` uses plain nginx, which starts in under a second
(`started=true` right away), so I wrote an app that takes 20 s to start (`sh -c "sleep 20; exec nginx"`):

```text
# startup-slow.yaml: failureThreshold 30 x periodSeconds 2 = 60 s allowed
22:00:51 startup-slow   0/1   Running   0     4s  started=false
22:01:10 startup-slow   0/1   Running   0     22s  started=false
22:01:13 startup-slow   1/1   Running   0     25s  started=true
  Warning  Unhealthy  11s (x10 over 29s)  kubelet  spec.containers{nginx}: Startup probe failed: Get "http://10.244.0.22:80/": dial tcp 10.244.0.22:80: connect: connection refused
Restart Count:  0

# startup-too-short.yaml: failureThreshold 3 x periodSeconds 2 = 6 s allowed
22:01:58 startup-too-short   0/1   Running   0     38s
22:02:02 startup-too-short   0/1   Running   1 (5s ago)   42s
    Last State:     Terminated
      Reason:       Error
      Exit Code:    137
  Normal   Killing    31s (x2 over 69s)  kubelet  spec.containers{nginx}: Container nginx failed startup probe, will be restarted
```

With enough budget, the 10 failed startup checks are harmless and liveness/readiness only start after it
passes. With 6 s it can never finish starting and gets killed in a loop. The first kill took ~36 s, not
6 s: `sh` (PID 1 during the sleep) ignores SIGTERM, so the kubelet waited the 30 s grace period and then
sent SIGKILL (exit 137).

| Probe | Question | On failure | What I saw |
|---|---|---|---|
| startup | has it finished starting? | kill + restart; holds off the other probes | slow app OK with 60 s budget, restart loop with 6 s |
| liveness | is it still working? | kill + restart | 403 -> restart after ~15 s |
| readiness | can it take traffic now? | removed from Service endpoints, no restart | endpoints empty, then back |

---

## Task 3 - Mini project: production-ready web app

All instructor files from `../mini-project/` applied unchanged. My extra files: `mini-project/hpa-30.yaml`
(bonus 1) and `mini-project/load-generator.yaml`.

**Deploy (`outputs/08-mini-project-deploy.txt`):**

```text
$ kubectl apply -f ../mini-project/pvc.yaml
$ kubectl -n production-webapp get pvc
NAME       STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
web-data   Pending                                      standard
$ kubectl apply -f ../mini-project/deployment.yaml -f ../mini-project/service.yaml
$ kubectl -n production-webapp get pvc
web-data   Bound    pvc-dc16dabc-d278-4082-ae40-449f3b152a51   500Mi      RWO            standard
$ kubectl -n production-webapp get pods -o wide
web-app-d45775485-hfb4p   1/1     Running   0          13s   10.244.0.131   hw-b-control-plane
web-app-d45775485-jcx8m   1/1     Running   0          13s   10.244.0.130   hw-b-control-plane
$ kubectl -n production-webapp get hpa
web-app-hpa   Deployment/web-app   cpu: 2%/50%   2         5         2          31s
```

Differences from the README's expected output: the class here is kind's `standard` (rancher.io/local-path),
not minikube-hostpath, and the PVC is `Pending` until the first pod exists because of `WaitForFirstConsumer`.

**Verification Task 1, storage persistence (`outputs/09-...`):**

```text
$ kubectl -n production-webapp exec web-app-d45775485-hfb4p -- sh -c 'echo "Student: Rudhar Bajaj (roll 10143)" > /data/student.txt'
$ kubectl -n production-webapp exec web-app-d45775485-jcx8m -- cat /data/student.txt
Student: Rudhar Bajaj (roll 10143)
$ kubectl -n production-webapp delete pod web-app-d45775485-hfb4p
$ kubectl -n production-webapp exec web-app-d45775485-qz4pb -- cat /data/student.txt
Student: Rudhar Bajaj (roll 10143)
$ docker exec hw-b-control-plane sh -c "cat /var/local-path-provisioner/pvc-dc16dabc-..._production-webapp_web-data/student.txt"
Student: Rudhar Bajaj (roll 10143)
```

Both replicas share one RWO volume. That works only because both are on the same node: RWO means one
*node*, not one pod. On a multi-node cluster the second replica could get stuck in ContainerCreating with a
Multi-Attach error. That's probably why the instructor used `strategy: Recreate`.

**Verification Task 2, service:**

```text
$ kubectl -n production-webapp port-forward svc/web-service 30094:80 &
$ curl -s http://localhost:30094 | head -5
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```

(Local port 30094 instead of 8080, because 8080 on my Mac is used by another container.)

**Verification Task 3, HPA (`outputs/10-...`, `11-...`, `12-...`).**
1. With the instructor's 50% target and 2 load pods, it did **not** scale:

```text
23:19:05 51%/50%      2/2       2/2            53m 50m
23:20:36 55%/50%      2/2       2/2            57m 54m
23:21:53 54%/50%      2/2       2/2            53m 55m
$ kubectl -n production-webapp top pods
load-generator-68488dd975-2dvt9   501m         7Mi
load-generator-68488dd975-djdq9   500m         6Mi
web-app-d45775485-jcx8m           53m          12Mi
web-app-d45775485-qz4pb           54m          12Mi
```

   55/50 = 1.10, which is still inside the 10% tolerance. The load pods were capped at their 500m limit.
   The README's "110%/50%" assumes a stronger load than two busybox pods can make here.

2. **Bonus 1 (target 30%)**, same load:

```text
23:29:47 5%/30%       2/2       2/2            51m 54m
23:30:02 52%/30%      2/4       2/4            51m 50m
23:30:17 50%/30%      4/4       4/4            18m 14m 47m 53m
23:30:49 31%/30%      4/4       4/4            29m 29m 29m 29m
23:31:36 29%/30%      4/4       4/4            26m 27m 26m 29m
  Normal   SuccessfulRescale             2m    horizontal-pod-autoscaler  New size: 4; reason: cpu resource utilization (percentage of request) above target
```

   ceil(2 x 52/30) = 4. The same total work (~105m before, ~105-120m after) spread over 4 pods is
   ~27-30% each, so it stopped at 4. A lower target scales out sooner and further for the same load.

3. **Default 5-minute scale-down.** After bonus 1 I stopped the load (~23:31:40) and re-applied the
   instructor's `hpa.yaml` (no `behavior` block = 300 s window):

```text
23:35:06 1%/50%       4/4       4/4            2m 1m 1m 1m
23:35:36 1%/50%       4/4       4/4            1m 1m 1m 1m
23:36:07 1%/50%       4/4       4/4            1m 2m 1m 1m
23:36:37 1%/50%       4/4       4/4            1m 1m 1m 1m
23:37:08 1%/50%       3/2       2/2            1m 1m
23:37:38 1%/50%       2/2       2/2            1m 1m
  Normal   SuccessfulRescale             4m1s                 horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
  Normal   SuccessfulRescale             3m46s                horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
  ScalingLimited  True    TooFewReplicas    the desired replica count is less than the minimum replica count
```

   CPU was at 1% from 23:35 but replicas stayed at 4 until ~23:37, about 5 minutes after the last high
   recommendation. Compare my 60 s window in Task 2. It stopped at 2 (`minReplicas`), and the condition
   says so.

**Bonus 2, readiness gating** (`outputs/11-...`). I patched the live Deployment's readiness path to
`/does-not-exist` instead of editing the instructor's file:

```text
web-app-5945bfc776-28gg7   0/1     Running   0          40s
...
$ kubectl -n production-webapp get endpoints web-service
NAME          ENDPOINTS   AGE
web-service               14m
10.244.0.154 ready=false
  Warning  Unhealthy  5s (x6 over 30s)  kubelet  spec.containers{nginx}: Readiness probe failed: HTTP probe failed with statuscode: 404
```

Exactly as the README says: `Running` but `0/1`, endpoints empty, 0 restarts. Because the strategy is
`Recreate`, all 4 old pods were killed first, so this was a full outage. With RollingUpdate, the
old pods would have stayed until the new ones were Ready. `kubectl rollout undo` restored it.

**Bonus 3, liveness restart loop** (`/crash`):

```text
23:33:05 web-app-85d86b65d-lgng2 1/1 Running 0 20s
23:33:10 web-app-85d86b65d-lgng2 0/1 Running 1 (4s ago) 25s
23:33:30 web-app-85d86b65d-lgng2 0/1 Running 2 (4s ago) 45s
23:33:51 web-app-85d86b65d-lgng2 0/1 Running 3 (5s ago) 66s
  Warning  Unhealthy  1s (x12 over 71s)  kubelet  spec.containers{nginx}: Liveness probe failed: HTTP probe failed with statuscode: 404
  Normal   Killing    1s (x4 over 61s)   kubelet  spec.containers{nginx}: Container nginx failed liveness probe, will be restarted
  Warning  BackOff    0s                 kubelet  spec.containers{nginx}: Back-off restarting failed container nginx in pod web-app-85d86b65d-lgng2_production-webapp(...)
```

A restart about every 20 s: 5 s initial delay + 3 failures x 5 s, plus the restart itself, a bit more than
the README's 15 s. After `rollout undo`, the file on the PVC was still there:
`Student: Rudhar Bajaj (roll 10143)`.

**Troubleshooting guide items from the README that I actually hit:** `TARGETS <unknown>/50%` right after
creating an HPA (metrics warm-up, and again during the host memory problem described in session 14's
README). PVC `Pending`, which here was `WaitForFirstConsumer` and not an error.

## Notes / honest differences

- Screenshots are replaced by the text transcripts in `outputs/`.
- The Docker VM I used is shared with other clusters. For a while it ran out of memory: metrics-server
  and the control plane restarted, and `kubectl top` failed (see the end of `06-hpa-load-test.txt`).
  The details and the fix are in `../../session-14-kubernetes-troubleshooting/homework/outputs/12-real-incident-control-plane.txt`.
  It happened after the main HPA run, so that run wasn't affected.
