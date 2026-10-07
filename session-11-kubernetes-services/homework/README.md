# Kubernetes Networking & Services - Homework

**Name:** Rudhar Bajaj
**Environment:** macOS 26.5.2 (Apple Silicon), Docker Desktop (Engine 29.6.1), kind v0.33.0 single-node cluster `hw-a` (Kubernetes v1.37.0, kube-proxy in iptables mode, CoreDNS 1.14.6), MetalLB v0.16.1, kubectl v1.36.1

Every output block below is real output from commands I ran on 2026-10-07. Full untrimmed transcripts are in `outputs/`. Where I shortened a listing I say so.

The cluster is the same `hw-a` kind cluster as in session 10 (config: `../../session10-k8s-core-objects/homework/cluster/kind-hw-a.yaml`). It publishes NodePort 30080 on my Mac's `localhost:30080`.

| File | Contents |
|---|---|
| `outputs/01-clusterip.txt` | ClusterIP: deploy, verify, short name / FQDN / IP, per-pod request count, iptables rule |
| `outputs/02-nodeport.txt` | NodePort 30080: from a pod, from the docker `kind` network, from my Mac |
| `outputs/03-loadbalancer.txt` | LoadBalancer: `<pending>` without a provider, MetalLB install, EXTERNAL-IP, tests from 3 places |
| `outputs/04-externalname.txt` | ExternalName: CNAME answers, a dead target, two working targets, no kube-proxy rules |
| `outputs/05-headless.txt` | Headless + StatefulSet: DNS returns pod IPs, per-pod names, name survives a restart |
| `outputs/06a-deployment-vs-replicaset.txt` | ownerReferences chain, self-healing, scaling, new RS per rollout, bare RS has no rollout |
| `outputs/06b-daemonset-statefulset.txt` | DaemonSet vs StatefulSet with per-pod PVCs |
| `outputs/06c-replicaset-vs-service.txt` | EndpointSlice YAML, pod IP changes but Service doesn't, iptables chain, Service with no endpoints |
| `outputs/07-fqdn.txt` | FQDN / cross-namespace DNS (used by `fqdn/README.md`) |
| `outputs/08-coredns.txt` | CoreDNS deployment, Corefile, query logging (used by `coredns/README.md`) |
| `outputs/09-coredns-troubleshooting.txt` | DNS outage drill (used by `coredns/README.md`) |

Other deliverables: [`fqdn/README.md`](fqdn/README.md), [`coredns/README.md`](coredns/README.md).

YAML: `services/01-clusterip` ... `services/05-headless` are copies of the instructor's folders. They are already multi-arch (`nginx:1.25-alpine`, `curlimages/curl`), so I used them as they are. I added `services/03-loadbalancer/metallb-pool.yaml`, `services/04-externalname/service-extra.yaml`, `dns-debug-pod.yaml` (a pod with `dig`/`nslookup`), `workloads/statefulset-with-storage.yaml` and `fqdn/team-b.yaml`.

## Contents

