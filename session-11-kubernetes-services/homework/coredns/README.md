# CoreDNS in Kubernetes

**Name:** Rudhar Bajaj
**Environment:** kind cluster `hw-a` (Kubernetes v1.37.0, CoreDNS 1.14.6) on macOS / Docker Desktop

Every output block is real output from 2026-10-07. Full transcripts: [`../outputs/08-coredns.txt`](../outputs/08-coredns.txt) (setup, Corefile, query logging) and [`../outputs/09-coredns-troubleshooting.txt`](../outputs/09-coredns-troubleshooting.txt) (outage drill).

## Contents

1. [What CoreDNS is and why Kubernetes uses it](#1-what-coredns-is-and-why-kubernetes-uses-it)
2. [How service discovery works](#2-how-service-discovery-works)
3. [How a DNS query is resolved](#3-how-a-dns-query-is-resolved)
4. [CoreDNS configuration: the Corefile](#4-coredns-configuration-the-corefile) (and [watching real queries](#4-watching-real-queries))
5. [Troubleshooting DNS](#5-troubleshooting-dns)

---

## 1. What CoreDNS is and why Kubernetes uses it

CoreDNS is a small DNS server written in Go (a CNCF graduated project). Everything it does comes from **plugins** that are chained together in a config file, the Corefile. Since Kubernetes 1.13 it has been the default cluster DNS, replacing kube-dns (which was dnsmasq + sidecars). The Service is still named `kube-dns` for compatibility.

Kubernetes needs a DNS server **inside** the cluster because:
- pod and Service IPs are assigned dynamically and change, so apps must find each other by **name**;
- the names (`<svc>.<ns>.svc.cluster.local`) must be answered from the **live** cluster state, which an external DNS server cannot see;
- every pod must also still resolve internet names, so it needs one resolver that does both.

In my cluster:

```text
$ kubectl get deploy coredns -n kube-system -o wide
NAME      READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES                                    SELECTOR
coredns   2/2     2            2           58m   coredns      registry.k8s.io/coredns/coredns:v1.14.6   k8s-app=kube-dns

$ kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide      (trimmed)
NAME                       READY   STATUS    RESTARTS      AGE   IP
coredns-559f6c778d-7srwb   1/1     Running   1 (48m ago)   58m   10.244.0.3
coredns-559f6c778d-q6rhr   1/1     Running   1 (48m ago)   58m   10.244.0.2

$ kubectl get svc kube-dns -n kube-system -o wide
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE   SELECTOR
kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   58m   k8s-app=kube-dns

$ kubectl get endpointslices -n kube-system -l kubernetes.io/service-name=kube-dns
NAME             ADDRESSTYPE   PORTS        ENDPOINTS               AGE
kube-dns-t4nwm   IPv4          53,53,9153   10.244.0.3,10.244.0.2   58m
```

It is an ordinary Deployment with 2 replicas behind an ordinary ClusterIP Service. Port 9153 is its Prometheus metrics port.

## 2. How service discovery works

1. I create a Service. The API server stores it, and the EndpointSlice controller fills its EndpointSlices with the IPs of the ready pods.
2. CoreDNS's **`kubernetes` plugin** watches Services and EndpointSlices through the API server and keeps them in memory. No DNS records are ever written anywhere by hand.
3. The kubelet starts every pod with `/etc/resolv.conf` pointing at the `kube-dns` ClusterIP. The value comes from the kubelet's own config:

```text
$ docker exec hw-a-control-plane grep -A3 -i clusterDNS /var/lib/kubelet/config.yaml
clusterDNS:
- 10.96.0.10
clusterDomain: cluster.local

$ kubectl exec dnsutils -- cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

4. A pod asks for `web-service-clusterip`, and CoreDNS answers from its in-memory view: the ClusterIP for a normal Service, the pod IPs for a headless one, a CNAME for ExternalName. All of these are shown in the main README, Task 1, and in [`../fqdn/README.md`](../fqdn/README.md).

## 3. How a DNS query is resolved

```text
 pod (curl web-service-clusterip)
   | 1. libc reads /etc/resolv.conf: ndots:5, search default.svc.cluster.local ...
   | 2. query "web-service-clusterip.default.svc.cluster.local A" -> 10.96.0.10:53 (UDP)
   v
 kube-proxy iptables on the node: 10.96.0.10:53 -> DNAT to one CoreDNS pod (10.244.0.2 or .3)
   v
 CoreDNS plugin chain (Corefile order of execution):
   errors -> health/ready -> kubernetes cluster.local in-addr.arpa ip6.arpa
     - name is in cluster.local?  answer from the in-memory Service/EndpointSlice cache (authoritative, "aa")
     - name not in cluster.local? fall through ...
   -> cache 30 -> forward . /etc/resolv.conf  (the node's resolver -> Docker Desktop DNS -> internet)
   v
 answer goes back to the pod; the app connects to the returned IP (for a ClusterIP, kube-proxy DNATs again)
```

Both paths from my cluster, the in-cluster name and an internet name:

```text
$ kubectl exec dnsutils -- dig @10.96.0.10 +noall +answer +stats web-service-clusterip.default.svc.cluster.local
web-service-clusterip.default.svc.cluster.local. 30 IN A 10.96.96.222
;; Query time: 2 msec
;; SERVER: 10.96.0.10#53(10.96.0.10)

$ kubectl exec dnsutils -- dig @10.244.0.3 +noall +answer web-service-clusterip.default.svc.cluster.local     # one CoreDNS pod directly
web-service-clusterip.default.svc.cluster.local. 30 IN A 10.96.96.222

$ docker exec hw-a-control-plane cat /etc/resolv.conf      (comments trimmed)
nameserver 192.168.65.254
options ndots:0

$ kubectl exec dnsutils -- dig +noall +answer +stats kubernetes.io
kubernetes.io.		30	IN	A	3.33.186.135
kubernetes.io.		30	IN	A	15.197.167.90
;; Query time: 11 msec
;; SERVER: 10.96.0.10#53(10.96.0.10)
```

The cluster name took 2 ms (answered from memory). `kubernetes.io` took 11 ms (forwarded to `192.168.65.254`, Docker Desktop's resolver). The TTL is 30 s for both, set by `ttl 30` and `cache 30` in the Corefile.

## 4. CoreDNS configuration: the Corefile

The Corefile lives in the ConfigMap `kube-system/coredns`, mounted into the CoreDNS pods:

```text
$ kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}'
.:53 {
    errors
    health {
       lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
       max_concurrent 1000
    }
    cache 30 {
       disable success cluster.local
       disable denial cluster.local
    }
    loop
    reload
    loadbalance
}
```

| Line | Meaning |
|---|---|
| `.:53` | one server block for all names (`.`) on port 53 |
| `errors` | log errors to stdout |
| `health { lameduck 5s }` | `:8080/health` for the liveness probe; on shutdown keep answering 5 s more |
| `ready` | `:8181/ready` for the readiness probe (ready once all plugins are) |
| `kubernetes cluster.local in-addr.arpa ip6.arpa` | answer cluster names and reverse lookups from the API. `pods insecure` enables `a-b-c-d.<ns>.pod` names. `fallthrough` passes reverse lookups it can't answer to the next plugin. `ttl 30` is the record TTL |
| `prometheus :9153` | metrics |
| `forward . /etc/resolv.conf` | everything else goes to the node's resolver |
| `cache 30 { disable success/denial cluster.local }` | cache external answers up to 30 s; do **not** cache cluster names, so changes show up right away |
| `loop` | detect a forwarding loop (CoreDNS forwarding to itself) and stop |
| `reload` | re-read the Corefile when the ConfigMap changes, with no restart |
| `loadbalance` | shuffle the order of A records in each answer |

### 4. Watching real queries

To see the resolution steps, I added the `log` plugin, waited for `reload`, ran one lookup, and then restored the original Corefile:

```text
$ kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' > Corefile.orig    # backup
$ sed 's/^    errors$/    errors\n    log/' Corefile.orig > Corefile.log
$ kubectl create configmap coredns -n kube-system --from-file=Corefile=Corefile.log --dry-run=client -o yaml | kubectl apply -f -
configmap/coredns configured

$ kubectl logs -n kube-system -l k8s-app=kube-dns --since-time=... --prefix      (trimmed)
[pod/coredns-559f6c778d-q6rhr/coredns] [INFO] plugin/reload: Running configuration SHA512 = 2dd49c56...
[pod/coredns-559f6c778d-q6rhr/coredns] [INFO] Reloading complete

$ kubectl exec dnsutils -- nslookup api.team-b
Name:	api.team-b.svc.cluster.local
Address: 10.96.101.126

$ kubectl logs -n kube-system -l k8s-app=kube-dns --since=40s --prefix | grep api.team-b      (one of the three lookups)
[pod/coredns-559f6c778d-7srwb/coredns] [INFO] 10.244.0.214:34875 - 59548 "A IN api.team-b.default.svc.cluster.local. udp 54 false 512" NXDOMAIN qr,aa,rd 147 0.001063125s
[pod/coredns-559f6c778d-7srwb/coredns] [INFO] 10.244.0.214:47997 - 10796 "A IN api.team-b.svc.cluster.local. udp 46 false 512" NOERROR qr,aa,rd 90 0.002085875s

$ kubectl create configmap coredns -n kube-system --from-file=Corefile=Corefile.orig --dry-run=client -o yaml | kubectl apply -f -
configmap/coredns configured
```

**What I observed.** `reload` picked up the change in each pod by itself within about 30 s, with no restart. The log shows the client (`10.244.0.214` = my `dnsutils` pod) walking the search list: first `api.team-b.default.svc.cluster.local` -> NXDOMAIN, then `api.team-b.svc.cluster.local` -> NOERROR. Both answers have the `aa` (authoritative) flag and took about 1-2 ms, because they came from the `kubernetes` plugin.

My first attempt at restoring failed. I had saved the ConfigMap with `kubectl get -o yaml`, which keeps the old `resourceVersion`, so `kubectl apply` was rejected with `Conflict ... the object has been modified`. In the final run I saved only the Corefile text, which avoids that.

## 5. Troubleshooting DNS

### Checklist with real commands

| Step | Command | What healthy looks like here |
|---|---|---|
| 1. Can the pod resolve at all? | `kubectl exec dnsutils -- nslookup kubernetes.default` | an answer from `10.96.0.10` |
| 2. Is the pod pointed at cluster DNS? | `kubectl exec <pod> -- cat /etc/resolv.conf` | `nameserver 10.96.0.10`, `search <ns>.svc.cluster.local ...` |
| 3. Does the DNS Service have endpoints? | `kubectl get svc,endpointslices -n kube-system -l k8s-app=kube-dns` / `-l kubernetes.io/service-name=kube-dns` | 2 endpoints on port 53 |
| 4. Are CoreDNS pods running and ready? | `kubectl get pods -n kube-system -l k8s-app=kube-dns` | `1/1 Running` |
| 5. What does CoreDNS say? | `kubectl logs -n kube-system -l k8s-app=kube-dns` | no `[ERROR]` lines |
| 6. Cluster name vs external name | `dig <svc>.<ns>.svc.cluster.local` and `dig kubernetes.io` | if only external names fail -> upstream/`forward` problem |
| 7. Name or network problem? | `curl` the Service by name, then by ClusterIP | by IP works but by name fails -> DNS |
| 8. Config | `kubectl get cm coredns -n kube-system -o yaml` | Corefile as above |

### Drill: CoreDNS is down

I broke DNS on purpose by scaling CoreDNS to 0, then followed the checklist.

**Symptom:**

```text
$ kubectl -n kube-system scale deployment coredns --replicas=0
deployment.apps/coredns scaled

$ kubectl exec dnsutils -- nslookup -timeout=3 web-service-clusterip
;; connection timed out; no servers could be reached
command terminated with exit code 1

$ kubectl exec curl-client -- curl -s -m 8 -o /dev/null -w 'by name -> HTTP %{http_code}\n' http://web-service-clusterip:8080
by name -> HTTP 000
command terminated with exit code 6

$ kubectl exec curl-client -- curl -s -m 5 -o /dev/null -w "by IP 10.96.96.222 -> HTTP %{http_code}\n" http://10.96.96.222:8080
by IP 10.96.96.222 -> HTTP 200
```

**Diagnosis:**

```text
$ kubectl exec dnsutils -- cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10                         <- correct
options ndots:5

$ kubectl get svc kube-dns -n kube-system
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   61m      <- Service exists

$ kubectl get endpointslices -n kube-system -l kubernetes.io/service-name=kube-dns
NAME             ADDRESSTYPE   PORTS     ENDPOINTS   AGE
kube-dns-t4nwm   IPv4          <unset>   <unset>     61m                            <- but no endpoints

$ kubectl get deploy coredns -n kube-system
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
coredns   0/0     0            0           61m                                      <- root cause

$ kubectl get pods -n kube-system -l k8s-app=kube-dns
No resources found in kube-system namespace.
```

**Root cause:** the CoreDNS Deployment had 0 replicas, so the `kube-dns` Service had no endpoints and every query to `10.96.0.10` went nowhere. curl's exit code 6 means "couldn't resolve host", and the same Service by IP still returned 200. So the network was fine and only DNS was broken.

**Fix and verification:**

```text
$ kubectl -n kube-system scale deployment coredns --replicas=2
deployment.apps/coredns scaled

$ kubectl get endpointslices -n kube-system -l kubernetes.io/service-name=kube-dns
NAME             ADDRESSTYPE   PORTS        ENDPOINTS                 AGE
kube-dns-t4nwm   IPv4          53,53,9153   10.244.0.23,10.244.0.24   61m

$ kubectl exec dnsutils -- nslookup web-service-clusterip
Name:	web-service-clusterip.default.svc.cluster.local
Address: 10.96.96.222

$ kubectl exec curl-client -- curl -s -m 8 -o /dev/null -w 'by name -> HTTP %{http_code}\n' http://web-service-clusterip:8080
by name -> HTTP 200
```

### A real problem I hit: a flaky upstream

I did not cause this one. The CoreDNS logs showed timeouts towards Docker Desktop's resolver:

```text
$ kubectl logs -n kube-system -l k8s-app=kube-dns --tail=6 --prefix      (trimmed)
[pod/coredns-559f6c778d-7srwb/coredns] [ERROR] plugin/errors: 2 example.com. A: read udp 10.244.0.3:49780->192.168.65.254:53: i/o timeout
[pod/coredns-559f6c778d-7srwb/coredns] [ERROR] plugin/errors: 2 kubernetes.io. A: read udp 10.244.0.3:59115->192.168.65.254:53: i/o timeout
[pod/coredns-559f6c778d-7srwb/coredns] [ERROR] plugin/errors: 2 api. A: read udp 10.244.0.3:35857->192.168.65.254:53: i/o timeout
```

In the same session, image pulls on the node failed with `lookup registry-1.docker.io on 192.168.65.254:53: server misbehaving`. So cluster names always resolved, but external names failed now and then. Following steps 5 and 6 of the checklist points straight at `forward` and the upstream, not at CoreDNS itself. In a real cluster I would point `forward` at a reliable resolver (e.g. `forward . 1.1.1.1 8.8.8.8`) or fix the node's resolver. On my laptop I just retried. It also explains why the wrong short name `api` in the FQDN tests gave a slow SERVFAIL instead of a quick NXDOMAIN: after the search list ran out, the bare name `api.` went upstream and timed out.

### Other common DNS problems (not reproduced here)

| Symptom | Likely cause | Check |
|---|---|---|
| CoreDNS in `CrashLoopBackOff`, log says `Loop ... detected` | node's `/etc/resolv.conf` points at a local stub (127.0.0.53), so CoreDNS forwards to itself | `kubectl logs`, the `loop` plugin message; point `forward` at a real upstream |
| Only one namespace can't resolve | NetworkPolicy blocking egress to kube-system port 53 | `kubectl get networkpolicy -A` |
| Slow lookups for external names | `ndots:5` makes 4 failed cluster lookups first | use FQDN with trailing dot, or `dnsConfig.options ndots` per pod |
| Pod uses the node's DNS | `dnsPolicy: Default` or `hostNetwork: true` without `ClusterFirstWithHostNet` | `kubectl get pod -o yaml | grep dnsPolicy` |
