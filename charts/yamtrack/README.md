# Yamtrack Helm Chart

Helm chart for [Yamtrack](https://github.com/FuzzyGrim/Yamtrack), a self-hosted media tracker.

## Prerequisites

- Kubernetes 1.23+
- Helm 3+
- **External Redis 6+** (required; cache and Celery)
- StorageClass for the SQLite PVC, or an existing claim
- Optional: external PostgreSQL 12+ (otherwise SQLite on the data volume)

This chart does **not** bundle Redis or PostgreSQL.

## Install

```bash
helm install yamtrack ./charts/yamtrack \
  --set redis.url='redis://yamtrack-redis:6379'
```

Behind a reverse proxy, set the public origin (protocol + host, no trailing slash):

```yaml
config:
  URLS: "https://yamtrack.example.com"
  REGISTRATION: "true"

redis:
  url: "redis://yamtrack-redis:6379"
  # or:
  # existingSecret: yamtrack-redis
  # existingSecretKey: url

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: yamtrack.example.com
      paths:
        - path: /
          pathType: Prefix
```

Create the first user in the UI, then set `config.REGISTRATION: "false"`.

## Configuration

### Static settings (`config` → ConfigMap)

Non-secret env vars. Common keys:

| Key | Default | Notes |
| --- | --- | --- |
| `TZ` | `UTC` | Timezone |
| `REGISTRATION` | `true` | Public sign-up. Set `false` after first user |
| `WEB_CONCURRENCY` | `1` | Gunicorn workers |
| `PUID` / `PGID` | `1000` | Must match `podSecurityContext.fsGroup` |
| `URLS` | unset | Public origins (`https://host`). Required behind a proxy |
| `ALLOWED_HOSTS` | app default `*` | Optional override |
| `CSRF` | unset | Optional; `URLS` covers this |
| `BASE_URL` | unset | Subpath, e.g. `/yamtrack` (no trailing slash) |
| `ADMIN_ENABLED` | app default `false` | Django admin |
| `REDIS_PREFIX` | unset | Isolate keys on a shared Redis |
| `HEALTHCHECK_CELERY_PING_TIMEOUT` | app default `1` | Raise if `/health/` flakes |

Full list: [Environment Variables](https://github.com/FuzzyGrim/Yamtrack/wiki/Environment-Variables).

### Django `SECRET`

Default: chart creates a Secret with a random value and **reuses it on upgrade**.

```yaml
secret:
  create: true
  value: ""          # empty = generate
  existingSecret: "" # set to use your own
  existingSecretKey: SECRET
```

Do not rotate `SECRET` after users exist (sessions/tokens break). To use a pre-created secret:

```bash
kubectl create secret generic yamtrack-secret \
  --from-literal=SECRET="$(openssl rand -hex 32)"
```

```yaml
secret:
  create: false
  existingSecret: yamtrack-secret
```

### Redis (required)

```yaml
redis:
  url: "redis://:password@redis-host:6379"
```

Prefer a secret in production:

```yaml
redis:
  existingSecret: yamtrack-redis
  existingSecretKey: url
```

```bash
kubectl create secret generic yamtrack-redis \
  --from-literal=url='redis://:password@redis-host:6379'
```

Example Redis (not production-hardened):

```bash
helm repo add cloudpirates https://cloudpirates-io.github.io/helm-charts
helm install yamtrack-redis cloudpirates/redis
```

### Database

**SQLite (default).** Data lives on the PVC at `/yamtrack/db`. Keep `replicaCount: 1` and `updateStrategy.type: Recreate` with `ReadWriteOnce`.

**PostgreSQL:**

```yaml
postgresql:
  enabled: true
  host: postgres-host
  port: 5432
  database: yamtrack
  user: yamtrack
  existingSecret: yamtrack-postgres
  existingSecretPasswordKey: password
  extraConfig:
    DB_SSL_MODE: require
```

```bash
kubectl create secret generic yamtrack-postgres \
  --from-literal=password='...'
```

### API keys and other secrets

Default keys are built into Yamtrack. Override via `extraEnv`:

```yaml
extraEnv:
  - name: TMDB_API
    valueFrom:
      secretKeyRef:
        name: yamtrack-apis
        key: tmdb
  - name: MAL_API
    valueFrom:
      secretKeyRef:
        name: yamtrack-apis
        key: mal
```

### Persistence

| Key | Default | Notes |
| --- | --- | --- |
| `persistence.enabled` | `true` | `false` uses emptyDir (ephemeral) |
| `persistence.size` | `1Gi` | SQLite + local files |
| `persistence.storageClass` | `""` | Empty = cluster default. `-` = none |
| `persistence.existingClaim` | `""` | Use an existing PVC |
| `persistence.accessMode` | `ReadWriteOnce` | `replicaCount > 1` needs `ReadWriteMany` |
| `persistence.annotations` | `helm.sh/resource-policy: keep` | Chart-created PVC is kept on uninstall |

The image listens on **8000**. `service.port` only changes the Service port (named target `http`). Do not point probes or NetworkPolicy at `service.port`.

### Least privilege

| Control | Default | Why |
| --- | --- | --- |
| `serviceAccount.automount` | `false` | App does not use the Kubernetes API |
| `seccompProfile` | `RuntimeDefault` | |
| `allowPrivilegeEscalation` | `false` | |
| dropped capabilities | `ALL` | Image still needs `CHOWN`, `SETUID`, `SETGID`, `FOWNER`, `DAC_OVERRIDE` |
| `networkPolicy.enabled` | `false` | Opt-in; requires Redis pod selector |

The official image **cannot** run as non-root: `entrypoint.sh` remaps `PUID`/`PGID`, then supervisord starts nginx as root and gunicorn/celery as uid 1000.

Opt-in NetworkPolicy:

```yaml
networkPolicy:
  enabled: true
  redis:
    port: 6379
    podSelector:
      app.kubernetes.io/name: redis
  # Required if postgresql.enabled is also true:
  # postgres:
  #   port: 5432
  #   podSelector:
  #     app.kubernetes.io/name: postgresql
  allowHTTPS: true   # TMDB/MAL/IGDB/etc.
  # Restrict who can reach port 8000 (empty = all):
  # extraIngress:
  #   - namespaceSelector:
  #       matchLabels:
  #         kubernetes.io/metadata.name: traefik
  #     podSelector:
  #       matchLabels:
  #         app.kubernetes.io/name: traefik
```

Allows: port 8000 ingress (all sources unless `extraIngress`), DNS to CoreDNS in `kube-system`, Redis, optional Postgres, and TCP/443. `extraEgress` is a list of extra egress rules.

The official image cannot use `runAsNonRoot` or `readOnlyRootFilesystem`. Pod Security Restricted will not admit it (root + `SETUID`/`DAC_OVERRIDE`).

### Probes

HTTP `GET /health/` on port 8000. Timeouts match the image healthcheck (15s). Startup allows ~5 minutes for migrations.

Deeper Celery check: `/health/full/` (slower; not the default probe).

## Values

See `values.yaml` for every option.

## Uninstall

```bash
helm uninstall yamtrack
```

The data PVC is annotated `helm.sh/resource-policy: keep`, so Helm leaves it. Delete it only if you want a clean wipe:

```bash
kubectl delete pvc -l app.kubernetes.io/instance=yamtrack
```

## Links

- [Yamtrack](https://github.com/FuzzyGrim/Yamtrack)
- [Setup](https://fuzzygrim.github.io/Yamtrack/release/setup/)
- [Environment variables](https://github.com/FuzzyGrim/Yamtrack/wiki/Environment-Variables)