- [Task 1 - The five Service types](#task-1---the-five-service-types)
  - [1. ClusterIP](#1-clusterip) · [2. NodePort](#2-nodeport) · [3. LoadBalancer](#3-loadbalancer) · [4. ExternalName](#4-externalname) · [5. Headless](#5-headless)
  - [Summary](#service-types-summary)
- [Task 2 - Comparisons](#task-2---comparisons)
  - [Deployment vs ReplicaSet](#deployment-vs-replicaset)
  - [Deployment vs DaemonSet vs StatefulSet](#deployment-vs-daemonset-vs-statefulset)
  - [ReplicaSet vs Service](#replicaset-vs-service)
- [Task 3 - FQDN](fqdn/README.md)
- [Task 4 - CoreDNS](coredns/README.md)

---

## Task 1 - The five Service types

All tests from "inside the cluster" use the instructor's `curl-client` pod (`curlimages/curl:8.5.0`). My kind node is at `172.18.0.3` on the docker network `kind`.

A note on timing. On this busy laptop, kube-proxy sometimes needed one or two seconds to write the iptables rules for a new Service (measured in session 10, canary test). So after each rollout my script polled the Service from the client pod until it answered, and only then ran the tests. The poll is printed in the transcripts, e.g. `# (polled until http://web-service-nodeport:80 answered 200 from the client pod - about 2s ...)`.

### 1. ClusterIP

**YAML:** `services/01-clusterip/` - Deployment `web-app-clusterip` (3 x nginx), Service `web-service-clusterip` (`type: ClusterIP`, `port: 8080` -> `targetPort: 80`), pod `curl-client`.

```bash
kubectl apply -f services/01-clusterip/
kubectl get svc web-service-clusterip -o wide
kubectl get endpointslices -l kubernetes.io/service-name=web-service-clusterip -o wide
kubectl exec curl-client -- curl -s http://web-service-clusterip:8080
```

```text
$ kubectl get svc web-service-clusterip -o wide
NAME                    TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE   SELECTOR
web-service-clusterip   ClusterIP   10.96.96.222   <none>        8080/TCP   3s    app=web-clusterip

$ kubectl describe svc web-service-clusterip      (trimmed)
Selector:                 app=web-clusterip
Type:                     ClusterIP
IP:                       10.96.96.222
Port:                     http  8080/TCP
TargetPort:               80/TCP
Endpoints:                10.244.0.206:80,10.244.0.207:80,10.244.0.208:80

$ kubectl exec curl-client -- curl -s -o /dev/null -w 'short name -> HTTP %{http_code} from %{remote_ip}:%{remote_port}\n' http://web-service-clusterip:8080
short name -> HTTP 200 from 10.96.96.222:8080
$ ... http://web-service-clusterip.default.svc.cluster.local:8080
FQDN       -> HTTP 200 from 10.96.96.222:8080
$ ... http://10.96.96.222:8080
ClusterIP  -> HTTP 200 from 10.96.96.222:8080

$ kubectl exec curl-client -- sh -c 'for i in $(seq 1 30); do curl -s -o /dev/null http://web-service-clusterip:8080/lb-test; done; echo sent 30'
sent 30
$ for p in $(kubectl get pods -l app=web-clusterip -o name); do echo "$p $(kubectl logs $p | grep -c "GET /lb-test HTTP/1.1\" 404")"; done
pod/web-app-clusterip-66865d4855-2w84d 10
pod/web-app-clusterip-66865d4855-fb4sc 11
pod/web-app-clusterip-66865d4855-j24pn 9

$ docker exec hw-a-control-plane iptables -t nat -S KUBE-SERVICES | grep web-service-clusterip
-A KUBE-SERVICES -d 10.96.96.222/32 -p tcp -m comment --comment "default/web-service-clusterip:http cluster IP" -m tcp --dport 8080 -j KUBE-SVC-TIXQXGX7DUC52XEM

$ curl -s -m 3 -o /dev/null -w '%{http_code}\n' http://10.96.96.222:8080        # from my Mac
000
```

**What I observed.** The Service got a virtual IP (`10.96.96.222`) and the DNS name `web-service-clusterip`. Port 8080 on the Service maps to port 80 in the pods. 30 requests were spread 10 / 11 / 9 over the three pods: I counted each pod's own nginx access log, so this is the real distribution. No process listens on the ClusterIP; it exists only as an iptables rule that kube-proxy wrote on the node. That is also why it is reachable only from inside the cluster: my Mac gets no answer.

### 2. NodePort

**YAML:** `services/02-nodeport/` - Deployment `web-app-nodeport` (2 x nginx), Service `web-service-nodeport` (`type: NodePort`, `nodePort: 30080`).

```text
$ kubectl get svc web-service-nodeport -o wide
NAME                   TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE   SELECTOR
web-service-nodeport   NodePort   10.96.81.176   <none>        80:30080/TCP   4s    app=web-nodeport

$ kubectl get nodes -o wide      (trimmed)
NAME                 STATUS   ROLES           AGE   VERSION   INTERNAL-IP
hw-a-control-plane   Ready    control-plane   36m   v1.37.0   172.18.0.3

### Test 1: from inside the cluster
$ kubectl exec curl-client -- curl -s -o /dev/null -w 'node 172.18.0.3:30080 -> HTTP %{http_code}\n' http://172.18.0.3:30080
node 172.18.0.3:30080 -> HTTP 200
$ kubectl exec curl-client -- curl -s -o /dev/null -w 'svc name:80     -> HTTP %{http_code}\n' http://web-service-nodeport:80
svc name:80     -> HTTP 200

### Test 2: from a container on the docker 'kind' network (like another machine on the LAN)
$ docker run --rm --network kind curlimages/curl:8.5.0 -s -o /dev/null -w 'kind network -> 172.18.0.3:30080 -> HTTP %{http_code}\n' http://172.18.0.3:30080
kind network -> 172.18.0.3:30080 -> HTTP 200

### Test 3: from my Mac - works because the kind config maps host 30080 -> node 30080
$ docker port hw-a-control-plane 30080/tcp
0.0.0.0:30080
$ curl -s -o /dev/null -w 'localhost:30080 -> HTTP %{http_code}\n' http://localhost:30080
localhost:30080 -> HTTP 200
$ sh -c 'curl -s http://localhost:30080 | grep -o "<title>.*</title>"'
<title>Welcome to nginx!</title>

$ docker exec hw-a-control-plane iptables -t nat -S KUBE-NODEPORTS | grep web-service-nodeport
-A KUBE-NODEPORTS -d 127.0.0.0/8 -p tcp ... --dport 30080 ... -j KUBE-EXT-542ZUKRJYISRKQCS
-A KUBE-NODEPORTS -p tcp -m comment --comment "default/web-service-nodeport:http" -m tcp --dport 30080 -j KUBE-EXT-542ZUKRJYISRKQCS
```

**What I observed.** A NodePort Service is a ClusterIP Service plus one port (30000-32767) opened on **every** node. The `PORT(S)` column `80:30080` shows both, and the Service still works by name inside the cluster. Anything that can reach a node IP can reach the app, so on a real network that is the way in from outside. My Mac cannot route to `172.18.0.3` (it lives inside Docker Desktop's VM), so I had added `extraPortMappings` for 30080 when I created the cluster. With that, `localhost:30080` in my browser reaches the NodePort.

### 3. LoadBalancer

**YAML:** `services/03-loadbalancer/` - Deployment `web-app-loadbalancer` (3 x nginx), Service `web-service-loadbalancer` (`type: LoadBalancer`), plus my `metallb-pool.yaml`.

On a cloud, the cloud-controller-manager would create a real load balancer. kind has none, so first I show what happens without one:

```text
$ kubectl get svc web-service-loadbalancer
NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
web-service-loadbalancer   LoadBalancer   10.96.148.250   <pending>     80:30737/TCP   14s
```

To provide the load balancer I chose **MetalLB** over `cloud-provider-kind`. cloud-provider-kind runs outside the cluster and serves **every** kind cluster on the Docker host, and other kind clusters were running on my Docker Desktop at the same time. MetalLB runs inside my cluster and only handles my cluster's Services. I gave it a small address range on the `kind` docker network (`172.18.0.0/16`), far away from the node addresses Docker hands out (`172.18.0.x`).

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.16.1/config/manifests/metallb-native.yaml
kubectl wait -n metallb-system --for=condition=Ready pod --all --timeout=240s
kubectl apply -f services/03-loadbalancer/metallb-pool.yaml      # IPAddressPool 172.18.203.200-210 + L2Advertisement
```

```text
$ kubectl get pods -n metallb-system -o wide      (trimmed)
NAME                          READY   STATUS    RESTARTS   AGE   IP             NODE
controller-76f4cf76b7-zfsds   1/1     Running   0          90s   10.244.0.212   hw-a-control-plane
speaker-z8nkm                 1/1     Running   0          90s   172.18.0.3     hw-a-control-plane

$ kubectl get svc web-service-loadbalancer -o wide
NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE    SELECTOR
web-service-loadbalancer   LoadBalancer   10.96.148.250   172.18.203.200   80:30737/TCP   113s   app=web-loadbalancer

$ kubectl get events --field-selector involvedObject.name=web-service-loadbalancer --sort-by=.lastTimestamp
LAST SEEN   TYPE     REASON         OBJECT                             MESSAGE
11s         Normal   IPAllocated    service/web-service-loadbalancer   Assigned IP ["172.18.203.200"]
10s         Normal   nodeAssigned   service/web-service-loadbalancer   announcing from node "hw-a-control-plane" with protocol "layer2"

# a) from a container on the docker 'kind' network:
$ docker run --rm --network kind curlimages/curl:8.5.0 -s -o /dev/null -w 'kind network -> http://172.18.203.200 -> HTTP %{http_code}\n' http://172.18.203.200
kind network -> http://172.18.203.200 -> HTTP 200
$ docker run --rm --network kind --entrypoint sh curlimages/curl:8.5.0 -c "curl -s http://172.18.203.200 | grep -o '<title>.*</title>'"
<title>Welcome to nginx!</title>

# b) from a pod inside the cluster:
$ kubectl exec curl-client -- curl -s -o /dev/null -w 'pod -> http://172.18.203.200 -> HTTP %{http_code}\n' http://172.18.203.200
pod -> http://172.18.203.200 -> HTTP 200

# c) from my Mac directly:
$ curl -s -m 5 -o /dev/null -w 'mac -> http://172.18.203.200 -> HTTP %{http_code}\n' http://172.18.203.200
mac -> http://172.18.203.200 -> HTTP 000
```

**What I observed.**
- Before MetalLB the Service already had a ClusterIP **and** a NodePort (30737). A LoadBalancer Service is built on top of a NodePort Service, and the provider only adds the external IP in front.
- MetalLB's controller allocated `172.18.203.200` from my pool. Its `speaker` (a DaemonSet on the host network) then answered ARP for that IP on the node's interface: `announcing ... with protocol "layer2"`. On a real LAN this is how traffic reaches the node.
- The IP worked from another container on the `kind` network and from a pod. It did **not** work from my Mac, because Docker Desktop on macOS runs containers in a Linux VM and does not route the `172.18.0.0/16` bridge to the host. On a Linux machine the same test would work from the host. On a cloud the external IP would be public.
- Later, in session 12, the ingress-nginx controller's own `LoadBalancer` Service got the same address from this pool after I had deleted this Service.

### 4. ExternalName

**YAML:** `services/04-externalname/service.yaml` (`externalName: nencyravaliya.me`), `client-pod.yaml`, and my `service-extra.yaml`.

```text
$ kubectl get svc external-database-service -o wide
NAME                        TYPE           CLUSTER-IP   EXTERNAL-IP        PORT(S)   AGE   SELECTOR
external-database-service   ExternalName   <none>       nencyravaliya.me   <none>    4m25s   <none>

$ kubectl exec dnsutils -- dig +noall +answer external-database-service.default.svc.cluster.local
external-database-service.default.svc.cluster.local. 30	IN CNAME nencyravaliya.me.

$ kubectl exec dnsutils -- dig nencyravaliya.me      (trimmed)
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, ...
```

The instructor's target domain no longer resolves (`NXDOMAIN`). Kubernetes never checks `externalName`, so the Service was created without complaint and serves a CNAME that leads nowhere. So I added two working ExternalName Services:

```text
$ kubectl get svc external-web backend-alias
NAME            TYPE           CLUSTER-IP   EXTERNAL-IP                                       PORT(S)   AGE
external-web    ExternalName   <none>       example.com                                       <none>    4s
backend-alias   ExternalName   <none>       web-service-clusterip.default.svc.cluster.local   <none>    4s

$ kubectl exec dnsutils -- dig +noall +answer external-web.default.svc.cluster.local
external-web.default.svc.cluster.local.	30 IN CNAME example.com.
example.com.		30	IN	A	104.20.23.154
example.com.		30	IN	A	172.66.147.243

$ kubectl exec dns-test-client -- curl -s -m 10 -o /dev/null -w 'http://external-web -> HTTP %{http_code} from %{remote_ip}\n' http://external-web
http://external-web -> HTTP 403 from 104.20.23.154
$ kubectl exec dns-test-client -- curl ... -H 'Host: example.com' http://external-web
http://external-web with Host: example.com -> HTTP 200 from 104.20.23.154

$ kubectl exec dnsutils -- dig +noall +answer backend-alias.default.svc.cluster.local
backend-alias.default.svc.cluster.local. 30 IN CNAME web-service-clusterip.default.svc.cluster.local.
web-service-clusterip.default.svc.cluster.local. 30 IN A 10.96.96.222
$ kubectl exec curl-client -- curl -s -o /dev/null -w 'http://backend-alias:8080 -> HTTP %{http_code} from %{remote_ip}\n' http://backend-alias:8080
http://backend-alias:8080 -> HTTP 200 from 10.96.96.222

$ docker exec hw-a-control-plane iptables-save -t nat | grep -c -E 'external-database-service|external-web|backend-alias'
0
```

**What I observed.** An ExternalName Service has no selector, no pods, no ClusterIP and no kube-proxy rules (0 matching iptables lines). It is purely a DNS entry: CoreDNS answers with a CNAME. It gives apps a stable in-cluster name for something outside, so the target can change without touching the app. One catch I hit: HTTP still sends `Host: external-web`, and the CDN in front of example.com refused that with 403. It answered 200 only with the right Host header. ExternalName suits databases and APIs that don't check the host name, or in-cluster aliases like `backend-alias`.

### 5. Headless

**YAML:** `services/05-headless/` - StatefulSet `web-stateful` (3 x nginx, `serviceName: web-service-headless`), Service `web-service-headless` with `clusterIP: None`, client pod.

```text
$ kubectl get svc web-service-headless -o wide
NAME                   TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE   SELECTOR
web-service-headless   ClusterIP   None         <none>        80/TCP    7s    app=web-headless

$ kubectl exec dnsutils -- dig +noall +answer web-service-headless.default.svc.cluster.local
web-service-headless.default.svc.cluster.local.	30 IN A	10.244.0.218
web-service-headless.default.svc.cluster.local.	30 IN A	10.244.0.215
web-service-headless.default.svc.cluster.local.	30 IN A	10.244.0.217

# compare with a normal ClusterIP Service, which returns one virtual IP:
$ kubectl exec dnsutils -- dig +noall +answer web-service-clusterip.default.svc.cluster.local
web-service-clusterip.default.svc.cluster.local. 30 IN A 10.96.96.222

$ kubectl exec headless-dns-client -- nslookup web-stateful-0.web-service-headless.default.svc.cluster.local
Name:	web-stateful-0.web-service-headless.default.svc.cluster.local
Address: 10.244.0.215

$ kubectl exec headless-dns-client -- sh -c 'for i in 0 1 2; do curl -s -o /dev/null -w "web-stateful-$i.web-service-headless -> HTTP %{http_code} from %{remote_ip}\n" http://web-stateful-$i.web-service-headless; done'
web-stateful-0.web-service-headless -> HTTP 200 from 10.244.0.215
web-stateful-1.web-service-headless -> HTTP 200 from 10.244.0.217
web-stateful-2.web-service-headless -> HTTP 200 from 10.244.0.218

### Stable name survives a pod restart (IP changes, name does not)
$ kubectl get pod web-stateful-1 -o 'jsonpath={.status.podIP}{"\n"}'
10.244.0.217
$ kubectl delete pod web-stateful-1
$ kubectl get pod web-stateful-1 -o 'jsonpath={.status.podIP}{"\n"}'
10.244.0.219
$ kubectl exec dnsutils -- dig +short web-stateful-1.web-service-headless.default.svc.cluster.local
10.244.0.219
```

**What I observed.** `clusterIP: None` means there is no virtual IP and no kube-proxy load balancing. DNS returns **all pod IPs** directly, and the client chooses. Combined with a StatefulSet, every pod gets its own stable DNS name `<pod>.<service>`. When `web-stateful-1` was recreated it got a new IP (`.217` -> `.219`), but the same name, and DNS followed it. That is what databases and clustered apps need, for example "connect to the primary `db-0`" or "peer list = db-0, db-1, db-2".

### Service types summary

| Type | Gets a ClusterIP? | Reachable from | kube-proxy rules? | My test result |
|---|---|---|---|---|
| ClusterIP | yes | inside the cluster only | yes | pods: 200, Mac: no answer |
| NodePort | yes + port 30000-32767 on every node | anything that reaches a node IP | yes | pod, kind network, Mac (via port mapping): 200 |
| LoadBalancer | yes + NodePort + external IP from a provider | the external IP | yes | `<pending>` without a provider; 172.18.203.200 with MetalLB: 200 from kind network and pods |
| ExternalName | no | n/a (DNS CNAME only) | no | CNAME answered; HTTP needs the right Host header |
| Headless | no (`None`) | inside the cluster | no | DNS returns 3 pod IPs + per-pod names |

---

## Task 2 - Comparisons

### Deployment vs ReplicaSet

The real ownership chain in my cluster (`outputs/06a-deployment-vs-replicaset.txt`):

```text
$ kubectl get deploy,rs,pods -l app=web-clusterip
NAME                                READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/web-app-clusterip   3/3     3            3           3s

NAME                                           DESIRED   CURRENT   READY   AGE
replicaset.apps/web-app-clusterip-66865d4855   3         3         3       3s

NAME                                     READY   STATUS    RESTARTS   AGE
pod/web-app-clusterip-66865d4855-jjklg   1/1     Running   0          3s
pod/web-app-clusterip-66865d4855-nsqbc   1/1     Running   0          3s
pod/web-app-clusterip-66865d4855-px8zm   1/1     Running   0          3s

$ kubectl get pod web-app-clusterip-66865d4855-jjklg -o 'jsonpath={.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name} (controller={.metadata.ownerReferences[0].controller}){"\n"}'
ReplicaSet/web-app-clusterip-66865d4855 (controller=true)

$ kubectl get rs web-app-clusterip-66865d4855 -o 'jsonpath={.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name} (controller={.metadata.ownerReferences[0].controller}){"\n"}'
Deployment/web-app-clusterip (controller=true)

$ kubectl get deploy web-app-clusterip -o 'jsonpath=ownerReferences={.metadata.ownerReferences}{"\n"}'
ownerReferences=

$ kubectl get rs web-app-clusterip-66865d4855 -o 'jsonpath=selector={.spec.selector.matchLabels}{"\n"}'
selector={"app":"web-clusterip","pod-template-hash":"66865d4855"}
```

So it is **Pod -> owned by ReplicaSet -> owned by Deployment -> owned by nobody**. The ReplicaSet's selector carries the `pod-template-hash`, which keeps the ReplicaSets of different versions apart.

What I then tested:

```text
### Pod management: the ReplicaSet replaces a deleted pod
$ kubectl delete pod web-app-clusterip-66865d4855-jjklg --wait=false
$ kubectl get pods -l app=web-clusterip
NAME                                 READY   STATUS        RESTARTS   AGE
web-app-clusterip-66865d4855-hf6rp   0/1     Pending       0          0s
web-app-clusterip-66865d4855-jjklg   1/1     Terminating   0          4s
web-app-clusterip-66865d4855-nsqbc   1/1     Running       0          4s
web-app-clusterip-66865d4855-px8zm   1/1     Running       0          4s

### Scaling the ReplicaSet directly does not stick - the Deployment owns it and puts it back
$ kubectl scale rs web-app-clusterip-66865d4855 --replicas=1
replicaset.apps/web-app-clusterip-66865d4855 scaled
$ kubectl get rs -l app=web-clusterip
NAME                           DESIRED   CURRENT   READY   AGE
web-app-clusterip-66865d4855   4         4         4       13s

### Rolling update: a template change creates a NEW ReplicaSet; the old one is kept at 0 for rollback
$ kubectl set image deployment/web-app-clusterip nginx-web=nginx:1.27-alpine
$ kubectl get rs -l app=web-clusterip -o wide      (trimmed)
NAME                           DESIRED   CURRENT   READY   IMAGES
web-app-clusterip-66865d4855   0         0         0       nginx:1.25-alpine
web-app-clusterip-695dddddd5   4         4         4       nginx:1.27-alpine

### A bare ReplicaSet has no rollout at all (instructor's replicaset/backend-rs.yaml)
$ kubectl set image rs/yatri-backend-rs backend=python:3.12-alpine
replicaset.apps/yatri-backend-rs image updated
$ kubectl get pods -l app=yatri-backend -o 'custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image'
POD                      IMAGE
yatri-backend-rs-5cjv9   python:3.11-alpine
yatri-backend-rs-8hz2r   python:3.11-alpine
yatri-backend-rs-g84vq   python:3.11-alpine
$ kubectl rollout history rs/yatri-backend-rs
error: no history viewer has been implemented for "ReplicaSet.apps"
```

| | ReplicaSet | Deployment |
|---|---|---|
| Purpose | keep N copies of one pod template running | manage releases of an app over time |
| Pod management | creates/deletes pods to match `replicas`, adopts pods matching its selector | never touches pods directly; it manages ReplicaSets |
| Scaling | `kubectl scale rs` works only if nothing owns the RS | `kubectl scale deploy`; the Deployment overwrote my direct `scale rs --replicas=1` back to 4 |
| Rolling updates | none. A template change only affects pods created later (my 3 pods kept `python:3.11`) | yes: new RS per template, old RS scaled down step by step, `rollout status/history/undo` |
| Relationship | a Deployment's RS has an `ownerReference` to it and a `pod-template-hash` in its selector | owner of one RS per revision |
| Use directly? | almost never | yes, for stateless apps |

### Deployment vs DaemonSet vs StatefulSet

From `outputs/06b-daemonset-statefulset.txt`:

```text
$ kubectl get ds node-logging-agent -o wide       (instructor's daemonset/node-agent-ds.yaml, trimmed)
NAME                 DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR
node-logging-agent   1         1         1       1            1           <none>
$ kubectl logs -l app=node-logging-agent --tail=2
[Wed Oct  7 17:43:08 UTC 2026] Collecting host system metrics on node-logging-agent-tr584
$ kubectl scale ds node-logging-agent --replicas=3
Error from server (NotFound): the server could not find the requested resource
$ kubectl get ds -A        (trimmed)
NAMESPACE        NAME                 DESIRED   CURRENT   READY
default          node-logging-agent   1         1         1
kube-system      kindnet              1         1         1
kube-system      kube-proxy           1         1         1
metallb-system   speaker              1         1         1

$ kubectl get pods -l app=web-db -w --output-watch-events      (my workloads/statefulset-with-storage.yaml, trimmed)
ADDED      web-db-0   0/1     Pending             0          0s
MODIFIED   web-db-0   1/1     Running             0          3s
ADDED      web-db-1   0/1     Pending             0          0s      <- only after web-db-0 is Ready
MODIFIED   web-db-1   1/1     Running             0          5s

$ kubectl get pvc
NAME            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
data-web-db-0   Bound    pvc-79b56c10-c6f5-44b6-ad67-63543ec38198   16Mi       RWO            standard
data-web-db-1   Bound    pvc-cfa1f14e-f846-49f7-b8b7-2488856a3a52   16Mi       RWO            standard

$ kubectl exec web-db-0 -- cat /data/owner
web-db-0
$ kubectl delete pod web-db-0
$ kubectl exec web-db-0 -- cat /data/owner          # after it came back
web-db-0
$ kubectl get pod web-db-0 -o 'jsonpath={.spec.volumes[0].persistentVolumeClaim.claimName}{"\n"}'
data-web-db-0

$ kubectl exec dnsutils -- dig +short web-db-0.web-db.default.svc.cluster.local
10.244.0.17

$ kubectl delete -f workloads/statefulset-with-storage.yaml
$ kubectl get pvc        (still there: data-web-db-0, data-web-db-1 Bound)
```

| | Deployment | DaemonSet | StatefulSet |
|---|---|---|---|
| Use case | stateless apps: web, APIs, workers | one agent per node: log shipper, node exporter, CNI, kube-proxy, MetalLB speaker | stateful apps: databases, Kafka, ZooKeeper, Elasticsearch |
| Pod names | random (`web-app-clusterip-66865d4855-2w84d`) | random, one per node | ordinal and stable (`web-db-0`, `web-db-1`) |
| Pod creation | all at once, in any order | one per matching node, automatically when a node joins | in order 0, 1, 2 ...; the next one waits for the previous to be Ready |
| Scaling | `replicas` | no `replicas` field: follows the node count (my `scale ds` failed) | `replicas`, scales down from the highest ordinal |
| Networking | one Service, pods interchangeable | often `hostNetwork`/`hostPort` (speaker runs on the node IP) | headless Service gives each pod a DNS name (`web-db-0.web-db`) |
| Storage | shared volume or none; a PVC in the template would be shared by all pods | usually `hostPath` to read node files | `volumeClaimTemplates`: one PVC per pod (`data-web-db-0`), re-attached to the same pod after a restart, kept after the StatefulSet is deleted |
| Example in my cluster | `coredns`, `web-app-clusterip` | `kube-proxy`, `kindnet`, `speaker`, `node-logging-agent` | `web-stateful`, `web-db` |

### ReplicaSet vs Service

A ReplicaSet and a Service both use a label selector, but they do completely different jobs. From `outputs/06c-replicaset-vs-service.txt`:

```text
$ kubectl get endpointslices -l kubernetes.io/service-name=web-service-clusterip -o yaml      (trimmed)
  endpoints:
  - addresses:
    - 10.244.0.6
    conditions:
      ready: true
      serving: true
      terminating: false
    nodeName: hw-a-control-plane
    targetRef:
      kind: Pod
      name: web-app-clusterip-695dddddd5-tcj58
  ...
  metadata:
    labels:
      endpointslice.kubernetes.io/managed-by: endpointslice-controller.k8s.io
      kubernetes.io/service-name: web-service-clusterip
    ownerReferences:
    - kind: Service
      name: web-service-clusterip

### Without a Service, a client would need pod IPs - and they change when a pod is replaced
$ kubectl get pod web-app-clusterip-695dddddd5-lz9bv -o 'jsonpath={.status.podIP}{"\n"}'
10.244.0.7
$ kubectl delete pod web-app-clusterip-695dddddd5-lz9bv
$ kubectl get endpointslices -l kubernetes.io/service-name=web-service-clusterip
NAME                          ADDRESSTYPE   PORTS   ENDPOINTS                           AGE
web-service-clusterip-69bvq   IPv4          80      10.244.0.6,10.244.0.8,10.244.0.20   17m
$ kubectl get svc web-service-clusterip
NAME                    TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
web-service-clusterip   ClusterIP   10.96.96.222   <none>        8080/TCP   17m
$ kubectl exec curl-client -- curl -s -o /dev/null -w 'HTTP %{http_code} via %{remote_ip}\n' http://web-service-clusterip:8080
HTTP 200 via 10.96.96.222

### How the traffic actually reaches a pod: kube-proxy's iptables chain for this Service
-A KUBE-SERVICES -d 10.96.96.222/32 -p tcp ... --dport 8080 -j KUBE-SVC-TIXQXGX7DUC52XEM
-A KUBE-SVC-TIXQXGX7DUC52XEM ... -> 10.244.0.20:80" -m statistic --mode random --probability 0.33333333349 -j KUBE-SEP-Z2VVDCEITVPGKUDB
-A KUBE-SVC-TIXQXGX7DUC52XEM ... -> 10.244.0.6:80" -m statistic --mode random --probability 0.50000000000 -j KUBE-SEP-A5RNH7T5JVKFJ3BA
-A KUBE-SVC-TIXQXGX7DUC52XEM ... -> 10.244.0.8:80" -j KUBE-SEP-KQYXHOSXGF3CO67S
-A KUBE-SEP-Z2VVDCEITVPGKUDB -p tcp ... -j DNAT --to-destination 10.244.0.20:80

### A Service whose selector matches nothing has no endpoints (no traffic possible):
$ kubectl get endpointslices -l kubernetes.io/service-name=nobody-home
NAME                ADDRESSTYPE   PORTS     ENDPOINTS   AGE
nobody-home-4t9s2   IPv4          <unset>   <unset>     0s
$ kubectl exec curl-client -- curl -s -m 3 -o /dev/null -w 'HTTP %{http_code}\n' http://nobody-home
HTTP 000
command terminated with exit code 7
```

| | ReplicaSet | Service |
|---|---|---|
| Responsibility | **how many** pods exist; replaces dead ones | **how to reach** whichever pods exist right now |
| Selector used for | counting and owning pods | building the endpoint list |
| Gives you | pods with changing names and IPs | one stable name (DNS) + one stable virtual IP + port mapping |
| Load balancing | none | yes (kube-proxy) |
| Created objects | Pods (with ownerReference) | EndpointSlices (with ownerReference) |

**Why a Service is required.** Pods are cattle: when I deleted one, its replacement came back with a different IP (`10.244.0.7` gone, `10.244.0.20` new). Nothing should hard-code pod IPs. The Service name and ClusterIP did not change, and the request still worked.

**How traffic reaches a pod**, step by step, as seen above:

1. The **EndpointSlice controller** watches pods that match the Service selector and are **Ready**, and writes their IPs into EndpointSlices owned by the Service. A pod that fails its readiness probe drops out here.
2. **kube-proxy** on every node watches Services and EndpointSlices and writes iptables rules: `KUBE-SERVICES` matches the ClusterIP:port, jumps to `KUBE-SVC-...`, which picks one `KUBE-SEP-...` at random (probabilities 1/3, 1/2, rest), and that does a **DNAT** to `podIP:targetPort`.
3. The client's packet to `10.96.96.222:8080` is rewritten in the kernel on the client's own node to `10.244.0.20:80` and delivered over the pod network (kindnet). No proxy process sits in the data path.
4. If the selector matches nothing (my `nobody-home` Service), the slice is empty, there is no DNAT target, and connections are refused. This is the first thing to check when a Service "doesn't work" (see session 12, troubleshooting `empty-endpoints.yaml`).

---

## Cleanup

At the end I deleted all the session 11 workloads, Services, test pods and the `team-b` namespace. I left MetalLB in the cluster for session 12, and deleted the whole cluster at the very end (`kind delete cluster --name hw-a`).
