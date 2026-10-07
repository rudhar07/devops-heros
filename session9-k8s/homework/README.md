# Kubernetes Fundamentals - Homework

**Name:** Rudhar Bajaj
**Environment:** macOS 26.5.2 (Apple Silicon), Docker Desktop (Engine 29.6.1, linux/arm64), minikube v1.39.0 (docker driver, Kubernetes v1.37.0, containerd 2.3.4), kubectl v1.36.1

Every output block below is real output from commands I ran on 2026-10-07. Full untrimmed transcripts are in `outputs/`. Where I shortened a listing I say so.

| File | Contents |
|---|---|
| `outputs/01-minikube-install.txt` | `minikube version`, Docker version, `minikube start` (download progress bar trimmed) |
| `outputs/02-cluster-status.txt` | `minikube status`, profile list, `kubectl version`, `get nodes -o wide`, `cluster-info`, `componentstatuses`, `/readyz?verbose`, namespaces |
| `outputs/03-architecture.txt` | control-plane pods, static pod manifests, processes on the node, `crictl ps`, API server flags, node info |
| `outputs/04-basic-objects.txt` | `api-resources`, a first Pod (`run`, `describe`, `logs`, `exec`, `-o yaml`, `explain`), namespaces |
| `outputs/05-basics-tutorial.txt` | Kubernetes Basics tutorial, modules 2-6 (deploy, explore, expose, scale, update, rollback) |
| `outputs/06-minikube-delete.txt` | `minikube delete` |

## Contents

