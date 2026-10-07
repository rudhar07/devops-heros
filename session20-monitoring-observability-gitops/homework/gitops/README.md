# Task 3: GitOps with Argo CD

**Name:** Rudhar Bajaj
**Environment:** kind `hw-e` (Kubernetes v1.37.0, arm64), Argo CD v3.5.4 (official non-HA `install.yaml`, server and CLI), throwaway Git server = `git daemon` in a container on the docker network `kind`

Every output block below is real output from commands I ran on 2026-10-07/08. Full transcripts are in [`../outputs/`](../outputs/) (files 08 to 16).

| File | What it is |
|---|---|
| [`app/`](app/) | the manifests I seeded the GitOps repo with (`namespace.yaml`, `deployment.yaml`, `service.yaml`, `configmap.yaml`), in their **initial** state. The later changes were made in the demo repo; the full diff history is in `outputs/16` |
| [`argocd-application.yaml`](argocd-application.yaml) | the Application I applied (auto-sync + selfHeal + prune) |
| [`argocd-cm-patch.yaml`](argocd-cm-patch.yaml) | lab-only change: poll Git every 30s instead of about 3 minutes |
| [`mini-project/`](mini-project/) | homework copy of `08-mini-project`: the instructor's 3 manifests unchanged, and `argocd-application.yaml` with only `repoURL` and `path` changed |

## 1. Concepts

**GitOps** means running infrastructure and apps by describing the desired state *declaratively* in Git, and letting an agent *inside the cluster* keep the live state equal to Git, all the time.

| Principle | Meaning | Where it shows up in my demo |
|---|---|---|
| **Declarative** | You describe *what* you want (`replicas: 4`), not the steps (`kubectl scale ...`) | the YAML in `app/` |
| **Git = source of truth** | The only way to change the system is a commit. Git gives versioning, review (PRs), an audit log (who, what, when) and rollback (`git revert`) | `git log` of the demo repo = the deploy history (`outputs/16`), and Argo CD history shows the same SHAs |
| **Pulled automatically** | An agent in the cluster *pulls* from Git. CI never needs cluster credentials (pull vs push model) | Argo CD's repo-server cloned `git://hw-e-gitd/gitops-demo-repo`; I never ran `kubectl apply` on `app/` |
| **Continuous reconciliation** | Loop: read desired (Git) → read actual (cluster) → diff → apply. It runs forever, not once per pipeline run | the Git change was applied within 27s, drift was reverted in about 3s, and a deleted file was pruned in 33s |

**GitOps workflow:**

```text
 dev edits YAML ──> git commit / PR / merge ──> Git (desired state)
                                                   │  Argo CD polls (or a webhook tells it)
                                                   v
                             Argo CD: render manifests → diff against live objects
                                   │ OutOfSync?                 │ live object edited by hand?
                                   v                            v
                             auto-sync (apply)            selfHeal (re-apply Git version)
                                   │ file removed from Git?
                                   v
                             prune (delete the live object)
                                                   │
                                                   v
                                         Kubernetes (actual state)
```

**Kubernetes + GitOps fit well together** because Kubernetes is already declarative and reconciles itself: a Deployment controller already turns "replicas: 4" into 4 pods. Argo CD adds one more loop on top: Git → API objects. The same idea one level up.

## 2. Setup

