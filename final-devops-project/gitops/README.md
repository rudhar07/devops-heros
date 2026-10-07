# gitops/ - ArgoCD

| File | Purpose |
|---|---|
| `argocd-application.yaml` | **The real one.** Watches `https://github.com/rudhar07/devops-heros.git`, branch `main`, path `final-devops-project/helm/taskboard`, values `values-gitops.yaml`. Auto-sync with `prune` + `selfHeal`, creates namespace `taskboard-gitops`. |
| `argocd-application-local-demo.yaml` | What I ran locally: same chart path, but the repo is a throw-away `git daemon` container (`git://hw-f-gitd/final-gitops-repo`) and the images are the locally built `taskboard-*:local`. |

## The loop

```
developer edits helm/taskboard/values-gitops.yaml  ->  git commit + push
        -> ArgoCD notices the new commit (poll every 3 min, or webhook / "argocd app get --refresh")
        -> renders the Helm chart, diffs it against the cluster, applies only the differences
someone runs kubectl scale/patch by hand  ->  selfHeal re-applies Git within seconds
```

## Using the real Application after the push

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.4/manifests/install.yaml
kubectl apply -f final-devops-project/gitops/argocd-application.yaml
```

The images come from GHCR (`ghcr.io/rudhar07/devops-heros/taskboard-*`), pushed by the CI on `main`
with two tags: the commit SHA and the chart `appVersion` (`2.0.0`). An empty tag in
`values-gitops.yaml` means `appVersion`. To roll out one exact build, commit its SHA as the tag;
that commit is the deployment record. GHCR packages are private by default, so either make the two
packages public (package settings -> visibility) or add an `imagePullSecrets` entry.

Live run (sync, Git change applied, drift healed): `../outputs/21-argocd-install.txt`, `../outputs/22-gitops.txt`.
