# FQDN and Service DNS in Kubernetes

**Name:** Rudhar Bajaj
**Environment:** kind cluster `hw-a` (Kubernetes v1.37.0, CoreDNS 1.14.6) on macOS / Docker Desktop

Every output block is real output from 2026-10-07. The full transcript is [`../outputs/07-fqdn.txt`](../outputs/07-fqdn.txt). The second namespace and its Service come from [`team-b.yaml`](team-b.yaml), and the `dnsutils` pod in `default` comes from [`../dns-debug-pod.yaml`](../dns-debug-pod.yaml).

## Contents

1. [What an FQDN is](#1-what-an-fqdn-is)
2. [Service DNS and the naming convention](#2-service-dns-and-the-naming-convention)
3. [Namespace-based DNS: the search list in /etc/resolv.conf](#3-namespace-based-dns-the-search-list-in-etcresolvconf)
4. [Pod-to-Service communication across two namespaces (real lookups)](#4-pod-to-service-communication-across-two-namespaces)
5. [Other names CoreDNS serves](#5-other-names-coredns-serves)
6. [Rules of thumb](#6-rules-of-thumb)

---

## 1. What an FQDN is

A **Fully Qualified Domain Name** is a name that is complete all the way up to the DNS root, so it means the same thing wherever it is looked up. Strictly, it ends with a dot: `www.example.com.`. A short name like `api` is **relative**: it only means something together with a list of domains to try, and the answer depends on who is asking.

Kubernetes uses both. Every Service gets a full name, and pods are set up so that short names work inside their own namespace.

## 2. Service DNS and the naming convention

```text
   api   .  team-b  .  svc  .  cluster.local
   ----     ------     ---     -------------
   Service  Namespace  "this   cluster domain (kubelet --cluster-domain,
   name                is a    shown in /var/lib/kubelet/config.yaml:
                       Service" clusterDomain: cluster.local)
```

`<service>.<namespace>.svc.cluster.local` is the FQDN of every Service. CoreDNS answers it with:

| Service type | A record returns |
|---|---|
| ClusterIP / NodePort / LoadBalancer | the Service's ClusterIP |
| Headless (`clusterIP: None`) | the IPs of all ready pods, plus `<pod>.<service>.<ns>.svc.cluster.local` per pod for StatefulSets |
| ExternalName | a CNAME to the external name |

## 3. Namespace-based DNS: the search list in /etc/resolv.conf

The kubelet writes `/etc/resolv.conf` into every pod. The search list starts with the pod's **own namespace**:

```text
$ kubectl exec dnsutils -- cat /etc/resolv.conf                 # pod in namespace default
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5

$ kubectl exec -n team-b dnsutils -- cat /etc/resolv.conf       # pod in namespace team-b
search team-b.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

- `nameserver 10.96.0.10` is the ClusterIP of the `kube-dns` Service, i.e. CoreDNS.
- `options ndots:5`: any name with fewer than 5 dots is first tried with each search suffix appended, and only then as given.
- So in namespace `default`, `api` is tried as `api.default.svc.cluster.local`, then `api.svc.cluster.local`, then `api.cluster.local`, then `api.` (upstream). In namespace `team-b` the first try is `api.team-b.svc.cluster.local`.

## 4. Pod-to-Service communication across two namespaces

Setup: the Service `api` (nginx) lives in namespace **team-b**. I query it from a pod in **default** and from a pod in **team-b**.

```text
$ kubectl get svc api -n team-b
NAME   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
api    ClusterIP   10.96.101.126   <none>        80/TCP    1s
```

**From namespace default, the short name fails:**

```text
$ kubectl exec dnsutils -- nslookup api
Server:		10.96.0.10
Address:	10.96.0.10#53

** server can't find api: SERVFAIL
command terminated with exit code 1
```

**From namespace default, adding the namespace works, in any of these forms:**

```text
$ kubectl exec dnsutils -- nslookup api.team-b
Name:	api.team-b.svc.cluster.local
Address: 10.96.101.126

$ kubectl exec dnsutils -- nslookup api.team-b.svc
Name:	api.team-b.svc.cluster.local
Address: 10.96.101.126

$ kubectl exec dnsutils -- nslookup api.team-b.svc.cluster.local
Name:	api.team-b.svc.cluster.local
Address: 10.96.101.126
```

**From namespace team-b, the short name works, because its own namespace comes first in the search list:**

```text
$ kubectl exec -n team-b dnsutils -- nslookup api
Name:	api.team-b.svc.cluster.local
Address: 10.96.101.126
```

**And the other way round: from team-b, a Service in default needs its namespace:**

```text
$ kubectl exec -n team-b dnsutils -- nslookup web-service-clusterip
** server can't find web-service-clusterip: NXDOMAIN
command terminated with exit code 1

$ kubectl exec -n team-b dnsutils -- nslookup web-service-clusterip.default.svc.cluster.local
Name:	web-service-clusterip.default.svc.cluster.local
Address: 10.96.96.222
```

**HTTP from a pod in default to the Service in team-b:**

```text
$ kubectl exec curl-client -- curl -s -o /dev/null -w 'default -> http://api.team-b.svc.cluster.local -> HTTP %{http_code} via %{remote_ip}\n' http://api.team-b.svc.cluster.local
default -> http://api.team-b.svc.cluster.local -> HTTP 200 via 10.96.101.126

$ kubectl exec curl-client -- curl -s -m 5 -o /dev/null -w 'default -> http://api -> HTTP %{http_code}\n' http://api
default -> http://api -> HTTP 000
command terminated with exit code 28
```

**Watching the search list do its work.** With query logging switched on in CoreDNS ([`../coredns/README.md`](../coredns/README.md#4-watching-real-queries)), one `nslookup api.team-b` from namespace default shows up as two queries:

```text
"A IN api.team-b.default.svc.cluster.local. udp 54 false 512" NXDOMAIN qr,aa,rd 147 0.001063125s
"A IN api.team-b.svc.cluster.local. udp 46 false 512" NOERROR qr,aa,rd 90 0.001936166s
```

**A trailing dot makes the name absolute,** so no search list is applied:

```text
$ kubectl exec dnsutils -- nslookup api.team-b.svc.cluster.local.
Name:	api.team-b.svc.cluster.local
Address: 10.96.101.126
```

**What I observed.**
- DNS scope follows namespaces. The short name only resolves inside the Service's own namespace; from anywhere else you need at least `<svc>.<ns>`.
- The failed short-name lookup from `default` ended in **SERVFAIL**, not NXDOMAIN. All three `*.cluster.local` tries returned NXDOMAIN, and then the bare name `api.` was forwarded to the upstream resolver (Docker Desktop's DNS), which was timing out (see the CoreDNS logs in `../outputs/08-coredns.txt`). That is also why `curl http://api` hung until its 5 s timeout (exit 28) instead of failing at once. A typo in a Service name can show up as a slow timeout rather than a clean "not found".
- `ndots:5` costs extra queries: `api.team-b` was looked up as `api.team-b.default.svc.cluster.local` first (NXDOMAIN) before the right name. Using the full FQDN with a trailing dot avoids that, which matters for chatty apps.

## 5. Other names CoreDNS serves

```text
# SRV record: port number + target for a named Service port (_<port-name>._<proto>.<svc>...)
$ kubectl exec dnsutils -- dig +noall +answer SRV _http._tcp.web-service-clusterip.default.svc.cluster.local
_http._tcp.web-service-clusterip.default.svc.cluster.local. 30 IN SRV 0 100 8080 web-service-clusterip.default.svc.cluster.local.

# pod A record: <pod-ip-with-dashes>.<namespace>.pod.cluster.local
$ kubectl exec dnsutils -- dig +noall +answer 10-244-0-22.team-b.pod.cluster.local
10-244-0-22.team-b.pod.cluster.local. 30 IN A	10.244.0.22

# the API server itself is a Service too
$ kubectl exec dnsutils -- dig +noall +answer kubernetes.default.svc.cluster.local
kubernetes.default.svc.cluster.local. 30 IN A	10.96.0.1
```

Per-pod names for StatefulSets behind a headless Service (`web-stateful-0.web-service-headless.default.svc.cluster.local`) are shown in the main README, Task 1, section 5.

## 6. Rules of thumb

| Situation | Name to use | Example |
|---|---|---|
| Same namespace | short name | `http://api` |
| Other namespace | `<svc>.<ns>` (or the full FQDN) | `http://api.team-b` |
| Config files, shared libraries, anything that may run in another namespace | full FQDN | `api.team-b.svc.cluster.local` |
| Performance-sensitive lookups | FQDN with trailing dot | `api.team-b.svc.cluster.local.` |
| A specific StatefulSet pod | `<pod>.<headless-svc>.<ns>` | `web-stateful-0.web-service-headless.default` |
| Something outside the cluster under an in-cluster name | ExternalName Service | `external-web` -> `example.com` |
