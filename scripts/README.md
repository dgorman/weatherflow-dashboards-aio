# WeatherFlow Collector Scripts

This directory contains automation scripts for managing the WeatherFlow data collection and visualization system.

## Scripts Overview

### 📊 Grafana Management

#### `create-grafana-datasource.sh`
Creates the InfluxDB datasource in Grafana for WeatherFlow dashboards.

**What it does:**
- Auto-detects production environment (uses K8s secrets)
- Creates/updates "WeatherFlow InfluxDB" datasource
- Configures InfluxDB v2 (Flux) connection
- Tests datasource connectivity
- Sets as default datasource

**Usage:**
```bash
# On production (auto-configures from K8s)
ssh dgorman@node01.olympusdrive.com
cd /home/dgorman/Apps/weatherflow-collector
./scripts/create-grafana-datasource.sh

# On local (prompts for values)
./scripts/create-grafana-datasource.sh
```

**Configuration:**
```
Name:         InfluxDB - weatherflow
Type:         InfluxDB (Flux)
URL:          http://influxdb.weatherflow.svc.cluster.local:8086
Organization: weatherflow
Bucket:       weatherflow
Default:      Yes
```

#### `import-grafana-dashboards.sh`
Imports all 11 WeatherFlow dashboards into Grafana's "Weather" folder.

**What it does:**
- Auto-detects production environment
- Uses kubectl port-forward to access Grafana
- Creates "Weather" folder (if not exists)
- Imports all dashboards with overwrite support
- Removes dashboard IDs to avoid conflicts

**Usage:**
```bash
# On production (auto-configures from K8s)
ssh dgorman@node01.olympusdrive.com
cd /home/dgorman/Apps/weatherflow-collector
./scripts/import-grafana-dashboards.sh

# On local (prompts for credentials)
./scripts/import-grafana-dashboards.sh
```

**Dashboards Imported:**
1. Current Conditions
2. Device Details
3. Forecast
4. Forecast Vs Observed
5. Historical (local-udp)
6. Historical (remote)
7. Overview
8. Rain and Lightning
9. System Stats
10. Today So Far (local-udp)
11. Today So Far (remote)

### 💾 InfluxDB Management

#### `migrate-influxdb-data.sh`
Migrates historical weather data from local development to production InfluxDB.

**Prerequisites:**
- Local InfluxDB with data
- Production InfluxDB pod running
- SSH access to node01.olympusdrive.com

**Usage:**
```bash
cd /Users/dgorman/Dev/weatherflow-collector
./scripts/migrate-influxdb-data.sh
```

See [README-MIGRATION.md](./README-MIGRATION.md) for detailed migration documentation.

#### `restore-from-backup.sh`
Restores InfluxDB backup to production (Phase 2 of migration).

**Usage:**
```bash
# After backup is transferred to production
ssh dgorman@node01.olympusdrive.com
cd /home/dgorman/Apps/weatherflow-collector
./scripts/restore-from-backup.sh
```

## Production Environment Setup

### Kubernetes Secrets

The Grafana scripts automatically retrieve credentials from K8s secrets in production:

```bash
# Grafana credentials (in weatherflow namespace)
kubectl get secret grafana-credentials -n weatherflow -o jsonpath='{.data.username}' | base64 -d
kubectl get secret grafana-credentials -n weatherflow -o jsonpath='{.data.password}' | base64 -d
```

### Port Forwarding

Scripts automatically use kubectl port-forward when running on production:

```bash
# Grafana (in solardashboard namespace)
kubectl port-forward -n solardashboard svc/grafana 8080:3000
```

### Service Locations

**Production (node01.olympusdrive.com):**
```
InfluxDB:  influxdb.weatherflow.svc.cluster.local:8086
Grafana:   grafana.solardashboard.svc.cluster.local:3000 (port-forward required)
Namespace: weatherflow (collector, influxdb)
Namespace: solardashboard (grafana)
```

**Local (Docker Compose):**
```
InfluxDB:  localhost:8086
Grafana:   localhost:3001
```

## Complete Setup Flow

To set up a fresh environment:

