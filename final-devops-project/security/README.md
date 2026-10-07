# security/

| File | Tool | Used for |
|---|---|---|
| `bandit.yaml` | Bandit 1.9.4 | SAST config: scan `application/backend/app`, tests excluded (they use `assert`), no checks skipped |
| `.gitleaks.toml` | Gitleaks 8.30.1 | Default rules + allowlist for generated files (lockfile, node_modules, dist, .terraform) + the one fake Grafana demo password (exact value) |
| `trivy.yaml` | Trivy 0.75.0 | Shared gate settings: HIGH,CRITICAL, exit code 1, ignore-unfixed, skip the deliberately broken `troubleshooting/` files |
| `.trivyignore` | Trivy | Two accepted IaC findings, each with a written reason |
| `reports/bandit.json`, `reports/pip-audit.json` | | Reports from my local run (both clean) |

Full Trivy JSON reports are gitignored (about 1 MB); the summaries are in `../outputs/06-trivy-image.txt`.

Gates in `.github/workflows/session21-final.yml` (any failure stops the push and the deploy):

| Layer | Job | Fails on |
|---|---|---|
| SAST | `sast` | Bandit MEDIUM+ severity with MEDIUM+ confidence |
| SCA (Python) | `sca` | any known vulnerability (pip-audit `--strict`) |
| SCA (npm) | `frontend-build` | `npm audit --audit-level=high` |
| SCA (lockfiles) | `sca` | Trivy fs HIGH/CRITICAL |
| Secrets | `secret-scan` | any Gitleaks finding in `final-devops-project/` (files and git history) |
| IaC / manifests | `iac-scan` | Trivy config HIGH/CRITICAL (Dockerfiles, k8s YAML, Helm, Terraform) |
| Images | `image-scan` | fixable HIGH/CRITICAL in either image |
| All of the above | `security-gate` | any needed job not `success` |
