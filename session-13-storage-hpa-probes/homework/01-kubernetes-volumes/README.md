# Kubernetes Volumes - emptyDir, hostPath, PV, PVC, StorageClass

**Name:** Rudhar Bajaj
**Cluster:** kind v0.33.0, single node `hw-b`, Kubernetes v1.37.0, default StorageClass `standard` (rancher.io/local-path)

Every output below is real and comes from the transcripts in `../outputs/` (01 to 04). I trimmed long
`describe` output and say where.

## Why volumes exist

A container's filesystem is thrown away when the container is replaced. Anything the app writes
(uploads, a database file, a cache) is gone after a restart or a reschedule. A volume is a directory
that Kubernetes mounts into the container and that has its own lifetime, separate from the container.
The type of volume decides how long that lifetime is.

| Type | Lives as long as | Where the data is | Shared between | Typical use |
|---|---|---|---|---|
| `emptyDir` | the Pod | node disk (or RAM with `medium: Memory`) under `/var/lib/kubelet/pods/<uid>/` | containers in the same Pod | scratch space, cache, sidecar hand-off |
| `hostPath` | the node | a fixed path on the node | every Pod on that node that mounts the path | node agents (log collectors, CNI), single-node demos |
| PersistentVolume (PV) | until an admin (or the reclaim policy) deletes it | whatever backs it: NFS, EBS, local disk, ... | Pods via a PVC | real app data |
| PersistentVolumeClaim (PVC) | until you delete it | it is a request, it binds to one PV | Pods in its namespace | what a Pod actually references |
| StorageClass | cluster object | describes a provisioner + parameters | n/a | creates PVs on demand (dynamic provisioning) |

## 1. emptyDir

An `emptyDir` is created empty when the Pod is scheduled and deleted when the Pod is deleted. A
container restart does not wipe it, but deleting the Pod does.

Files: `../../01-volumes/emptydir-pod.yaml` (instructor) and my `emptydir-shared.yaml`.

**Part A - lifetime.** I wrote a file, found it on the node under the Pod's UID, then deleted the Pod:

```text
$ kubectl exec emptydir-demo -- sh -c echo "temp data" > /data/file.txt; ls -l /data; cat /data/file.txt
-rw-r--r-- 1 root root 10 Oct  7 16:25 file.txt
temp data

$ docker exec hw-b-control-plane ls -l /var/lib/kubelet/pods/c7e16e9f-fba8-4660-ae9e-083631945b45/volumes/kubernetes.io~empty-dir/app-storage
-rw-r--r-- 1 root root 10 Oct  7 16:25 file.txt

$ kubectl delete pod emptydir-demo
$ kubectl apply -f ../01-volumes/emptydir-pod.yaml
$ kubectl exec emptydir-demo -- ls -la /data
total 8
drwxrwxrwx 2 root root 4096 Oct  7 16:25 .
drwxr-xr-x 1 root root 4096 Oct  7 16:25 ..

$ docker exec hw-b-control-plane ls /var/lib/kubelet/pods/c7e16e9f-fba8-4660-ae9e-083631945b45
ls: cannot access '/var/lib/kubelet/pods/c7e16e9f-...': No such file or directory
```

**Part B - shared between two containers.** `emptydir-shared.yaml` has a busybox `writer` that appends
a line every 5 s to `/shared/index.html`, and an nginx `web` container that mounts the same volume at
`/usr/share/nginx/html`:

```yaml
# abridged from emptydir-shared.yaml (same content, compact form)
containers:
  - name: writer
    image: busybox:1.36
    command: ["sh", "-c", "while true; do echo \"written by writer at $(date)\" >> /shared/index.html; sleep 5; done"]
    volumeMounts: [{ name: shared, mountPath: /shared }]
  - name: web
    image: nginx:1.27
    volumeMounts: [{ name: shared, mountPath: /usr/share/nginx/html }]
volumes:
  - name: shared
    emptyDir: {}
```

```text
$ kubectl get pod emptydir-shared
NAME              READY   STATUS    RESTARTS   AGE
emptydir-shared   2/2     Running   0          6s

$ kubectl exec emptydir-shared -c web -- curl -s http://localhost/
written by writer at Wed Oct  7 16:25:35 UTC 2026
written by writer at Wed Oct  7 16:25:40 UTC 2026
written by writer at Wed Oct  7 16:25:45 UTC 2026
```

