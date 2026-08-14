# Agent notes

Helm charts for self-hosted apps. One chart per app under `charts/<name>/`. Style reference: `charts/dawarich` and `charts/yamtrack`. Prefer yamtrack’s fail-fast / least-privilege over dawarich’s looser defaults.

## Chart conventions

- No bundled Redis/Postgres (Bitnami or otherwise). External only.
- `config` → ConfigMap (non-secrets). Fail if `SECRET`, `REDIS_URL`, `CELERY_REDIS_URL`, `DB_PASSWORD` land in `config`.
- Secrets via chart Secret, `existingSecret`, or `extraEnv` `valueFrom`.
- Renovate: `# renovate datasource=docker depName=<image>` above `appVersion` in `Chart.yaml`.
- `kubeVersion` must match APIs used (`fsGroupChangePolicy` needs 1.23+).

## Pitfalls

### Helm test vs NetworkPolicy

Test pod **must not** use `selectorLabels` (`app.kubernetes.io/name` + `instance`). NP selects those labels → test egress to the app is denied. Use `app.kubernetes.io/component: test` only. Add `helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded`.

### Django/app SECRET generation

`lookup` + `randAlphaNum` is fine on **install**. On **upgrade**, if lookup misses, **fail** — do not rotate. Do not `checksum` the secret template (`include` of `secret.yaml` re-rolls `randAlphaNum` and forces extra Recreate).

### PVCs

Helm 3 **deletes** chart-created PVCs on uninstall. Default SQLite/data volumes need `helm.sh/resource-policy: keep`. Cleanup after cluster tests must `kubectl delete pvc` (and the PV) explicitly. Do not document “Helm leaves PVCs” without that annotation.

### Ports

Image listen port ≠ `service.port`. Hardcode `containerPort` / NP / probes to the image port (Yamtrack: 8000). `service.port` is the Service only.

### RWO

`ReadWriteOnce` + `replicaCount > 1` deadlocks. Require `Recreate` (not RollingUpdate). Fail-fast in templates.

### Official images that start as root

linuxserver-style `PUID`/`entrypoint` + supervisord/nginx as root: do **not** set `runAsNonRoot` / `readOnlyRootFilesystem`. Drop `ALL`, add only what entrypoint needs (`CHOWN`, `SETUID`, `SETGID`, `FOWNER`, `DAC_OVERRIDE`). `automountServiceAccountToken: false` unless the app talks to the API. Set `terminationGracePeriodSeconds` above Celery/supervisord `stopwaitsecs` (Yamtrack: 70).

### NetworkPolicy

- Disabled by default.
- DNS: `kube-system` + `k8s-app: kube-dns`. Never `namespaceSelector: {}`.
- Redis (and Postgres if enabled) need `podSelector`; fail if missing.
- `extraIngress` = `ingress.from` peers on the **same** rule. Empty = allow-all. Do not append sibling rules or raw selectors without `from`.
- Helm test labels (above) or NP will break `helm test`.

## Verify

`helm lint`, `helm template` of fail paths, `kubectl apply --dry-run=client`, then install + `helm test`. Loop a review subagent until PASS. Unique test NS; uninstall + delete keep-PVCs + delete NS.
