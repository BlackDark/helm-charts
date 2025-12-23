# Dawarich Helm Chart

A Helm chart for deploying [Dawarich](https://dawarich.app) - a self-hosted alternative to Google Location History.

## Prerequisites

- Kubernetes 1.16+
- Helm 3+
- **External PostgreSQL 12+** with PostGIS extension
- **External Redis 6+**

## Breaking Changes (v0.2.0)

This version removes Bitnami PostgreSQL and Redis subcharts. You **must** provide external database instances.

See [Migration Guide](#migration-from-bitnami-subcharts) below.

## Installation

### 1. Add the Helm Repository

```bash
helm repo add dawarich https://your-repo-url
helm repo update
```

### 2. Configure Databases and Application

Create a `values.yaml` with your database connection details and application settings:

```yaml
# Static application configuration (ConfigMap)
config:
  APPLICATION_HOSTS: "dawarich.example.com,gps.example.com"
  # Optional: Override defaults
  # TIME_ZONE: "America/New_York"
  # DISTANCE_UNIT: "mi"

# Secrets and external references (REQUIRED)
env:
  - name: DATABASE_HOST
    valueFrom:
      secretKeyRef:
        name: postgres-secret
        key: host
  - name: DATABASE_PORT
    value: "5432"
  - name: DATABASE_NAME
    value: "dawarich"
  - name: DATABASE_USERNAME
    valueFrom:
      secretKeyRef:
        name: postgres-secret
        key: username
  - name: DATABASE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: postgres-secret
        key: password
  - name: REDIS_URL
    valueFrom:
      secretKeyRef:
        name: redis-secret
        key: url

# Optional: Secret key for Rails (if not provided, create manually)
# secretKeyBase: "generate-a-secure-random-string-here"
```

### 3. Install the Chart

```bash
helm install dawarich dawarich/dawarich -f values.yaml
```

## External Database Setup Options

### Option 1: CloudPirates Charts (Recommended)

```bash
# Add CloudPirates repository
helm repo add cloudpirates https://cloudpirates-io.github.io/helm-charts

# Create secrets for the databases
kubectl create secret generic postgres-secret \
  --from-literal=host=dawarich-postgres-postgresql \
  --from-literal=username=dawarich \
  --from-literal=password=changeme

kubectl create secret generic redis-secret \
  --from-literal=url=redis://:changeme@dawarich-redis-master:6379

# Install PostgreSQL with PostGIS
helm install dawarich-postgres cloudpirates/postgres \
  --set auth.database=dawarich \
  --set auth.username=dawarich \
  --set auth.password=changeme \
  --set persistence.enabled=true \
  --set persistence.size=20Gi

# Install Redis
helm install dawarich-redis cloudpirates/redis \
  --set auth.password=changeme \
  --set master.persistence.enabled=false
```

### Option 2: AWS Managed Services

Create secrets:
```bash
kubectl create secret generic postgres-secret \
  --from-literal=host=mydb.abc123.us-east-1.rds.amazonaws.com \
  --from-literal=username=dawarich \
  --from-literal=password=your-password

kubectl create secret generic redis-secret \
  --from-literal=url=redis://:your-password@myredis.abc123.cache.amazonaws.com:6379
```

Then reference in values.yaml as shown in the Configuration section above.

### Option 3: Google Cloud Managed Services

Create secrets:
```bash
kubectl create secret generic postgres-secret \
  --from-literal=host=10.1.2.3 \
  --from-literal=username=dawarich \
  --from-literal=password=your-password

kubectl create secret generic redis-secret \
  --from-literal=url=redis://:your-password@10.1.2.4:6379
```

### Option 4: Azure Managed Services

Create secrets:
```bash
kubectl create secret generic postgres-secret \
  --from-literal=host=mydb.postgres.database.azure.com \
  --from-literal=username=dawarich@mydb \
  --from-literal=password=your-password

kubectl create secret generic redis-secret \
  --from-literal=url=rediss://:your-access-key@myredis.redis.cache.windows.net:6380
```

## Configuration

### Two-Part Configuration Approach

This chart separates configuration into two clear concerns:

#### 1. Static Configuration (`config` → ConfigMap)

Immutable values written to a ConfigMap. Most users won't need to change these:

| Variable                            | Default                                        | Description                                              |
| ----------------------------------- | ---------------------------------------------- | -------------------------------------------------------- |
| `APPLICATION_HOSTS`                 | `localhost,::1,127.0.0.1,dawarich.example.org` | Allowed hosts                                            |
| `MIN_MINUTES_SPENT_IN_CITY`         | `60`                                           | Minimum duration for a location to be considered visited |
| `TIME_ZONE`                         | `Europe/Berlin`                                | Application timezone                                     |
| `DISTANCE_UNIT`                     | `km`                                           | Distance unit (km or mi)                                 |
| `APPLICATION_PROTOCOL`              | `http`                                         | Protocol for application URLs                            |
| `BACKGROUND_PROCESSING_CONCURRENCY` | `10`                                           | Number of concurrent background jobs                     |
| `PHOTON_API_HOST`                   | `photon.komoot.io`                             | Geocoding service host                                   |
| `PHOTON_API_USE_HTTPS`              | `true`                                         | Use HTTPS for geocoding API                              |
| `RAILS_ENV`                         | `production`                                   | Rails environment                                        |
| `RAILS_LOG_TO_STDOUT`               | `true`                                         | Log to stdout                                            |
| `RAILS_CACHE_DB`                    | `0`                                            | Redis database for caching                               |
| `RAILS_JOB_QUEUE_DB`                | `1`                                            | Redis database for Sidekiq jobs                          |
| `RAILS_WS_DB`                       | `2`                                            | Redis database for WebSockets                            |

Override in values.yaml:
```yaml
config:
  APPLICATION_HOSTS: "dawarich.example.com,gps.example.com"
  TIME_ZONE: "America/New_York"
  DISTANCE_UNIT: "mi"
```

#### 2. Secrets and External References (`env` → Pod Environment)

References to secrets or direct values. You **must** configure database/Redis details:

| Variable            | Required | Description                                                        |
| ------------------- | -------- | ------------------------------------------------------------------ |
| `DATABASE_HOST`     | ✓        | PostgreSQL hostname                                                |
| `DATABASE_PORT`     |          | PostgreSQL port (default: 5432)                                    |
| `DATABASE_NAME`     |          | Database name (default: dawarich)                                  |
| `DATABASE_USERNAME` | ✓        | Database username                                                  |
| `DATABASE_PASSWORD` | ✓        | Database password (via secretKeyRef)                               |
| `REDIS_URL`         | ✓        | Redis connection URL                                               |
| `SECRET_KEY_BASE`   | ✓        | Rails secret (auto-generated from secretKeyBase, or manual secret) |

Configure via values.yaml:
```yaml
env:
  - name: DATABASE_HOST
    valueFrom:
      secretKeyRef:
        name: postgres-secret
        key: host
  - name: DATABASE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: postgres-secret
        key: password
  - name: REDIS_URL
    valueFrom:
      secretKeyRef:
        name: redis-secret
        key: url

# Optional: Auto-generate the SECRET_KEY_BASE secret
# If not provided, create the secret manually:
# kubectl create secret generic dawarich-app \
#   --from-literal=secretKeyBase=$(openssl rand -hex 32)
secretKeyBase: "$(openssl rand -hex 32)"
```

See [Dawarich documentation](https://dawarich.app) for additional environment variables.

## Migration from Bitnami Subcharts

If you're upgrading from a previous version that used Bitnami subcharts, follow these steps:

### Step 1: Backup Your Data

```bash
# Get the PostgreSQL pod name
kubectl get pods -l app=postgresql

# Create a backup
kubectl exec -it <postgresql-pod> -- \
  pg_dump -U dawarich dawarich | gzip > backup.sql.gz
```

### Step 2: Deploy External Databases

Choose one of the setup options above and deploy your databases.

### Step 3: Create Database Secrets

```bash
# Create PostgreSQL secret
kubectl create secret generic postgres-secret \
  --from-literal=host=<postgres-host> \
  --from-literal=username=dawarich \
  --from-literal=password='your-password'

# Create Redis secret
kubectl create secret generic redis-secret \
  --from-literal=url='redis://:your-redis-password@<redis-host>:6379'
```

### Step 4: Restore Data

```bash
# Get the new PostgreSQL pod name
kubectl get pods -l app=postgresql

# Restore the backup
gunzip < backup.sql.gz | \
  kubectl exec -i <new-postgresql-pod> -- \
  psql -U dawarich dawarich
```

### Step 5: Update Helm Values

Create your values.yaml with environment variables (see Configuration section above).

### Step 6: Upgrade the Chart

```bash
helm upgrade dawarich ./dawarich -f values.yaml
```

## Troubleshooting

### PostgreSQL Connection Issues

Test connectivity to PostgreSQL:

```bash
kubectl run -it --rm debug --image=postgres:16 --restart=Never -- \
  psql -h <postgres-host> -U dawarich -d dawarich -c "SELECT 1"
```

### Redis Connection Issues

Test connectivity to Redis:

```bash
kubectl run -it --rm debug --image=redis:8 --restart=Never -- \
  redis-cli -h <redis-host> -a <password> ping
```

### PostGIS Extension Missing

If you get errors about PostGIS not being available, connect to PostgreSQL and run:

```sql
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
```

## Backup & Restore

### Backup PostgreSQL

```bash
# Get PostgreSQL pod
POSTGRES_POD=$(kubectl get pod -l app=postgresql -o jsonpath='{.items[0].metadata.name}')

# Create backup
kubectl exec -it $POSTGRES_POD -- \
  pg_dump -U dawarich dawarich | gzip > backup.sql.gz
```

### Restore PostgreSQL

```bash
# Get PostgreSQL pod
POSTGRES_POD=$(kubectl get pod -l app=postgresql -o jsonpath='{.items[0].metadata.name}')

# Restore backup
gunzip < backup.sql.gz | \
  kubectl exec -i $POSTGRES_POD -- \
  psql -U dawarich dawarich
```

### About Redis Backups

Redis is used for caching and job queues only - no backup is needed. If Redis data is lost:
- Cached data will be rebuilt automatically
- In-flight jobs will need to be requeued
- All persistent data is in PostgreSQL

## Values

See `values.yaml` for all available configuration options.

## Support

- [Dawarich Documentation](https://dawarich.app)
- [GitHub Repository](https://github.com/Freika/dawarich)

## License

This chart is licensed under the Apache License 2.0.