1. [Task 1 - Install and configure Minikube](#task-1---install-and-configure-minikube)
2. [Task 2 - Verify cluster status](#task-2---verify-cluster-status)
3. [Task 3 - Kubernetes architecture](#task-3---kubernetes-architecture)
4. [Task 4 - Basic objects and commands](#task-4---basic-objects-and-commands)
5. [Task 5 - Kubernetes Basics tutorial](#task-5---kubernetes-basics-tutorial)
6. [Why sessions 10-12 use kind instead of minikube](#why-sessions-10-12-use-kind-instead-of-minikube)

---

## Task 1 - Install and configure Minikube

minikube was already installed with Homebrew (`brew install minikube`). I started a named profile with the Docker driver, limited to 2 CPUs and 2 GB, because other things share Docker Desktop's 8 GB VM. I also pointed `KUBECONFIG` at a private file, so this cluster did not touch my normal `~/.kube/config`.

```bash
export KUBECONFIG=<private kubeconfig file>
minikube version
minikube start -p hw-minikube --driver=docker --memory=2048 --cpus=2
```

```text
$ minikube version
minikube version: v1.39.0
commit: 7a9f6a841470a207de8cf4bafcccee0969d8ba10

$ minikube start -p hw-minikube --driver=docker --memory=2048 --cpus=2
* [hw-minikube] minikube v1.39.0 on Darwin 26.5.2 (arm64)
* Using the docker driver based on user configuration
* Using Docker Desktop driver with root privileges
* Starting "hw-minikube" primary control-plane node in "hw-minikube" cluster
* Pulling base image v0.0.51 ...
* Configuring CNI (Container Networking Interface) ...
* Verifying Kubernetes components...
  - Using image gcr.io/k8s-minikube/storage-provisioner:v5
* Enabled addons: storage-provisioner, default-storageclass
* Done! kubectl is now configured to use "hw-minikube" cluster and "default" namespace by default
```

**What I observed.** With the Docker driver, minikube runs the whole "node" as one Docker container (`hw-minikube`), based on the `kicbase` image (470 MB on first pull). kubectl was configured automatically: the current context became `hw-minikube`.

## Task 2 - Verify cluster status

```bash
minikube status -p hw-minikube
kubectl get nodes -o wide
kubectl cluster-info
kubectl get componentstatuses
kubectl get --raw='/readyz?verbose'
```

```text
$ minikube status -p hw-minikube
hw-minikube
type: Control Plane
host: Running
kubelet: Running
apiserver: Running
kubeconfig: Configured

$ kubectl version
Client Version: v1.36.1
Kustomize Version: v5.8.1
Server Version: v1.37.0

$ kubectl get nodes -o wide
NAME          STATUS     ROLES           AGE   VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION             CONTAINER-RUNTIME
hw-minikube   NotReady   control-plane   22s   v1.37.0   192.168.49.2   <none>        Debian GNU/Linux 12 (bookworm)   6.12.76-linuxkit (arm64)   containerd://2.3.4

$ kubectl cluster-info
Kubernetes control plane is running at https://127.0.0.1:56343
CoreDNS is running at https://127.0.0.1:56343/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

$ kubectl get componentstatuses
Warning: v1 ComponentStatus is deprecated in v1.19+
NAME                 STATUS    MESSAGE   ERROR
scheduler            Healthy   ok
controller-manager   Healthy   ok
etcd-0               Healthy   ok

$ kubectl get --raw=/readyz?verbose          (37 checks, trimmed)
[+]ping ok
[+]etcd ok
[+]etcd-readiness ok
[+]informer-sync ok
...
readyz check passed

$ kubectl wait --for=condition=Ready node --all --timeout=180s
node/hw-minikube condition met

$ kubectl get nodes -o wide        (some columns trimmed)
NAME          STATUS   ROLES           AGE   VERSION   INTERNAL-IP    ...   CONTAINER-RUNTIME
hw-minikube   Ready    control-plane   43s   v1.37.0   192.168.49.2   ...   containerd://2.3.4
```

**What I observed.** My first `get nodes` ran 22 seconds after start and showed `NotReady`. The API server was already up, but the CNI plugin (kindnet) had not started yet, so the kubelet reported the network as not ready. About 20 seconds later the node was `Ready`. `componentstatuses` is deprecated; `/readyz?verbose` is the current way to check API server health, and it includes the etcd checks.

## Task 3 - Kubernetes architecture

### The components

| Part | Component | Job | Where it runs in my minikube cluster |
|---|---|---|---|
| Control plane | **kube-apiserver** | The front door. Every `kubectl` call and every component talks to it over HTTPS. It authenticates, authorizes, validates and stores objects in etcd. | static pod `kube-apiserver-hw-minikube` |
| Control plane | **etcd** | Key-value database that holds the whole cluster state (desired and current). Only the API server talks to it. | static pod `etcd-hw-minikube` |
| Control plane | **kube-scheduler** | Watches for Pods with no node and picks a node for each (resources, affinity, taints). | static pod `kube-scheduler-hw-minikube` |
| Control plane | **kube-controller-manager** | Runs the control loops: Deployment, ReplicaSet, Node, Job, EndpointSlice, ServiceAccount, and more. Each loop compares desired state with actual state and fixes the difference. | static pod `kube-controller-manager-hw-minikube` |
| Control plane | **cloud-controller-manager** | Talks to a cloud API: creates load balancers, sets node addresses, attaches routes. | **not present.** minikube is not on a cloud, so there is nothing to talk to. |
| Node | **kubelet** | Agent on every node. Gets the Pods assigned to its node from the API server and makes the container runtime run them; runs probes; reports status. | systemd service on the node (not a pod) |
| Node | **kube-proxy** | Turns Services into network rules (iptables here) on every node. | DaemonSet pod `kube-proxy-8pfb9` |
| Node | **container runtime** | Pulls images and runs containers (via the CRI). | `containerd://2.3.4` |
| Add-ons | CoreDNS, CNI (kindnet), storage-provisioner | Cluster DNS, pod networking, dynamic volumes. | pods in `kube-system` |

```text
                     kubectl
                        |
                        v  HTTPS
   +-------------------------------------------- control plane -----+
   |  kube-apiserver  <----->  etcd                                  |
   |     ^      ^                                                    |
   |     |      +---- kube-scheduler (assigns pods to nodes)         |
   |     +----------- kube-controller-manager (reconcile loops)      |
   |                  [cloud-controller-manager: only on a cloud]    |
   +-----------------------------------------------------------------+
                        ^  watches / status
                        |
   +------------------------------------------------- node ----------+
   |  kubelet ---> containerd ---> containers of the pods            |
   |  kube-proxy  (Service -> iptables rules)                        |
   +-----------------------------------------------------------------+
   (in minikube the control plane and the node are the same machine)
```

### The real pods in my cluster

```text
$ kubectl get pods -n kube-system -o wide        (last two columns trimmed)
NAME                                  READY   STATUS    RESTARTS   AGE   IP             NODE
coredns-559f6c778d-x26wn              1/1     Running   0          47s   10.244.0.2     hw-minikube
etcd-hw-minikube                      1/1     Running   0          54s   192.168.49.2   hw-minikube
kindnet-zxz2k                         1/1     Running   0          47s   192.168.49.2   hw-minikube
kube-apiserver-hw-minikube            1/1     Running   0          54s   192.168.49.2   hw-minikube
kube-controller-manager-hw-minikube   1/1     Running   0          54s   192.168.49.2   hw-minikube
kube-proxy-8pfb9                      1/1     Running   0          47s   192.168.49.2   hw-minikube
kube-scheduler-hw-minikube            1/1     Running   0          54s   192.168.49.2   hw-minikube
storage-provisioner                   1/1     Running   0          52s   192.168.49.2   hw-minikube

$ kubectl get pods -n kube-system -l tier=control-plane -o custom-columns=NAME:.metadata.name,COMPONENT:.metadata.labels.component,IMAGE:.spec.containers[0].image
NAME                                  COMPONENT                 IMAGE
etcd-hw-minikube                      etcd                      registry.k8s.io/etcd:3.7.0-0
kube-apiserver-hw-minikube            kube-apiserver            registry.k8s.io/kube-apiserver:v1.37.0
kube-controller-manager-hw-minikube   kube-controller-manager   registry.k8s.io/kube-controller-manager:v1.37.0
kube-scheduler-hw-minikube            kube-scheduler            registry.k8s.io/kube-scheduler:v1.37.0

$ kubectl get daemonsets,deployments -n kube-system
NAME                        DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
daemonset.apps/kindnet      1         1         1       1            1           <none>                   63s
daemonset.apps/kube-proxy   1         1         1       1            1           kubernetes.io/os=linux   64s

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/coredns   1/1     1            1           64s

$ minikube -p hw-minikube ssh -- sudo ls /etc/kubernetes/manifests
etcd.yaml	     kube-controller-manager.yaml
kube-apiserver.yaml  kube-scheduler.yaml

$ minikube -p hw-minikube ssh -- "sudo systemctl is-active kubelet containerd; ps -eo comm | grep -E '^(kubelet|containerd|kube-apiserver|etcd|kube-scheduler|kube-controller|kube-proxy)' | sort | uniq"
active
active
containerd
containerd-shim
etcd
kube-apiserver
kube-controller
kube-proxy
kube-scheduler
kubelet
```

The API server's own flags show how it is wired to etcd and to the kubelets (trimmed):

```text
"--etcd-servers=https://127.0.0.1:2379"
"--etcd-certfile=/var/lib/minikube/certs/apiserver-etcd-client.crt"
"--kubelet-client-certificate=/var/lib/minikube/certs/apiserver-kubelet-client.crt"
"--authorization-mode=Node,RBAC"
```

**What I observed.**
- The four control-plane components are **static pods**: the kubelet starts them straight from the YAML files in `/etc/kubernetes/manifests`, before any API server exists. That is how the API server can run "as a pod" without needing itself to be scheduled.
- The **kubelet and containerd are not pods**. They are systemd services on the node (`systemctl is-active` says `active`), because they are what runs pods in the first place.
- **kube-proxy** and the CNI (**kindnet**) are DaemonSets, so every node gets one. **CoreDNS** is a normal Deployment.
- There is **no cloud-controller-manager**. That is expected on a laptop cluster. In session 11 I saw the consequence: a `LoadBalancer` Service stays `<pending>` until something else (MetalLB) plays the cloud's role.
- `crictl ps` on the node lists the same containers, which shows the kubelet really hands the pods to containerd.

## Task 4 - Basic objects and commands

| Object | What it is | Command I used |
|---|---|---|
| Namespace | A folder for objects; names must be unique inside one | `kubectl create namespace demo-ns`, `kubectl get ns` |
| Pod | Smallest deployable unit: one or more containers sharing network and volumes | `kubectl run hello-pod --image=nginx:1.27-alpine` |
| ReplicaSet | Keeps N identical pods running | created by the Deployment in Task 5 |
| Deployment | Manages ReplicaSets, which gives rolling updates and rollbacks | `kubectl create deployment ...` |
| Service | Stable virtual IP + DNS name in front of a set of pods | `kubectl expose deployment ...` |
| Label / selector | Key-value tags; selectors connect Services and controllers to pods | `kubectl label pods ...`, `-l version=v1` |

```text
$ kubectl api-resources --api-group=apps
NAME                  SHORTNAMES   APIVERSION   NAMESPACED   KIND
controllerrevisions                apps/v1      true         ControllerRevision
daemonsets            ds           apps/v1      true         DaemonSet
deployments           deploy       apps/v1      true         Deployment
replicasets           rs           apps/v1      true         ReplicaSet
statefulsets          sts          apps/v1      true         StatefulSet

$ kubectl run hello-pod --image=nginx:1.27-alpine --labels=app=hello --port=80
pod/hello-pod created

$ kubectl get pods -o wide --show-labels
NAME        READY   STATUS    RESTARTS   AGE   IP           NODE          ...   LABELS
hello-pod   1/1     Running   0          14s   10.244.0.3   hw-minikube   ...   app=hello

$ kubectl exec hello-pod -- nginx -v
nginx version: nginx/1.27.5
```

The full transcript also has `describe`, `logs`, `get -o yaml`, `explain` and the namespace commands. The everyday commands are:

```bash
kubectl get <kind> [-o wide|yaml|json] [-l key=value] [-A]
kubectl describe <kind> <name>        # status + events, first place to look when something is wrong
kubectl logs <pod> [-c container] [--previous]
kubectl exec -it <pod> -- sh
kubectl apply -f file.yaml / kubectl delete -f file.yaml
kubectl explain pod.spec.containers   # built-in API documentation
```

## Task 5 - Kubernetes Basics tutorial

I followed modules 2-6 of <https://kubernetes.io/docs/tutorials/kubernetes-basics/> on minikube. The tutorial image `gcr.io/google-samples/kubernetes-bootcamp` only exists for amd64 (its manifest has a single amd64 config), so on my arm64 Mac I used the multi-arch `registry.k8s.io/e2e-test-images/agnhost` image. In `netexec` mode it answers `/hostname` with the pod name, which does the same job as the bootcamp app's "Running on: <pod>" reply. For the update step I went from tag `2.39` to `2.40`, and for the bad update I used the non-existent tag `v10`, as the tutorial does.

### Module 2 - Create a Deployment

```text
$ kubectl create deployment kubernetes-bootcamp --image=registry.k8s.io/e2e-test-images/agnhost:2.39 -- /agnhost netexec --http-port=8080
deployment.apps/kubernetes-bootcamp created

$ kubectl get deployments
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
kubernetes-bootcamp   1/1     1            1           1s
```

### Module 3 - Explore the app

I started `kubectl proxy --port=8099` in the background and reached the pod through the API server, then looked at logs and the environment:

```text
$ curl -s http://localhost:8099/api/v1/namespaces/default/pods/kubernetes-bootcamp-99dc48984-nm6vc:8080/proxy/hostname
kubernetes-bootcamp-99dc48984-nm6vc

$ kubectl logs kubernetes-bootcamp-99dc48984-nm6vc --tail=5
I1007 16:33:21.350750       1 log.go:195] Started HTTP server on port 8080
I1007 16:33:21.352287       1 log.go:195] Started UDP server on port  8081
I1007 16:33:22.237329       1 log.go:195] GET /hostname
```

### Module 4 - Expose with a Service, use labels

```text
$ kubectl expose deployment/kubernetes-bootcamp --type=NodePort --port 8080
service/kubernetes-bootcamp exposed

$ kubectl get services
NAME                  TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
kubernetes            ClusterIP   10.96.0.1       <none>        443/TCP          10m
kubernetes-bootcamp   NodePort    10.100.25.184   <none>        8080:30448/TCP   0s

$ docker run --rm --network hw-minikube curlimages/curl:8.5.0 -sS http://192.168.49.2:30448/hostname
curl: (7) Failed to connect to 192.168.49.2 port 30448 after 0 ms: Couldn't connect to server

$ kubectl label pods kubernetes-bootcamp-99dc48984-nm6vc version=v1
pod/kubernetes-bootcamp-99dc48984-nm6vc labeled

$ kubectl get pods -l version=v1
NAME                                  READY   STATUS    RESTARTS   AGE
kubernetes-bootcamp-99dc48984-nm6vc   1/1     Running   0          5s
```

On macOS, the minikube node IP `192.168.49.2` is inside Docker Desktop's Linux VM and the Mac cannot route to it. So I tested the NodePort from a throwaway container on minikube's Docker network, which counts as "outside the cluster". That first request ran less than a second after `expose` and was refused, because kube-proxy had not written the rules for the new port yet. Every later request on the same NodePort worked (module 5 and module 6 below).

### Module 5 - Scale

```text
$ kubectl scale deployments/kubernetes-bootcamp --replicas=4
deployment.apps/kubernetes-bootcamp scaled

$ kubectl get pods -o wide        (trimmed)
kubernetes-bootcamp-99dc48984-l7k8b   1/1   Running   10.244.0.40
kubernetes-bootcamp-99dc48984-nm6vc   1/1   Running   10.244.0.39
kubernetes-bootcamp-99dc48984-p6rwh   1/1   Running   10.244.0.41
kubernetes-bootcamp-99dc48984-r2pc2   1/1   Running   10.244.0.42

$ kubectl get endpointslices -l kubernetes.io/service-name=kubernetes-bootcamp -o wide
NAME                        ADDRESSTYPE   PORTS   ENDPOINTS                             AGE
kubernetes-bootcamp-vhzcl   IPv4          8080    10.244.0.39,10.244.0.42,10.244.0.41   5s

$ docker exec hw-a-mk-client sh -c 'for i in $(seq 1 20); do curl -sS http://192.168.49.2:30448/hostname; echo; done | sort | uniq -c'
      4 kubernetes-bootcamp-99dc48984-l7k8b
      7 kubernetes-bootcamp-99dc48984-nm6vc
      9 kubernetes-bootcamp-99dc48984-p6rwh

$ kubectl scale deployments/kubernetes-bootcamp --replicas=2
```

**What I observed.** The Service spreads requests over the pods. Only 3 of the 4 pods answered. At that moment the EndpointSlice listed only 3 addresses (`.39`, `.42`, `.41`) even though all 4 pods showed `Running`, so the newest pod had not been added yet. Pod `.42` was in the slice but got none of the 20 requests; with random choice over 3 pods that can happen. It shows that `Running` and "receiving Service traffic" are not the same moment.

### Module 6 - Rolling update and rollback

```text
$ kubectl set image deployments/kubernetes-bootcamp agnhost=registry.k8s.io/e2e-test-images/agnhost:2.40
deployment.apps/kubernetes-bootcamp image updated

$ kubectl get rs
NAME                             DESIRED   CURRENT   READY   AGE
kubernetes-bootcamp-6f598bcf4d   2         2         2       7s
kubernetes-bootcamp-99dc48984    0         0         0       20s

$ kubectl set image deployments/kubernetes-bootcamp agnhost=registry.k8s.io/e2e-test-images/agnhost:v10
$ kubectl rollout status deployments/kubernetes-bootcamp --timeout=45s
error: timed out waiting for the condition

$ kubectl get pods
NAME                                   READY   STATUS             RESTARTS   AGE
kubernetes-bootcamp-6f598bcf4d-tsdrf   1/1     Running            0          52s
kubernetes-bootcamp-6f598bcf4d-xtll8   1/1     Running            0          54s
kubernetes-bootcamp-7c4fc9cb49-6hlwv   0/1     ImagePullBackOff   0          45s

  Warning  Failed  ...  Failed to pull image "registry.k8s.io/e2e-test-images/agnhost:v10": ... not found

$ kubectl rollout undo deployments/kubernetes-bootcamp
deployment.apps/kubernetes-bootcamp rolled back

$ kubectl get pods -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image,PHASE:.status.phase
NAME                                   IMAGE                                          PHASE
kubernetes-bootcamp-6f598bcf4d-tsdrf   registry.k8s.io/e2e-test-images/agnhost:2.40   Running
kubernetes-bootcamp-6f598bcf4d-xtll8   registry.k8s.io/e2e-test-images/agnhost:2.40   Running

$ kubectl rollout history deployment/kubernetes-bootcamp
REVISION  CHANGE-CAUSE
1         <none>
3         <none>
4         <none>
```

**What I observed.**
- An image change creates a **new ReplicaSet** (`6f598bcf4d`), and the old one is scaled to 0 but kept. That kept ReplicaSet is what makes rollback possible.
- With the bad tag, the Deployment created **one** new pod, which went into `ImagePullBackOff`, and stopped there. Both old pods kept running (`READY 2/2`), so the broken update caused no outage. The default `maxUnavailable: 25%` of 2 pods rounds down to 0.
- `rollout undo` went back to the 2.40 template. In the history, revision 2 turned into revision 4: an undo re-uses the old ReplicaSet under a new revision number.

## Why sessions 10-12 use kind instead of minikube

After the tutorial I deleted the profile (`minikube delete -p hw-minikube`, see `outputs/06-minikube-delete.txt`). For sessions 10, 11 and 12 I used a single-node **kind** cluster (`hw-a`) instead:

- kind is just one container running the node image, with no extra VM layer and no addon manager. It used about 650 MB of memory, and I needed that headroom because my Docker Desktop VM was shared and nearly full.
- Its config file can publish node ports on `localhost` (`extraPortMappings`). That made NodePort and Ingress reachable from my Mac without `minikube tunnel` or `minikube service`.
- It runs the same upstream Kubernetes (v1.37.0, kubeadm-based, the same static-pod control plane), so the architecture notes above apply to it unchanged.
