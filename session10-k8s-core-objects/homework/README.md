# Pods, ReplicaSets & Deployments - Homework

**Name:** Rudhar Bajaj
**Environment:** macOS 26.5.2 (Apple Silicon), Docker Desktop (Engine 29.6.1), kind v0.33.0 single-node cluster `hw-a` (Kubernetes v1.37.0, containerd 2.3.4), kubectl v1.36.1

Every output block below is real output from commands I ran on 2026-10-07. Full untrimmed transcripts are in `outputs/`. Where I shortened a listing I say so.

| File | Contents |
|---|---|
| `outputs/00-cluster-setup.txt` | kind cluster `hw-a` creation (config: `cluster/kind-hw-a.yaml`) |
| `outputs/00b-control-plane-restart.txt` | why I recreated the cluster: scheduler/controller-manager losing leader election, OOM in the Docker VM |
| `outputs/01-rolling-update.txt` | rolling update: watch, 280-request traffic loop, ReplicaSets, rollback |
| `outputs/01b-rolling-update-prestop.txt` | the same rolling update with a `preStop` hook added |
| `outputs/02-blue-green.txt` | blue/green: switch and switch back via the Service selector |
| `outputs/03-canary.txt` | canary 9:1 and 5:5 under one Service, 100-request counts, iptables counters |
| `outputs/04-recreate.txt` | Recreate: watch shows all v1 pods gone before v2 starts, request loop shows the gap |
| `outputs/lifecycle-01-running.txt` ... `lifecycle-12-termination.txt` | one file per pod-lifecycle YAML |

YAML used: `strategies/01-rolling-update` ... `strategies/04-recreate` are copies of the instructor's files. They already run on arm64 (`nginx:*-alpine` is multi-arch) and already identify the version (a `postStart` hook writes `VERSION: v1/v2` into the page), so I used them unchanged. I added `strategies/client-pod.yaml` (a curl pod) and two `*-prestop.yaml` variants (Task 1.1 follow-up). For Task 2 I applied the instructor's `pod-lifecycle/*.yaml` directly.

## Contents