### Argo CD (non-HA, trimmed)

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd scale deploy argocd-dex-server argocd-notifications-controller argocd-applicationset-controller --replicas=0
kubectl -n argocd patch svc argocd-server -p '{"spec":{"type":"NodePort","ports":[{"name":"https","port":443,"targetPort":8080,"nodePort":30102}]}}'
```

Memory was tight, so I **scaled dex, notifications and applicationset to 0**. I log in as the local `admin` user (no SSO), I don't send notifications, and I don't use ApplicationSets. Four pods remained ([`outputs/08`](../outputs/08-argocd-install.txt)):

```text
pod/argocd-application-controller-0      1/1     Running   0          2m23s
pod/argocd-redis-bdbdffcb4-9tjwz         1/1     Running   0          2m24s
pod/argocd-repo-server-d89c7967d-4s6sd   1/1     Running   0          2m24s
pod/argocd-server-776b7cdd4d-tspbj       1/1     Running   0          2m23s
deployment.apps/argocd-applicationset-controller   0/0     0            0           2m24s
deployment.apps/argocd-dex-server                  0/0     0            0           2m24s
deployment.apps/argocd-notifications-controller    0/0     0            0           2m24s
```

Lab-only tuning ([`argocd-cm-patch.yaml`](argocd-cm-patch.yaml)): `timeout.reconciliation: 30s` and jitter `0s`, then I restarted the controller and repo-server. The default is to poll Git every 120s plus up to 60s of jitter. In production you'd keep the default and add a Git webhook.

### A Git server that doesn't need GitHub

The demo must not depend on the student's GitHub repo. So the "remote" is a throwaway repo at `<scratchpad>/gitops-demo-repo`, served by `git daemon` in a container attached to the docker network `kind`. That's the same network the kind node is on, so pods can reach it by container name ([`outputs/09`](../outputs/09-git-server.txt)):

```text
$ docker run -d --name hw-e-gitd --network kind -v <scratchpad>:/srv/git alpine:3.20 sh -c "... apk add git git-daemon ...; exec git -c safe.directory='*' daemon --verbose --reuseaddr --export-all --enable=receive-pack --base-path=/srv/git /srv/git"
$ docker logs hw-e-gitd
[13] Ready to rumble
$ docker exec hw-e-control-plane getent hosts hw-e-gitd
fc00:f853:ccd:e793::2 hw-e-gitd
$ kubectl run git-check --rm -i --restart=Never --image=alpine/git:latest --command -- git ls-remote git://hw-e-gitd/gitops-demo-repo
c404e4b5b5c5da0bb99fa7d294aacc423459bb4d	HEAD
c404e4b5b5c5da0bb99fa7d294aacc423459bb4d	refs/heads/main
```

Two things went wrong on the way, and I note them in the transcript header:

- `alpine/git` has no `git-daemon` binary (`git: 'daemon' is not a git command`), so I used plain alpine plus `apk add git-daemon`.
- One `apk` fetch hit a transient "temporary error", so the container retries.

Commits in this demo repo are made as `Rudhar Bajaj <rudharbajaj@gmail.com>`. It's a scratch repo, not the student repo.

### The Application ([`argocd-application.yaml`](argocd-application.yaml))

```yaml
spec:
  source:
    repoURL: git://hw-e-gitd/gitops-demo-repo
    targetRevision: main
    path: app
  destination:
    server: https://kubernetes.default.svc
    namespace: gitops-demo
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

As in the instructor's README, this file lives *outside* the watched `app/` path. I apply it once by hand. Everything under `app/` is applied only by Argo CD.

## 3. Demo

### 3.1 Login and initial sync ([`outputs/11`](../outputs/11-gitops-initial-sync.txt))

I logged in with the CLI. The password came from `argocd-initial-admin-secret` into a shell variable only, and the CLI session file went to the scratchpad via `--config`, not `~/.config/argocd`.

```text
$ argocd login localhost:8086 --insecure --username admin --password "$APW"
'admin:login' logged in successfully
$ argocd version --short
argocd: v3.5.4+d6d5b24.dirty
argocd-server: v3.5.4
$ argocd repo list
TYPE  NAME         REPO                              INSECURE  OCI    LFS    CREDS  STATUS      MESSAGE  PROJECT
git   gitops-demo  git://hw-e-gitd/gitops-demo-repo  false     false  false  false  Successful
$ kubectl apply -f gitops/argocd-application.yaml
application.argoproj.io/gitops-demo-web created
$ argocd app get gitops-demo-web
Sync Policy:        Automated (Prune)
Sync Status:        Synced to main (c404e4b)
Health Status:      Healthy

GROUP  KIND        NAMESPACE    NAME              STATUS  HEALTH   HOOK  MESSAGE
apps   Deployment  gitops-demo  web               Synced  Healthy        deployment.apps/web unchanged
       ConfigMap   gitops-demo  web-extra-config  Synced
       Namespace                gitops-demo       Synced
       Service     gitops-demo  web               Synced  Healthy
$ kubectl -n gitops-demo get deploy web -o jsonpath=...
nginx:1.27-alpine  [{"name":"APP_MESSAGE","value":"hello from git, version 1"}]
```