### 1. Deploy WeatherFlow Collector
```bash
# Using Argo Workflows
cd /home/dgorman/Apps/weatherflow-collector/argo
./trigger-deploy.sh
```

### 2. Create Grafana Datasource
```bash
cd /home/dgorman/Apps/weatherflow-collector
./scripts/create-grafana-datasource.sh
```

### 3. Import Grafana Dashboards
```bash
./scripts/import-grafana-dashboards.sh
```

### 4. (Optional) Migrate Historical Data
```bash
# From local dev machine
./scripts/migrate-influxdb-data.sh
```

## Verification

### Check InfluxDB Data
```bash
# Port-forward to production
ssh dgorman@node01.olympusdrive.com 'kubectl port-forward -n weatherflow svc/influxdb 8086:8086'

# Query data count
curl -X POST "http://localhost:8086/api/v2/query?org=weatherflow" \
  -H "Authorization: Token weatherflow-admin-token-12345" \
  -H "Content-Type: application/vnd.flux" \
  -d 'from(bucket: "weatherflow") |> range(start: -1h) |> count()'
```

### Check Grafana Datasource
```bash
# View datasources (opens browser)
open http://grafana.olympusdrive.com/datasources
```

### Check Dashboards
```bash
# View Weather folder (opens browser)
open http://grafana.olympusdrive.com/dashboards
```

## Troubleshooting

### Grafana Connection Issues

If scripts can't connect to Grafana:

```bash
# Check Grafana service
kubectl get svc -n solardashboard grafana

# Verify credentials
kubectl get secret grafana-credentials -n weatherflow -o yaml

# Test port-forward manually
kubectl port-forward -n solardashboard svc/grafana 8080:3000
curl http://localhost:8080/api/health
```

### InfluxDB Connection Issues

If datasource test fails:

```bash
# Check InfluxDB service
kubectl get svc -n weatherflow influxdb

# Check InfluxDB pod
kubectl get pods -n weatherflow -l app=influxdb

# Check InfluxDB logs
kubectl logs -n weatherflow -l app=influxdb --tail=50
```

### Dashboard Import Failures

If dashboard import fails:

```bash
# Check folder exists
kubectl port-forward -n solardashboard svc/grafana 8080:3000 &
curl -u admin:PASSWORD http://localhost:8080/api/folders

# Check dashboard JSON is valid
jq '.' grafana/dashboards/weatherflow-collector/weatherflow_collector-overview-influxdb.json
```

## Script Features

### Auto-Detection
- ✅ Detects production vs local environment
- ✅ Auto-retrieves K8s secrets on production
- ✅ Uses kubectl port-forward when needed
- ✅ Prompts for credentials in local dev

### Error Handling
- ✅ Validates connectivity before operations
- ✅ Provides clear error messages
- ✅ Cleans up port-forwards on exit
- ✅ Returns proper exit codes

### Safety
- ✅ Confirms overwrites when updating
- ✅ Tests connections before making changes
- ✅ Preserves existing data (additive)
- ✅ Uses temp files for large JSON payloads

## Environment Variables

You can override defaults:

```bash
# Grafana URL (default: auto-detected)
export GRAFANA_URL="http://grafana.olympusdrive.com"

# Grafana credentials (default: from K8s secret or prompt)
export GRAFANA_USER="admin"
export GRAFANA_PASS="password"

# Run script
./scripts/import-grafana-dashboards.sh
```

## Support

For issues or questions:
1. Check script output for detailed error messages
2. Review K8s pod logs: `kubectl logs -n weatherflow <pod-name>`
3. Verify service connectivity: `kubectl get svc -n weatherflow`
4. Check [PROJECT_STATUS.md](../PROJECT_STATUS.md) for current status

## Related Documentation

- [DEPLOYMENT.md](../DEPLOYMENT.md) - Full deployment guide
- [README-MIGRATION.md](./README-MIGRATION.md) - InfluxDB migration details
- [ARGO_WORKFLOW_SETUP.md](../ARGO_WORKFLOW_SETUP.md) - CI/CD pipeline setup