- [Setup and a note about my laptop](#setup-and-a-note-about-my-laptop)
- [Task 1 - Deployment strategies](#task-1---deployment-strategies)
  - [1.1 Rolling update](#11-rolling-update)
  - [1.2 Blue-green](#12-blue-green)
  - [1.3 Canary](#13-canary)
  - [1.4 Recreate](#14-recreate)
  - [Comparison](#comparison)
- [Task 2 - Pod lifecycle](#task-2---pod-lifecycle)
  - [01 Running](#01-running) · [02 Pending](#02-pending) · [03 Succeeded](#03-succeeded) · [04 Failed](#04-failed) · [05 CrashLoopBackOff](#05-crashloopbackoff) · [06 ImagePullBackOff](#06-imagepullbackoff)
  - [07 Readiness](#07-readiness-probe) · [08 Liveness](#08-liveness-probe) · [09 Startup](#09-startup-probe) · [10 Init container](#10-init-container) · [11 Multi-container](#11-multi-container-pod) · [12 Termination](#12-graceful-termination)
  - [Summary table](#lifecycle-summary)

---

## Setup and a note about my laptop

```bash
kind create cluster --config cluster/kind-hw-a.yaml
kubectl apply -f strategies/client-pod.yaml      # curl client used for all traffic tests
```

My first cluster worked at first, but during the rolling-update test `kube-scheduler` and `kube-controller-manager` kept restarting. Their logs showed why:

```text
$ kubectl logs -n kube-system kube-scheduler-hw-a-control-plane --previous --tail=3
...
E1007 16:40:50.585959       1 server.go:337] "Leaderelection lost"
```

The Docker Desktop VM (8 GB) was almost out of memory. Other containers on the same Docker Desktop were using most of it, and the kernel was OOM-killing processes:

```text
$ docker run --rm --privileged --pid=host alpine:3.20 free -m     # memory of the Docker Desktop VM itself
              total        used        free      shared  buff/cache   available
Mem:           7935        7414          90          36         431         296
```

Under that pressure, etcd writes became slow. The two components could not renew their leader lease in time, so they exited and restarted. A Deployment rollout then hangs while nobody runs the controllers. A single control-plane node has no other candidate to elect anyway, so I recreated the cluster with `--leader-elect=false` for both components (the JSON patch is in `cluster/kind-hw-a.yaml`). After that the rollouts behaved. The API server and etcd were still killed once more by the OOM killer later on. I saw the same strain on the data plane: kube-proxy sometimes took a few seconds to apply Service changes. I point that out below wherever it showed up in the numbers.

I also had to move ingress HTTP from host port 8081 to 30081, because another container already held 8081 (`Bind for 0.0.0.0:8081 failed: port is already allocated`). That matters only for session 12.

---

## Task 1 - Deployment strategies

### 1.1 Rolling update

**Files:** `strategies/01-rolling-update/deployment-v1.yaml`, `deployment-v2.yaml`, `service.yaml`. There are 4 replicas, and the strategy is

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # at most 5 pods during the update
    maxUnavailable: 0  # never fewer than 4 ready pods
```

Both versions have a readiness probe, so a new pod only counts once nginx answers.

**Commands**

```bash
kubectl apply -f strategies/01-rolling-update/deployment-v1.yaml -f strategies/01-rolling-update/service.yaml
kubectl rollout status deployment/app-rolling
# in the background: kubectl get pods -l app=app-rolling -L version -w --output-watch-events
# in the background: 280 curls from the client pod, one every 0.25 s
kubectl apply -f strategies/01-rolling-update/deployment-v2.yaml
kubectl rollout status deployment/app-rolling
kubectl get rs -l app=app-rolling
kubectl rollout undo deployment/app-rolling
```

**Output**

```text
$ kubectl get deploy app-rolling -o 'jsonpath={.spec.strategy}'
{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0},"type":"RollingUpdate"}

$ kubectl apply -f strategies/01-rolling-update/deployment-v2.yaml
deployment.apps/app-rolling configured

$ kubectl rollout status deployment/app-rolling --timeout=180s
Waiting for deployment "app-rolling" rollout to finish: 1 out of 4 new replicas have been updated...
...
Waiting for deployment "app-rolling" rollout to finish: 1 old replicas are pending termination...
deployment "app-rolling" successfully rolled out

$ kubectl get rs -l app=app-rolling
NAME                     DESIRED   CURRENT   READY   AGE
app-rolling-56bff6d88c   4         4         4       30s
app-rolling-86d7d44d5b   0         0         0       39s
```

The pod watch during the update (trimmed to the transitions that matter):

```text
EVENT      NAME                           READY   STATUS              AGE   VERSION
ADDED      app-rolling-86d7d44d5b-2sqmw   1/1     Running             7s    v1      <- 4 x v1 running
...
ADDED      app-rolling-56bff6d88c-mxnn9   0/1     Pending             0s    v2      <- surge: 5th pod
MODIFIED   app-rolling-56bff6d88c-mxnn9   0/1     Running             2s    v2
MODIFIED   app-rolling-56bff6d88c-mxnn9   1/1     Running             7s    v2      <- ready (probe passed)
MODIFIED   app-rolling-86d7d44d5b-pnngt   1/1     Terminating         16s   v1      <- only now one v1 goes
ADDED      app-rolling-56bff6d88c-tkwn6   0/1     Pending             0s    v2
...                                                                                  (same pattern 3 more times)
DELETED    app-rolling-86d7d44d5b-zzg5k   0/1     Completed           40s   v1      <- last v1 gone
```

The ReplicaSet events from `kubectl describe deployment app-rolling` show the same one-for-one steps:

```text
Scaled up replica set app-rolling-56bff6d88c from 0 to 1
Scaled down replica set app-rolling-86d7d44d5b from 4 to 3
Scaled up replica set app-rolling-56bff6d88c from 1 to 2
Scaled down replica set app-rolling-86d7d44d5b from 3 to 2
Scaled up replica set app-rolling-56bff6d88c from 2 to 3
Scaled down replica set app-rolling-86d7d44d5b from 2 to 1
Scaled up replica set app-rolling-56bff6d88c from 3 to 4
Scaled down replica set app-rolling-86d7d44d5b from 1 to 0
```

What the client saw. I used `uniq -c` without sorting, so it groups consecutive identical answers in time order (trimmed in the middle):

```text
  34 VERSION: v1
   1 VERSION: v2
   1 VERSION: v1
   1 VERSION: v2
   3 VERSION: v1
 ...
   2 VERSION: v1
   1 FAILED
   1 VERSION: v1
   3 VERSION: v2
 ...
   2 FAILED
 169 VERSION: v2
# totals:
   4 FAILED
  75 VERSION: v1
 201 VERSION: v2
```

**What I observed.**
- The watch shows exactly what `maxSurge: 1, maxUnavailable: 0` promises. A v2 pod is created first, and a v1 pod is terminated only after that v2 pod becomes `1/1` ready. There were never fewer than 4 ready pods.
- During the update **both versions answer at the same time**. The client flips back and forth between v1 and v2 for about 20 seconds. Any app that does a rolling update has to put up with old and new running side by side.
- 4 of 280 requests **failed**, even with `maxUnavailable: 0`. Each failure happened just as a v1 pod was terminated. When a pod is deleted, the kubelet sends SIGTERM to nginx while kube-proxy is still removing the pod from the Service's iptables rules. For a moment, new connections can still go to a pod that is shutting down.

**Follow-up: fixing the 4 failures with a `preStop` hook.** I copied both YAMLs to `*-prestop.yaml` and added only this:

```yaml
lifecycle:
  preStop:
    exec:
      command: ["sh", "-c", "sleep 5; nginx -s quit; sleep 1"]
```

The pod keeps serving for 5 more seconds after it is marked Terminating, which gives the endpoint removal time to reach kube-proxy. Then nginx shuts down gracefully. I ran the identical experiment again (`outputs/01b-rolling-update-prestop.txt`):

```text
# totals:
  75 VERSION: v1
 205 VERSION: v2
```

0 failures out of 280, compared with 4 out of 280 before. That is one run each, so it is not proof, but it matches what the Kubernetes docs say about graceful shutdown behind a Service.

**Rollback.** `kubectl rollout undo deployment/app-rolling` scaled the old ReplicaSet `86d7d44d5b` back to 4 and the v2 one to 0. Kubernetes kept the old ReplicaSet for exactly this reason. My single `curl` right after `rollout status` still returned `VERSION: v2`. The v2 pods were still terminating, and kube-proxy had not yet caught up: the same lag as above.

### 1.2 Blue-green

**Files:** `strategies/02-blue-green/deployment-blue.yaml` (v1, label `slot: blue`), `deployment-green.yaml` (v2, `slot: green`), `service-blue.yaml` / `service-green.yaml`. The two Service files are the same Service `myapp-service`, and the only difference is the selector. In this strategy the selector is the switch.

**Commands**

```bash
kubectl apply -f strategies/02-blue-green/deployment-blue.yaml -f strategies/02-blue-green/service-blue.yaml
kubectl apply -f strategies/02-blue-green/deployment-green.yaml
kubectl patch service myapp-service -p '{"spec":{"selector":{"app":"myapp","slot":"green"}}}'   # switch
kubectl apply -f strategies/02-blue-green/service-blue.yaml                                    # switch back
kubectl apply -f strategies/02-blue-green/service-green.yaml                                   # promote again
```

**Output**

```text
$ kubectl get deploy,pods -l app=myapp -L slot,version      (pods trimmed)
NAME                        READY   UP-TO-DATE   AVAILABLE   AGE   SLOT    VERSION
deployment.apps/app-blue    3/3     3            3           14s   blue    v1
deployment.apps/app-green   3/3     3            3           7s    green   v2

$ kubectl get svc myapp-service -o wide
NAME            TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE   SELECTOR
myapp-service   NodePort   10.96.126.1   <none>        80:30020/TCP   13s   app=myapp,slot=blue

$ kubectl get endpointslices -l kubernetes.io/service-name=myapp-service
NAME                  ADDRESSTYPE   PORTS   ENDPOINTS                             AGE
myapp-service-mjmhm   IPv4          80      10.244.0.64,10.244.0.65,10.244.0.66   14s

# 10 requests through the Service before the switch:
$ kubectl exec client -- sh -c 'for i in $(seq 1 10); do curl -s -m2 myapp-service | grep -o "[A-Z]* ENVIRONMENT" || echo FAILED; done | sort | uniq -c'
     10 BLUE ENVIRONMENT

# Green can be smoke-tested directly (pod IP) before it gets any user traffic:
$ kubectl exec client -- sh -c 'curl -s 10.244.0.67 | grep -o -E "GREEN ENVIRONMENT|Version: v2"'
GREEN ENVIRONMENT
Version: v2

$ kubectl patch service myapp-service -p '{"spec":{"selector":{"app":"myapp","slot":"green"}}}'
service/myapp-service patched
# requests sent immediately after the patch:
     10 GREEN ENVIRONMENT

$ kubectl describe service myapp-service      (trimmed)
Selector:                 app=myapp,slot=green
Endpoints:                10.244.0.68:80,10.244.0.69:80,10.244.0.67:80

$ kubectl apply -f strategies/02-blue-green/service-blue.yaml      # rollback
# requests sent immediately after the apply:
     10 BLUE ENVIRONMENT

$ kubectl apply -f strategies/02-blue-green/service-green.yaml     # promote again
# requests sent immediately after the apply:
     10 GREEN ENVIRONMENT
```

**What I observed.**
- Both versions run fully side by side, but only one gets traffic. The Service's selector decides which. Changing one label in the selector moved **all** traffic at once: 10/10 BLUE, then 10/10 GREEN.
- Green could be tested by its pod IP **before** the switch, which a rolling update does not allow.
- Rollback is the same one-line change in reverse, and it was instant because the Blue pods were still running. The cost is double the pods during the release. After promotion I scaled Blue to 0 (`kubectl scale deployment app-blue --replicas=0`): that frees the resources, and the Deployment stays around for a later rollback.
- The switch is instant in the API, but each node's kube-proxy still has to reprogram its rules. In this run that took less time than the gap between two of my commands: the requests sent right after each switch already went to the new side. The script also waits until the EndpointSlice lists only the new pods before it tests again, because in the canary test (1.3) I measured kube-proxy lagging behind on this busy node.

### 1.3 Canary

**Files:** `strategies/03-canary/deployment-stable.yaml` (9 replicas, v1, `track: stable`), `deployment-canary.yaml` (1 replica, v2, `track: canary`), `service.yaml`. The Service selects only `app: myapp-canary`, the label both Deployments share, so it load-balances over all 10 pods. The traffic split equals the pod ratio.

**Commands**

```bash
kubectl apply -f strategies/03-canary/deployment-stable.yaml -f strategies/03-canary/service.yaml
kubectl apply -f strategies/03-canary/deployment-canary.yaml
# 100 requests, count answers per version
kubectl exec client -- sh -c 'for i in $(seq 1 100); do ... curl myapp-canary-service ...; done | sort | uniq -c'
kubectl scale deployment app-stable --replicas=5; kubectl scale deployment app-canary --replicas=5   # widen to 50%
kubectl scale deployment app-canary --replicas=0; kubectl scale deployment app-stable --replicas=9   # abort
```

**Output**

```text
$ kubectl get pods -l app=myapp-canary -L track,version      (7 of the 9 stable pods trimmed)
NAME                          READY   STATUS    RESTARTS   AGE   TRACK    VERSION
app-canary-5849994497-td255   1/1     Running   0          7s    canary   v2
app-stable-6ffb777f9d-2hrb7   1/1     Running   0          15s   stable   v1
app-stable-6ffb777f9d-5d6lc   1/1     Running   0          15s   stable   v1

# 100 requests with only stable running:
    100 STABLE v1

### Step 3: ~10% of traffic to the canary - 100 requests through the one Service:
      9 CANARY v2
     91 STABLE v1
# and a second batch of 100, to see how much the split moves around:
     15 CANARY v2
     85 STABLE v1
```

How kube-proxy actually splits the traffic. These are the iptables rules on the node for this Service (10 endpoints, trimmed):

```text
-A KUBE-SVC-FZS5ED5AWZKMK4AC -m comment --comment "default/myapp-canary-service:http -> 10.244.0.152:80" -m statistic --mode random --probability 0.10000000009 -j KUBE-SEP-RYBYQGBHYEJWIQD4
-A KUBE-SVC-FZS5ED5AWZKMK4AC -m comment --comment "default/myapp-canary-service:http -> 10.244.0.153:80" -m statistic --mode random --probability 0.11111111101 -j KUBE-SEP-PBLKFCPXVGHUDZ6D
-A KUBE-SVC-FZS5ED5AWZKMK4AC -m comment --comment "default/myapp-canary-service:http -> 10.244.0.154:80" -m statistic --mode random --probability 0.12500000000 -j KUBE-SEP-DWF5ADWNS5O3LPDG
...
-A KUBE-SVC-FZS5ED5AWZKMK4AC -m comment --comment "default/myapp-canary-service:http -> 10.244.0.160:80" -m statistic --mode random --probability 0.50000000000 -j KUBE-SEP-6OYGISEPVNFY7GOU
-A KUBE-SVC-FZS5ED5AWZKMK4AC -m comment --comment "default/myapp-canary-service:http -> 10.244.0.161:80" -j KUBE-SEP-RUWRIREWJZ5LFZBW
```

Widening to 5:5 also showed the kube-proxy lag:

```text
$ kubectl scale deployment app-stable --replicas=5
$ kubectl scale deployment app-canary --replicas=5
# 100 requests sent immediately after the rollouts finished:
     22 CANARY v2
     78 STABLE v1
$ docker exec hw-a-control-plane iptables -t nat -S KUBE-SVC-FZS5ED5AWZKMK4AC | grep -c KUBE-SEP    # endpoint rules on the node right now
7
# (polled until the node's iptables chain held exactly the 10 ready pod IPs)
     46 CANARY v2
     54 STABLE v1
# second batch of 100:
     49 CANARY v2
     51 STABLE v1
$ docker exec hw-a-control-plane iptables -t nat -L KUBE-SVC-FZS5ED5AWZKMK4AC -v -n | <pkts per endpoint>
   19 pkts  10.244.0.154:80
   15 pkts  10.244.0.156:80
   ...                                 (10 endpoints, 15-26 packets each)

# abort: canary -> 0, stable -> 9
    100 STABLE v1
```

**What I observed.**
- 9:1 pods gave 9/100 and 15/100 canary answers, and 5:5 gave 46/100 and 49/100. The split follows the pod count because kube-proxy picks an endpoint at random with equal weight. The probabilities 1/10, 1/9, 1/8 ... 1/2 in the chain add up to an even split.
- The split is only approximate (random per connection), and its granularity is limited by the replica count. 1% would need 99 stable pods. Fine-grained splits need an Ingress controller or service mesh with weights.
- Right after scaling, the node had only 7 endpoint rules, not 10, and the split was 22/78. Measuring too early gives the wrong ratio, so it is worth checking `iptables`/EndpointSlices first.
- Aborting the canary is just scaling it to 0: the next 100 requests were all stable.

### 1.4 Recreate

**Files:** `strategies/04-recreate/deployment-v1.yaml`, `deployment-v2.yaml` (`strategy: type: Recreate`, 3 replicas), `service.yaml`.

**Commands**

```bash
kubectl apply -f strategies/04-recreate/deployment-v1.yaml -f strategies/04-recreate/service.yaml
# in the background: pod watch + 240 curls, one every 0.25 s
kubectl apply -f strategies/04-recreate/deployment-v2.yaml
kubectl rollout status deployment/app-recreate
```

**Output** - the watch during the update:

```text
EVENT      NAME                            READY   STATUS              RESTARTS   AGE   VERSION
ADDED      app-recreate-6c78cb55bb-56jp8   1/1     Running             0          2s    v1
ADDED      app-recreate-6c78cb55bb-mn85t   1/1     Running             0          2s    v1
ADDED      app-recreate-6c78cb55bb-t45xx   1/1     Running             0          2s    v1
MODIFIED   app-recreate-6c78cb55bb-t45xx   1/1     Terminating         0          5s    v1   <- all three v1
MODIFIED   app-recreate-6c78cb55bb-56jp8   1/1     Terminating         0          5s    v1      terminate together
MODIFIED   app-recreate-6c78cb55bb-mn85t   1/1     Terminating         0          5s    v1
...
MODIFIED   app-recreate-6c78cb55bb-mn85t   0/1     Completed           0          5s    v1
MODIFIED   app-recreate-6c78cb55bb-56jp8   0/1     Completed           0          5s    v1
MODIFIED   app-recreate-6c78cb55bb-t45xx   0/1     Completed           0          5s    v1   <- all stopped
ADDED      app-recreate-7bd8d89b8b-7f5fk   0/1     Pending             0          0s    v2   <- only now v2
ADDED      app-recreate-7bd8d89b8b-plvgc   0/1     Pending             0          0s    v2
ADDED      app-recreate-7bd8d89b8b-fgcfs   0/1     Pending             0          0s    v2
...
MODIFIED   app-recreate-7bd8d89b8b-7f5fk   1/1     Running             0          1s    v2
```

```text
Events (kubectl describe deployment app-recreate):
  Normal  ScalingReplicaSet  67s   deployment-controller  Scaled up replica set app-recreate-6c78cb55bb from 0 to 3
  Normal  ScalingReplicaSet  62s   deployment-controller  Scaled down replica set app-recreate-6c78cb55bb from 3 to 0
  Normal  ScalingReplicaSet  62s   deployment-controller  Scaled up replica set app-recreate-7bd8d89b8b from 0 to 3

$ kubectl exec client -- sh -c '<240 requests, one every 0.25s>' | uniq -c
  13 VERSION: v1
   3 FAILED (no answer)
 224 VERSION: v2
```

**What I observed.**
- The old ReplicaSet went from 3 to 0 in one step. The v2 pods were only created **after** all three v1 containers had stopped (`Completed`), not when the old pods were deleted from the API. That ordering is the whole point of Recreate.
- Unlike the rolling update, there is no mixing: v1 then a gap, then only v2. The gap was **3 failed requests, about 1 second**, because the image was already cached and nginx starts fast. With a slow-starting app or an image pull, the gap would be much longer.
- The instructor's Recreate YAMLs have no readiness probe. My single test `curl` right after the v1 rollout got no `VERSION` line back, most likely because kube-proxy had not programmed the new Service yet. The loop a few seconds later answered normally.
- Recreate fits when two versions must never run together (e.g. an incompatible DB schema, a single-writer app or a RWO volume) and a short outage is acceptable.

### Comparison

| | Rolling update | Blue-green | Canary | Recreate |
|---|---|---|---|---|
| Built into Deployment? | yes (default) | no - 2 Deployments + Service selector | no - 2 Deployments, 1 Service | yes (`type: Recreate`) |
| Downtime in my test | 4/280 failed (0/280 with preStop) | none | none | 3/240 failed (~1 s) |
| Old + new at the same time? | yes, mixed for ~20 s | both running, only one gets traffic | yes, on purpose (by ratio) | never |
| Rollback | `rollout undo` (re-rolls) | flip selector back (instant) | scale canary to 0 | redeploy old (downtime again) |
| Extra resources | +1 pod (maxSurge) | 2x pods during release | +canary pods | none |
| Traffic control | none | all-or-nothing | approx. by replica ratio | n/a |

---

## Task 2 - Pod lifecycle

For each YAML in `pod-lifecycle/` I ran: `kubectl apply -f`, a background `kubectl get pods --field-selector metadata.name=<pod> -w --output-watch-events` from the moment of the apply, `kubectl get pod`, `kubectl describe pod`, and `kubectl logs` where useful. Each transcript is in `outputs/lifecycle-NN-*.txt`.

### 01 Running

```text
EVENT      NAME                READY   STATUS              RESTARTS   AGE
ADDED      lifecycle-running   0/1     Pending             0          0s
MODIFIED   lifecycle-running   0/1     ContainerCreating   0          0s
MODIFIED   lifecycle-running   1/1     Running             0          1s

$ kubectl get pod lifecycle-running -o 'jsonpath={.status.phase}{"  "}{.status.conditions[*].type}{"\n"}'
Running  PodReadyToStartContainers Initialized Ready ContainersReady PodScheduled
```

**Observed:** Pending (scheduled, waiting for the sandbox) -> ContainerCreating -> Running in about 1 second, because `nginx:1.27` was already on the node. All five pod conditions are True. With no readiness probe, Ready becomes True as soon as the container starts.

### 02 Pending

```text
$ kubectl get node -o custom-columns=NODE:.metadata.name,ALLOCATABLE-CPU:.status.allocatable.cpu,ALLOCATABLE-MEM:.status.allocatable.memory
NODE                 ALLOCATABLE-CPU   ALLOCATABLE-MEM
hw-a-control-plane   15                8125796Ki

$ kubectl get pod lifecycle-pending -o wide
NAME                READY   STATUS    RESTARTS   AGE   IP       NODE     NOMINATED NODE   READINESS GATES
lifecycle-pending   0/1     Pending   0          15s   <none>   <none>   <none>           <none>

Events:
  Warning  FailedScheduling  15s  default-scheduler  0/1 nodes are available: 1 Insufficient memory. preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.
```

**Observed:** the pod requests `memory: 9Gi`, and my only node has about 7.75 GiB allocatable. The scheduler never finds a node, so the pod has no IP and no node and stays Pending forever. `describe` gives the exact reason. Pending is a scheduling problem: the kubelet never even sees this pod.

### 03 Succeeded

```text
MODIFIED   lifecycle-succeeded   1/1     Running     0          1s
MODIFIED   lifecycle-succeeded   0/1     Completed   0          7s

$ kubectl logs lifecycle-succeeded
Task started
Task completed successfully

$ kubectl get pod lifecycle-succeeded -o 'jsonpath={.status.containerStatuses[0].state}{"\n"}'
{"terminated":{"containerID":"containerd://3285...","exitCode":0,"finishedAt":"2026-10-07T17:17:32Z","reason":"Completed","startedAt":"2026-10-07T17:17:27Z"}}
```

**Observed:** `restartPolicy: Never` plus exit code 0 gives phase **Succeeded** (`kubectl get` shows the reason `Completed`). The container ran for 5 s (`sleep 5`). The pod object stays, so logs can still be read. This is how Job pods end.

### 04 Failed

```text
MODIFIED   lifecycle-failed   1/1     Running   0          1s
MODIFIED   lifecycle-failed   0/1     Error     0          7s

$ kubectl logs lifecycle-failed
Task started
Task failed

    State:          Terminated
      Reason:       Error
      Exit Code:    1
    Restart Count:  0
```

**Observed:** same as 03 but `exit 1`. With `restartPolicy: Never` the kubelet does not restart it, so the phase is **Failed** and the status shows `Error` with exit code 1.

### 05 CrashLoopBackOff

```text
MODIFIED   lifecycle-crashloop   1/1     Running             0             1s
MODIFIED   lifecycle-crashloop   0/1     Error               0             5s
MODIFIED   lifecycle-crashloop   1/1     Running             1 (1s ago)    5s
MODIFIED   lifecycle-crashloop   0/1     Error               1 (5s ago)    9s
MODIFIED   lifecycle-crashloop   0/1     CrashLoopBackOff    1 (12s ago)   20s
MODIFIED   lifecycle-crashloop   1/1     Running             2 (12s ago)   20s
MODIFIED   lifecycle-crashloop   0/1     Error               2 (16s ago)   24s
MODIFIED   lifecycle-crashloop   0/1     CrashLoopBackOff    2 (25s ago)   48s
MODIFIED   lifecycle-crashloop   1/1     Running             3 (25s ago)   48s

  Warning  BackOff    24s (x3 over 66s)  kubelet  ... Back-off restarting failed container crashing-app ...

$ kubectl logs lifecycle-crashloop --previous
Application started
Application crashed
```

**Observed:** the default `restartPolicy: Always` restarts the container every time it exits with 1. The kubelet waits longer each time: the first restart came immediately, then about 10 s, then about 20 s in `CrashLoopBackOff` (the delay doubles up to 5 minutes). CrashLoopBackOff is not a phase. The phase stays `Running`; it is the waiting reason between restarts. `logs --previous` shows the output of the crashed run, which is where the real error usually is.

### 06 ImagePullBackOff

```text
MODIFIED   lifecycle-image-error   0/1     ContainerCreating   0          1s
MODIFIED   lifecycle-image-error   0/1     ErrImagePull        0          4s
MODIFIED   lifecycle-image-error   0/1     ImagePullBackOff    0          16s
MODIFIED   lifecycle-image-error   0/1     ErrImagePull        0          32s

  Warning  Failed     22s (x2 over 37s)  kubelet  ... Failed to pull image "jakwehrgkaejw:kahsdfgkhj": ... pull access denied, repository does not exist or may require authorization ...
  Normal   BackOff    8s (x2 over 36s)   kubelet  ... Back-off pulling image "jakwehrgkaejw:kahsdfgkhj"
```

**Observed:** the pod is scheduled, but the kubelet cannot pull the image. A name with no registry means `docker.io/library/...`, and that repository does not exist. It alternates between `ErrImagePull` (a pull just failed) and `ImagePullBackOff` (waiting before the next try, with growing delays). The phase stays Pending because no container has ever started. The event message tells a typo from a missing tag from a private repo.

### 07 Readiness probe

```text
$ kubectl get pod lifecycle-readiness      (polled every 2.5 s)
lifecycle-readiness   0/1     Running   0          3s
lifecycle-readiness   0/1     Running   0          5s
lifecycle-readiness   1/1     Running   0          8s

$ kubectl get pod lifecycle-readiness -o 'jsonpath={range .status.conditions[*]}{.type}={.status} at {.lastTransitionTime}{"\n"}{end}'
PodReadyToStartContainers=True at 2026-10-07T17:18:48Z
Initialized=True at 2026-10-07T17:18:47Z
Ready=True at 2026-10-07T17:18:54Z
ContainersReady=True at 2026-10-07T17:18:54Z
PodScheduled=True at 2026-10-07T17:18:47Z

    Readiness:      http-get http://:80/ delay=5s timeout=1s period=5s #success=1 #failure=3
```

**Observed:** the container was `Running` but `0/1` for about 6 seconds. The probe waits `initialDelaySeconds: 5` and then does its first HTTP GET. `Ready` turned True 7 s after scheduling. Until then, a Service would not send this pod any traffic. A failing readiness probe never restarts a container; it only removes the pod from Service endpoints.

### 08 Liveness probe

```text
MODIFIED   lifecycle-liveness   1/1     Running   0            1s
MODIFIED   lifecycle-liveness   1/1     Running   1 (0s ago)   61s

  Warning  Unhealthy  30s (x2 over 35s)  kubelet  spec.containers{app}: Liveness probe failed:
  Normal   Killing    30s                kubelet  spec.containers{app}: Container app failed liveness probe, will be restarted

    Last State:     Terminated
      Reason:       Error
      Exit Code:    137
      Started:      Wed, 07 Oct 2026 22:48:48 +0530
      Finished:     Wed, 07 Oct 2026 22:49:48 +0530
    Restart Count:  1
    Liveness:       exec [sh -c test -f /tmp/healthy] delay=5s timeout=1s period=5s #success=1 #failure=2

$ kubectl logs lifecycle-liveness --previous
App started
Health file removed
```

**Observed:** the app deletes `/tmp/healthy` after 20 s. The probe failed twice (`failureThreshold: 2`, 5 s apart), and at about 30 s the kubelet decided to restart the container. But the restart only showed at **61 s**, and the exit code is **137** (SIGKILL). The container's PID 1 is `sh`, which ignores SIGTERM, so the kubelet waited the full default `terminationGracePeriodSeconds` (30 s) and then killed it. Started 22:48:48 and finished 22:49:48 is exactly 30 s of probing plus 30 s of grace. Liveness probes restart a hung app, but the restart is only as quick as the app's shutdown.

### 09 Startup probe

```text
$ kubectl get pod lifecycle-startup              (at 15 s)
lifecycle-startup   0/1     Running   0          15s
$ ... jsonpath=started={...started} ready={...ready}
started=false ready=false

  Warning  Unhealthy  5s (x6 over 30s)  kubelet  spec.containers{slow-app}: Startup probe failed:

$ kubectl get pod lifecycle-startup              (after wait)
lifecycle-startup   1/1     Running   0          36s
started=true ready=true restarts=0
    Startup:        exec [sh -c test -f /tmp/started] delay=0s timeout=1s period=5s #success=1 #failure=10
```

**Observed:** the app needs 30 s before it creates `/tmp/started`. The startup probe failed 6 times, and that is fine: it is allowed `10 x 5 s = 50 s`. At 36 s it passed, `started` became true, and the pod became Ready, with **0 restarts**. Without the startup probe, a liveness probe tuned for a running app would have killed this slow starter. With it, the other probes wait until startup is done.

### 10 Init container

```text
MODIFIED   lifecycle-init   0/1     Init:0/1          0          0s
MODIFIED   lifecycle-init   0/1     PodInitializing   0          12s
MODIFIED   lifecycle-init   1/1     Running           0          12s

Init Containers:
  setup:
    State:          Terminated
      Reason:       Completed
      Exit Code:    0
      Started:      Wed, 07 Oct 2026 22:48:48 +0530
      Finished:     Wed, 07 Oct 2026 22:48:58 +0530

$ kubectl logs lifecycle-init -c setup
Init container running
Init complete
```

**Observed:** `Init:0/1` means 0 of 1 init containers have finished. The `setup` container ran for 10 s, exited 0, and only then did the `nginx` app container start (`PodInitializing` -> `Running`). If an init container fails, the app container never starts. That makes init containers good for "wait for DB", migrations or fetching config.

### 11 Multi-container pod

```text
MODIFIED   lifecycle-multi-container   0/2     ContainerCreating   0          1s
MODIFIED   lifecycle-multi-container   2/2     Running             0          1s

$ kubectl get pod lifecycle-multi-container -o 'jsonpath={range .spec.containers[*]}{.name}{"\t"}{.image}{"\n"}{end}'
app	nginx:1.27
sidecar	busybox:1.36

$ kubectl logs lifecycle-multi-container -c sidecar
Sidecar is running
Sidecar is running

$ kubectl exec lifecycle-multi-container -c sidecar -- wget -qO- localhost:80
<!DOCTYPE html>
<html>
...
```

**Observed:** `READY 2/2` counts containers. Each container has its own logs (`-c`). The sidecar reached nginx on `localhost:80` because all containers in a pod share one network namespace (same IP, same ports), so two containers in one pod cannot both listen on port 80.

### 12 Graceful termination

```text
$ time kubectl delete pod lifecycle-termination
pod "lifecycle-termination" deleted from default namespace
# kubectl delete returned after 12 s

MODIFIED   lifecycle-termination   1/1     Terminating   0          2s
MODIFIED   lifecycle-termination   0/1     Completed     0          13s
DELETED    lifecycle-termination   0/1     Completed     0          14s

$ kubectl logs -f lifecycle-termination    # followed in the background while the pod was being deleted
Application running
SIGTERM received; cleaning up...
Cleanup complete

  Normal   Killing    12s   kubelet   Stopping container graceful-app
```

**Observed:** on delete, the kubelet sends **SIGTERM**. The script's `trap` caught it (within 2 s, once the current `sleep 2` returned), cleaned up for 10 s and exited 0 (`Completed`). That fits inside `terminationGracePeriodSeconds: 20`, so no SIGKILL was needed and `kubectl delete` returned after 12 s. Compare with 08, where `sh` without a trap ignored SIGTERM and got SIGKILL (exit 137) after the full grace period.

### Lifecycle summary

| YAML | Phase | STATUS column | Restarts | Key thing to check |
|---|---|---|---|---|
| 01-running | Running | Running | 0 | conditions all True |
| 02-pending | Pending | Pending | 0 | `FailedScheduling: Insufficient memory` |
| 03-succeeded | Succeeded | Completed | 0 | exit code 0, `restartPolicy: Never` |
| 04-failed | Failed | Error | 0 | exit code 1 |
| 05-crashloopbackoff | Running | Error / CrashLoopBackOff | 3 in 75 s | `logs --previous`, back-off events |
| 06-imagepullbackoff | Pending | ErrImagePull / ImagePullBackOff | 0 | pull error message in events |
| 07-readiness | Running | 0/1 then 1/1 | 0 | `Ready` condition time |
| 08-liveness | Running | Running | 1 | `Liveness probe failed`, exit 137 |
| 09-startup | Running | 0/1 for 36 s then 1/1 | 0 | `Startup probe failed` x6 is fine |
| 10-init-container | Pending -> Running | Init:0/1 -> PodInitializing | 0 | `logs -c setup` |
| 11-multi-container | Running | 2/2 | 0 | `logs -c sidecar`, shared localhost |
| 12-termination | Running -> deleted | Terminating -> Completed | 0 | SIGTERM trap, grace period |