(The CLI prints `Automated (Prune)` and doesn't mention selfHeal. The Application spec does have both, as shown in 3.4.)

### 3.2 Change Git → Argo CD applies it, no kubectl ([`outputs/12`](../outputs/12-gitops-change-git.txt))

I made one commit: replicas 2→4, image `nginx:1.27-alpine`→`nginx:1.28-alpine`, env `version 1`→`version 2`. After that I only watched.

```text
$ git commit -am "Scale web to 4 replicas, bump nginx to 1.28, message v2"      # (in gitops-demo-repo)
[main 22f6509] Scale web to 4 replicas, bump nginx to 1.28, message v2
### Committed at 00:03:40. From here I only watch - no kubectl apply/scale/set image.
  00:03:40 +0s  deploy[spec ready image]=[2 2 nginx:1.27-alpine]  app=Synced/Healthy rev=c404e4b5b5c5da0bb99fa
  00:04:06 +26s  deploy[spec ready image]=[2 2 nginx:1.27-alpine]  app=Synced/Healthy rev=c404e4b5b5c5da0bb99fa
  00:04:11 +31s  deploy[spec ready image]=[4 3 nginx:1.28-alpine]  app=Synced/Progressing rev=22f6509f0044216f2
  00:04:31 +51s  deploy[spec ready image]=[4 4 nginx:1.28-alpine]  app=Synced/Healthy rev=22f6509f0044216f2b61d
$ kubectl -n gitops-demo get deploy web -o jsonpath='{...env}'
[{"name":"APP_MESSAGE","value":"hello from git, version 2"}]
$ argocd app history gitops-demo-web
ID      DATE                           REVISION
0       2026-10-07 23:57:09 +0530 IST  main (c404e4b)
1       2026-10-08 00:04:07 +0530 IST  main (22f6509)
```

**What I observed.**

- Argo CD picked up the commit on its next 30s poll: the sync started at 00:04:07, 27s after the commit.
- The Deployment did a normal rolling update. The events show `web-666699f9d5` scaling up 1→4 while `web-7fb865489c` scaled down to 0, and the app was `Progressing` until all 4 new pods were ready.
- The commit SHA is in both `git log` and `argocd app history`. That is the audit trail.
- Honest note: my first attempt at this step didn't commit at all. A zsh word-splitting bug in my script meant `git commit` never ran, so nothing synced for 5 minutes, which is correct behaviour since Git hadn't changed. I reset the uncommitted edit and re-ran the step as a bash script. The transcript is from the re-run.

### 3.3 Drift → selfHeal reverts it ([`outputs/13`](../outputs/13-gitops-drift-selfheal.txt))

```text
$ kubectl -n gitops-demo scale deploy web --replicas=1
deployment.apps/web scaled
$ kubectl -n gitops-demo set env deploy/web APP_MESSAGE=edited by hand with kubectl
deployment.apps/web env updated
  00:04:45 +1s  deploy[spec ready APP_MESSAGE]=[1 1 edited by hand with kubectl]  app=Synced/Healthy
  00:04:47 +3s  deploy[spec ready APP_MESSAGE]=[4 3 hello from git, version 2]  app=Synced/Progressing
  00:04:49 +5s  deploy[spec ready APP_MESSAGE]=[4 4 hello from git, version 2]  app=Synced/Healthy
$ kubectl -n argocd get application gitops-demo-web -o jsonpath='{.status.operationState...}'
{"automated":true}
Succeeded  successfully synced (all tasks run)
2026-10-07T18:34:45Z
controller log: "Initiated automated sync to '22f6509f...'" at 18:34:45Z, Resources:[...{Group:apps,Kind:Deployment,Name:web}]
```

**What I observed.**

- Self-heal doesn't wait for the Git poll. The controller watches the live objects, so the change was reverted in about 2 seconds: replicas back to 4, env back to "version 2".
- The self-heal sync only touched the one drifted resource (`Resources:[... Kind:Deployment, Name:web]`).
- `app history` didn't get a new entry, because the revision (22f6509) didn't change. History records *Git revisions deployed*, not every self-heal.
- The status poll never caught `OutOfSync`: the window was shorter than my 2s poll.
- The lesson: with selfHeal on, `kubectl edit` in production is pointless. The only way to change the app is a commit.

### 3.4 Prune: delete a manifest from Git → resource removed ([`outputs/14`](../outputs/14-gitops-prune.txt))

```text
$ kubectl -n argocd get application gitops-demo-web -o jsonpath={.spec.syncPolicy}
{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}
$ git rm -q app/configmap.yaml      # (in gitops-demo-repo)
$ git commit -m "Remove web-extra-config ConfigMap"
[main 3cbdbbc] Remove web-extra-config ConfigMap
 1 file changed, 8 deletions(-)
  00:05:04 +0s  configmap=[configmap/web-extra-config]  app=Synced/Healthy rev=22f6509f0044216f2b61d
  00:05:35 +31s  configmap=[configmap/web-extra-config]  app=Synced/Healthy rev=22f6509f0044216f2b61d
  00:05:40 +36s  configmap=[Error from server (NotFound): configmaps "web-extra-config" not found]  app=Synced/Healthy rev=3cbdbbc65bc6a8a8118d0
$ kubectl -n argocd get application gitops-demo-web -o jsonpath={...syncResult.resources...}
ConfigMap/web-extra-config: Pruned pruned
Namespace/gitops-demo: Synced namespace/gitops-demo unchanged
Service/web: Synced service/web unchanged
Deployment/web: Synced deployment.apps/web unchanged
$ argocd app history gitops-demo-web
ID      DATE                           REVISION
0       2026-10-07 23:57:09 +0530 IST  main (c404e4b)
1       2026-10-08 00:04:07 +0530 IST  main (22f6509)
2       2026-10-08 00:05:37 +0530 IST  main (3cbdbbc)
```

Application status, trimmed to the relevant fields:

```text
sync: {"status": "Synced", "revision": "3cbdbbc65bc6a8a8118d032232c1438219af3702"}
health: Healthy
history:
  - {"id": 0, "revision": "c404e4b", "deployedAt": "2026-10-07T18:27:09Z", "initiatedBy": {"automated": true}}
  - {"id": 1, "revision": "22f6509", "deployedAt": "2026-10-07T18:34:07Z", "initiatedBy": {"automated": true}}
  - {"id": 2, "revision": "3cbdbbc", "deployedAt": "2026-10-07T18:35:37Z", "initiatedBy": {"automated": true}}
last operation: {"phase": "Succeeded", "message": "successfully synced (all tasks run)", "initiatedBy": {"automated": true}, "prune": true, ...}
```

**What I observed.** With `prune: false`, the ConfigMap would have stayed in the cluster as an orphan, and Argo CD would only have flagged it with "requires pruning". Prune is what makes "delete the file" really mean "delete the thing". All three deployments in the history were `initiatedBy: automated`: I never clicked Sync or ran `argocd app sync`.

## 4. Instructor's 08-mini-project ([`outputs/15`](../outputs/15-mini-project.txt))

This works with the local repo approach. The demo repo has a `mini/` folder holding the instructor's `namespace.yaml`, `deployment.yaml` and `service.yaml`, unchanged. The homework copy of `argocd-application.yaml` changes only two lines:

```text
$ diff 08-mini-project/app/argocd-application.yaml homework/gitops/mini-project/argocd-application.yaml
<     repoURL: https://github.com/YOUR_USERNAME/YOUR_GITOPS_REPO.git
>     repoURL: git://hw-e-gitd/gitops-demo-repo   # was https://github.com/YOUR_USERNAME/YOUR_GITOPS_REPO.git
<     path: app
>     path: mini   # in the demo repo the mini-project manifests live in mini/
```

Steps 1 and 2 (cluster, Argo CD) were already done above. Step 3/4 is the repo, steps 5 to 9 are below:

```text
### Step 5
$ kubectl get applications -n argocd
NAME              SYNC STATUS   HEALTH STATUS
gitops-demo-web   Synced        Healthy
session20-mini    Synced        Healthy
### Step 6
$ kubectl get all -n session20      (trimmed)
pod/session20-mini-68946db7dd-tcczj   1/1     Running   0          2s
pod/session20-mini-68946db7dd-zfqtk   1/1     Running   0          2s
service/session20-mini   ClusterIP   10.96.12.74   <none>        80/TCP    2s
deployment.apps/session20-mini   2/2     2            2           2s
### Step 7: git commit -am "Scale application to three replicas"  -> [main a6fa12c]
  00:06:05 +0s  session20-mini spec/ready=2/2  app=Synced/Healthy rev=3cbdbbc65bc6a8a8118d0
  00:06:40 +35s  session20-mini spec/ready=3/3  app=Synced/Healthy rev=a6fa12c80a177f925d502
### Step 8
$ kubectl scale deployment session20-mini -n session20 --replicas=1
  00:06:41 +0s  session20-mini spec/ready=1/3  app=Synced/Healthy
  00:06:43 +2s  session20-mini spec/ready=3/3  app=Synced/Healthy
### Step 9
$ kubectl logs deployment/session20-mini -n session20 --tail=5      (trimmed)
2026/10/07 18:36:04 [notice] 1#1: start worker process 44
$ argocd app history session20-mini
ID      DATE                           REVISION
0       2026-10-08 00:06:03 +0530 IST  main (3cbdbbc)
1       2026-10-08 00:06:37 +0530 IST  main (a6fa12c)
```

**Cleanup surprise.** The mini-project README says to delete the Application to clean up. I did, and the workload **stayed**:

```text
$ kubectl delete -f .../mini-project/argocd-application.yaml
application.argoproj.io "session20-mini" deleted from argocd namespace
$ kubectl get all -n session20      (trimmed)
deployment.apps/session20-mini   3/3     3            3           41s
```

That's because the Application has no `resources-finalizer.argocd.argoproj.io` finalizer, so Argo CD only forgets about the app and doesn't cascade-delete it. To get cascading delete, add `metadata.finalizers: [resources-finalizer.argocd.argoproj.io]`, or use `argocd app delete --cascade`. I removed the namespace by hand.

### Viva answers (short, my own words)

1. **Monitoring vs observability:** monitoring = alerts and dashboards for problems you predicted; observability = enough data to work out problems you didn't predict.
2. **Metrics vs logs vs traces:** numbers over time / individual events / one request's path through services.
3. **Prometheus:** pulls `/metrics` from targets on a schedule, stores time series, answers PromQL, evaluates alert rules.
4. **Grafana:** UI that queries datasources (Prometheus, Loki, Tempo...) for dashboards and exploration.
5. **GitOps:** the desired state lives in Git, and an in-cluster agent keeps the cluster equal to it.
6. **Git is the source of truth** because every change goes through a commit: it's versioned, reviewed, auditable and revertible, and anything not in Git gets overwritten.
7. **Argo CD:** renders manifests from Git, diffs them against the live cluster, syncs, self-heals, prunes, and shows status and history.
8. **Desired state:** what Git says (`replicas: 3`).
9. **Actual state:** what's really in the cluster right now (`kubectl get` shows 1 after my manual scale).
10. **Reconciliation:** the loop that compares the two and acts to make actual = desired.
11. **Self-healing:** Argo CD undoes manual changes to managed objects; my `--replicas=1` was back to 3 in 2s.
12. **Replicas 2 → 3 in Git:** Argo CD sees a new commit on its next poll, the app goes OutOfSync, it applies the new Deployment spec, the ReplicaSet creates 1 pod, and the app is Synced/Healthy at 3/3. That took 35s in my run.

## 5. Differences from a real setup

| Here | Real setup |
|---|---|
| `git daemon` with no auth, on the docker network | GitHub/GitLab over HTTPS/SSH with a deploy key or token stored as an Argo CD repo secret |
| poll every 30s | default 3 min poll plus a webhook from the Git host for instant sync |
| commits straight to `main` | PR + review + CI checks (lint, kubeconform, policy) before merge |
| image tags changed by hand | CI builds the image and bumps the tag in Git (or Argo CD Image Updater) |
| dex, notifications, ApplicationSet scaled to 0 | SSO via dex/OIDC, Slack notifications, ApplicationSets for many apps/clusters |

Cleanup: the `hw-e-gitd` container was removed and the kind cluster deleted ([`outputs/18`](../outputs/18-cleanup.txt)).