**What I saw:** the file the busybox container wrote was served by nginx, which never wrote it. The
data was under the Pod UID on the node, and that directory disappeared with the Pod.

## 2. hostPath

`hostPath` mounts a directory of the node into the Pod. The data outlives the Pod, but it is tied to
that one node. If the Pod moves to another node it sees a different (empty) directory. It also gives
the Pod access to the node's filesystem, which is a security risk, so it is usually blocked by Pod
Security "restricted"/"baseline".

File: `../../01-volumes/hostpath-pod.yaml` (`path: /tmp/hostpath-data`, `type: DirectoryOrCreate`).

```text
$ kubectl exec hostpath-demo -- sh -c echo "written from pod at $(date)" > /data/note.txt; cat /data/note.txt
written from pod at Wed Oct  7 16:26:24 UTC 2026

$ docker exec hw-b-control-plane cat /tmp/hostpath-data/note.txt
written from pod at Wed Oct  7 16:26:24 UTC 2026

$ kubectl delete pod hostpath-demo
$ kubectl apply -f ../01-volumes/hostpath-pod.yaml
$ kubectl exec hostpath-demo -- cat /data/note.txt
written from pod at Wed Oct  7 16:26:24 UTC 2026
```

**What I saw:** the "node" in kind is a Docker container, so `docker exec hw-b-control-plane` is the
same as SSH-ing to a node. The file was there, and a brand-new Pod read it back.

## 3. PersistentVolume + PersistentVolumeClaim (static provisioning)

- **PV** = a piece of storage that exists in the cluster (created by an admin here). It has a
  capacity, access modes (`ReadWriteOnce`, `ReadOnlyMany`, `ReadWriteMany`, `ReadWriteOncePod`) and a
  reclaim policy (`Retain` or `Delete`).
- **PVC** = a request for storage ("500Mi, RWO"). Kubernetes binds it to a matching PV. The Pod only
  knows the PVC name, so the app YAML doesn't care what the storage really is.

Files: `../../02-persistent-storage/pv.yaml` (1Gi, RWO, Retain, hostPath `/tmp/student-data`),
`../../02-persistent-storage/pvc.yaml`, `../../02-persistent-storage/pod.yaml`, and my `static-pvc.yaml`.

**A gotcha I hit on kind.** With the instructor's PVC as it is, it did not bind to `student-pv`:

```text
$ kubectl get pv,pvc
NAME                          CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS
persistentvolume/student-pv   1Gi        RWO            Retain           Available
NAME                                STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
persistentvolumeclaim/student-pvc   Pending                                      standard

$ kubectl describe pvc student-pvc      (trimmed)
StorageClass:  standard
Events:
  Normal  WaitForFirstConsumer  1s    persistentvolume-controller  waiting for first consumer to be created before binding
```

The PVC has no `storageClassName`, so the DefaultStorageClass admission plugin filled in `standard`.
The PV has no class (empty string). A PVC only binds to a PV of the same class, so this PVC would have
got a new dynamically provisioned volume instead of the PV I made. Fix in my copy `static-pvc.yaml`:

```yaml
# excerpt of static-pvc.yaml, comments added here
spec:
  storageClassName: ""      # "no class" - opt out of the default StorageClass
  volumeName: student-pv    # optional, pins it to this PV
```

```text
$ kubectl apply -f 01-kubernetes-volumes/static-pvc.yaml
$ kubectl get pv,pvc
NAME                          CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                 STORAGECLASS
persistentvolume/student-pv   1Gi        RWO            Retain           Bound    default/student-pvc
NAME                                STATUS   VOLUME       CAPACITY   ACCESS MODES   STORAGECLASS
persistentvolumeclaim/student-pvc   Bound    student-pv   1Gi        RWO
```

The PVC asked for 500Mi but shows 1Gi: it got the whole PV.

**Data survives Pod deletion:**

```text
$ kubectl exec storage-demo -- sh -c echo "Rudhar - data on a static PV" > /data/student.txt; cat /data/student.txt
Rudhar - data on a static PV
$ kubectl delete pod storage-demo
$ kubectl apply -f ../02-persistent-storage/pod.yaml
$ kubectl exec storage-demo -- cat /data/student.txt
Rudhar - data on a static PV
```

**Reclaim policy Retain:** deleting the PVC does not delete the PV or the data. The PV becomes
`Released` and can't be bound again until an admin cleans it up:

```text
$ kubectl delete pvc student-pvc
$ kubectl get pv student-pv
NAME         CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS     CLAIM
student-pv   1Gi        RWO            Retain           Released   default/student-pvc
$ docker exec hw-b-control-plane cat /tmp/student-data/student.txt
Rudhar - data on a static PV
```

## 4. StorageClass and dynamic provisioning

Making PVs by hand doesn't scale. A **StorageClass** names a provisioner. When a PVC asks for that
class, the provisioner creates the PV for it. kind ships one:

```text
$ kubectl get storageclass
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false
```

| Field | Value on kind | Meaning |
|---|---|---|
| `provisioner` | `rancher.io/local-path` | creates a directory under `/var/local-path-provisioner/` on the node |
| `reclaimPolicy` | `Delete` | delete the PV (and the data) when the PVC is deleted |
| `volumeBindingMode` | `WaitForFirstConsumer` | don't create the PV until a Pod using the PVC is scheduled, so the volume ends up on the Pod's node |
| `is-default-class` annotation | `true` | PVCs without `storageClassName` get this class |

On a cloud this would be e.g. `ebs.csi.aws.com` with `type: gp3`. The YAML for the app stays the same.

Files: `../../03-storageclass/pvc.yaml` (`dynamic-pvc`, `storageClassName: standard`, 500Mi) and my
`dynamic-pod.yaml` which mounts it.

```text
$ kubectl get pv
No resources found

$ kubectl apply -f ../03-storageclass/pvc.yaml
$ kubectl get pvc dynamic-pvc
NAME          STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
dynamic-pvc   Pending                                      standard

$ kubectl apply -f 01-kubernetes-volumes/dynamic-pod.yaml
$ kubectl get pvc dynamic-pvc
NAME          STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
dynamic-pvc   Bound    pvc-ba4558a4-7935-49ff-ae76-6c7abeba4a87   500Mi      RWO            standard

$ kubectl get pv
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                 STORAGECLASS
pvc-ba4558a4-7935-49ff-ae76-6c7abeba4a87   500Mi      RWO            Delete           Bound    default/dynamic-pvc   standard

$ kubectl get events --field-selector involvedObject.name=dynamic-pvc     (LAST SEEN/OBJECT columns trimmed)
Normal   WaitForFirstConsumer    waiting for first consumer to be created before binding
Normal   ExternalProvisioning    Waiting for a volume to be created either by the external provisioner 'rancher.io/local-path' ...
Normal   Provisioning            External provisioner is provisioning volume for claim "default/dynamic-pvc"
Normal   ProvisioningSucceeded   Successfully provisioned volume pvc-ba4558a4-7935-49ff-ae76-6c7abeba4a87

$ kubectl describe pv pvc-ba4558a4-...   (trimmed)
Annotations:       pv.kubernetes.io/provisioned-by: rancher.io/local-path
Node Affinity:     kubernetes.io/hostname in [hw-b-control-plane]
Source:
    Type:          HostPath (bare host directory volume)
    Path:          /var/local-path-provisioner/pvc-ba4558a4-7935-49ff-ae76-6c7abeba4a87_default_dynamic-pvc

$ kubectl exec dynamic-demo -- cat /data/hello.txt
hello from a dynamically provisioned volume

$ kubectl delete pod dynamic-demo
$ kubectl delete pvc dynamic-pvc
$ kubectl wait --for=delete pv/pvc-ba4558a4-7935-49ff-ae76-6c7abeba4a87 --timeout=60s
persistentvolume/pvc-ba4558a4-7935-49ff-ae76-6c7abeba4a87 condition met
```

**What I saw:** I never wrote a PV. The PVC stayed `Pending` until the Pod existed (that's
`WaitForFirstConsumer`, not an error), then a PV named `pvc-<uid>` appeared with node affinity to my
node. Because the class's reclaim policy is `Delete`, removing the PVC removed the PV too. Compare
with the static `Retain` PV above, which stayed as `Released`.

## Static vs dynamic, in one table

| | Static (section 3) | Dynamic (section 4) |
|---|---|---|
| Who creates the PV | admin, by hand | the provisioner named in the StorageClass |
| PVC `storageClassName` | `""` (must match the PV) | `standard` (or omitted, if it's the default) |
| PV name | `student-pv` | `pvc-ba4558a4-...` |
| Reclaim policy here | `Retain` -> PV `Released`, data kept | `Delete` -> PV and data removed |
| Bound when | as soon as the PVC is created | when the first Pod using it is scheduled |
