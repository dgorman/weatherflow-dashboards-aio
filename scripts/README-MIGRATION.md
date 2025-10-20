# InfluxDB Data Migration

## Overview

This script migrates historical weather data from your local development InfluxDB to production.

## Prerequisites

- ✅ Local InfluxDB running with data (`docker ps | grep influx`)
- ✅ Production InfluxDB pod running on [prod]
- ✅ SSH access to node01.olympusdrive.com
- ✅ kubectl access to weatherflow namespace

## What It Does

1. **Backs up local InfluxDB** using `influx backup`
2. **Transfers backup** to production via rsync
3. **Restores to production** InfluxDB pod
4. **Preserves local backup** in `/tmp` for safety

## Usage

### Step 1: Ensure Production InfluxDB is Running

```bash
# Check if InfluxDB pod is ready on [prod]
ssh dgorman@node01.olympusdrive.com 'kubectl get pods -n weatherflow -l app=influxdb'

# Should show: STATUS = Running
```

### Step 2: Run Migration

```bash
cd /Users/dgorman/Dev/weatherflow-collector
./scripts/migrate-influxdb-data.sh
```

The script will:
- Export data from local Docker InfluxDB
- Transfer to production
- Restore into production InfluxDB pod
- Keep local backup for safety

### Step 3: Verify

```bash
# Port-forward to production InfluxDB
ssh dgorman@node01.olympusdrive.com 'kubectl port-forward -n weatherflow svc/influxdb 8086:8086'

# Open browser
open http://localhost:8086

# Login with:
# Username: admin
# Password: weatherflow-admin-password
```

## InfluxDB Configuration

### Local (Dev)
```
URL:    http://localhost:8086
Org:    weatherflow
Bucket: weatherflow
Token:  weatherflow-admin-token-12345
```

### Production
```
URL:    http://influxdb.weatherflow.svc.cluster.local:8086
Org:    weatherflow
Bucket: weatherflow
Token:  weatherflow-admin-token-12345
Storage: 10Gi Longhorn PVC (persistent)
```

## Persistent Storage on Production

Production InfluxDB uses **Longhorn persistent storage**:

```yaml
PersistentVolumeClaim:
  name: influxdb-data
  storage: 10Gi
  storageClassName: longhorn
  accessModes: ReadWriteOnce
```

Data is preserved across:
- ✅ Pod restarts
- ✅ Node rescheduling
- ✅ Cluster upgrades
- ✅ Container rebuilds

## Backup Location

Local backups are saved in `/tmp/weatherflow-influxdb-backup-YYYYMMDD-HHMMSS/`

Keep these backups for recovery if needed!

## Troubleshooting

### Pod Not Ready

```bash
# Check pod status
ssh dgorman@node01.olympusdrive.com 'kubectl describe pod -n weatherflow -l app=influxdb'

# Check PVC
ssh dgorman@node01.olympusdrive.com 'kubectl get pvc -n weatherflow'
```

### Restore Fails

```bash
# Check pod logs
ssh dgorman@node01.olympusdrive.com 'kubectl logs -n weatherflow -l app=influxdb'

# Manually restore
ssh dgorman@node01.olympusdrive.com
kubectl exec -it -n weatherflow <pod-name> -- /bin/bash
influx restore --help
```

### Verify Data After Migration

```bash
# Port-forward to prod
ssh dgorman@node01.olympusdrive.com 'kubectl port-forward -n weatherflow svc/influxdb 8086:8086'

# Query using influx CLI
influx query 'from(bucket: "weatherflow") |> range(start: -7d) |> limit(n: 10)' \
  --host http://localhost:8086 \
  --token weatherflow-admin-token-12345 \
  --org weatherflow
```

## Alternative: Line Protocol Export/Import

If the backup/restore doesn't work, you can export as line protocol:

### Export from Local

```bash
# Export last 30 days
influx query 'from(bucket: "weatherflow") |> range(start: -30d)' \
  --host http://localhost:8086 \
  --token weatherflow-admin-token-12345 \
  --org weatherflow \
  --raw > weatherflow-data.lp
```

### Import to Production

```bash
# Transfer to production
scp weatherflow-data.lp dgorman@node01.olympusdrive.com:/tmp/

# Import
ssh dgorman@node01.olympusdrive.com
POD=$(kubectl get pod -n weatherflow -l app=influxdb -o jsonpath='{.items[0].metadata.name}')
kubectl cp /tmp/weatherflow-data.lp ${POD}:/tmp/weatherflow-data.lp -n weatherflow
kubectl exec -n weatherflow ${POD} -- influx write \
  --bucket weatherflow \
  --org weatherflow \
  --token weatherflow-admin-token-12345 \
  --file /tmp/weatherflow-data.lp
```

## Notes

- Migration preserves all timestamps and data points
- Production and dev use the same org/bucket/token for simplicity
- Data is additive - won't overwrite existing production data
- The collector will continue adding new data after migration
- Consider running during low collection activity
