# WeatherFlow Collector - Deployment Quick Reference

## Environment Overview

### Local Development
- **Location**: `/Users/dgorman/Dev/weatherflow-collector`
- **InfluxDB**: http://localhost:8086 (org=weatherflow, bucket=weatherflow)
- **Grafana**: http://localhost:3000 (existing instance on monitoring network)
- **Collector**: Host network mode for UDP port 50222

### Production
- **Host**: node01.olympusdrive.com
- **Location**: `/home/dgorman/Apps/weatherflow-collector`
- **Namespace**: weatherflow
- **Registry**: registry.olympusdrive.com
- **Storage**: Longhorn (10Gi PVC)

## Quick Commands

### Initial Production Setup (One-Time)
```bash
# From local dev machine
cd /Users/dgorman/Dev/weatherflow-collector
./setup.sh
```

**What it does**:
1. Syncs code to node01.olympusdrive.com
2. Creates Argo CD application `weatherflow-collector`
3. Displays next steps

### Deploy/Update Production
```bash
# From local dev machine
cd /Users/dgorman/Dev/weatherflow-collector
./deploy.sh
```

**What it does**:
1. Syncs latest code to remote
2. Builds Docker image on node01
3. Pushes to registry.olympusdrive.com/weatherflow-collector:latest
4. Deploys via Argo CD (or kubectl if Argo CD not available)
5. Waits for rollout completion
6. Shows status and log commands

### Optional: Deploy with Specific Tag
```bash
./deploy.sh v1.0.0
```

## Monitoring Production

### Check Pod Status
```bash
ssh dgorman@node01.olympusdrive.com 'kubectl get pods -n weatherflow'
```

### View Collector Logs
```bash
ssh dgorman@node01.olympusdrive.com 'kubectl logs -f -n weatherflow -l app=weatherflow-collector'
```

### View InfluxDB Logs
```bash
ssh dgorman@node01.olympusdrive.com 'kubectl logs -f -n weatherflow -l app=influxdb'
```

### Check Argo CD Application
```bash
ssh dgorman@node01.olympusdrive.com 'argocd app get weatherflow-collector'
```

### Manual Argo CD Sync
```bash
ssh dgorman@node01.olympusdrive.com 'argocd app sync weatherflow-collector'
```

### Get All Resources
```bash
ssh dgorman@node01.olympusdrive.com 'kubectl get all -n weatherflow'
```

## Local Development

### Start Services
```bash
cd /Users/dgorman/Dev/weatherflow-collector
docker-compose up -d
```

### Stop Services
```bash
docker-compose down
```

### View Collector Logs
```bash
docker logs -f wxfdashboardsaio-collector-a1af9766
```

### View InfluxDB Logs
```bash
docker logs -f wxfdashboardsaio_influxdb
```

### Rebuild Collector
```bash
docker-compose up -d --build
```

## Dashboard Management

### Local Dashboards Location
```
/Users/dgorman/Dev/weatherflow-collector/grafana/dashboards/weatherflow-collector/
```

### Production Import (Manual)
1. Access production Grafana
2. Import JSON files from above location
3. Configure datasource:
   - URL: `http://influxdb.weatherflow.svc.cluster.local:8086`
   - Organization: `weatherflow`
   - Token: `weatherflow-admin-token-12345`
   - Query Language: `InfluxQL`

### Dashboard List (11 total)
- `weatherflow_collector-forecast-influxdb.json`
- `weatherflow_collector-current_conditions-influxdb.json`
- `weatherflow_collector-historical_local-udp-influxdb.json`
- `weatherflow_collector-historical_remote-influxdb.json`
- `weatherflow_collector-overview-influxdb.json`
- `weatherflow_collector-today_so_far_local-udp-influxdb.json`
- `weatherflow_collector-today_so_far_remote-influxdb.json`
- `weatherflow_collector-rain_and_lightning-influxdb.json`
- `weatherflow_collector-forecast_vs_observed-influxdb.json`
- `weatherflow_collector-device_details-influxdb.json`
- `weatherflow_collector-system_stats-influxdb.json`

## Configuration

### Collector Settings
**API Token**: `a1af9766-cf15-429b-8bbc-8c40bcda2314`

**Enabled Collectors**:
- REST API (observations, forecasts, stats)
- UDP (local broadcasts on port 50222)
- WebSocket (real-time updates)
- System metrics
- Health checks

### InfluxDB Credentials
**Local**:
- URL: http://localhost:8086
- Username: admin
- Password: weatherflow-admin-password
- Org: weatherflow
- Bucket: weatherflow
- Token: weatherflow-admin-token-12345

**Production**:
- Same credentials as local
- Internal URL: http://influxdb.weatherflow.svc.cluster.local:8086

## Troubleshooting

### Collector Not Receiving UDP Data (Production)
1. Verify collector pod using hostNetwork:
   ```bash
   ssh dgorman@node01.olympusdrive.com 'kubectl get pod -n weatherflow -o yaml | grep hostNetwork'
   ```
2. Check UDP listener in logs:
   ```bash
   ssh dgorman@node01.olympusdrive.com 'kubectl logs -n weatherflow -l app=weatherflow-collector | grep UDP'
   ```
3. Verify weather station hub on same network as node01

### InfluxDB Not Persisting Data
1. Check PVC status:
   ```bash
   ssh dgorman@node01.olympusdrive.com 'kubectl get pvc -n weatherflow'
   ```
2. Verify Longhorn storage:
   ```bash
   ssh dgorman@node01.olympusdrive.com 'kubectl get pv | grep weatherflow'
   ```

### Dashboard Shows "No Data"
1. Verify datasource configured correctly (InfluxQL, not Flux)
2. Check collector_type constants match (collector_rest, collector_udp, collector_websocket, collector_forecast)
3. Verify time range includes data (forecasts start tomorrow, not today)
4. Check InfluxDB has measurements:
   ```bash
   # Port-forward to InfluxDB
   ssh dgorman@node01.olympusdrive.com 'kubectl port-forward -n weatherflow svc/influxdb 8086:8086'
   # Access UI at http://localhost:8086
   ```

### Argo CD Application Out of Sync
```bash
ssh dgorman@node01.olympusdrive.com 'argocd app sync weatherflow-collector --prune'
```

## File Structure

```
weatherflow-collector/
├── docker-compose.yml          # Local development stack
├── Dockerfile                  # Collector container image
├── setup.sh                    # Initial production setup
├── deploy.sh                   # Deployment automation
├── README.md                   # Main documentation
├── DEPLOYMENT.md               # This file
├── k8s/
│   ├── README.md              # Kubernetes deployment docs
│   ├── argocd-application.yaml # Argo CD app definition
│   ├── base/                  # Base Kubernetes manifests
│   │   ├── namespace.yaml
│   │   ├── influxdb-pvc.yaml
│   │   ├── influxdb-deployment.yaml
│   │   ├── influxdb-service.yaml
│   │   ├── weatherflow-deployment.yaml
│   │   └── kustomization.yaml
│   └── overlays/
│       └── prod/              # Production overlay
│           └── kustomization.yaml
├── grafana/
│   └── dashboards/
│       └── weatherflow-collector/  # 11 dashboard JSON files
└── src/                       # Python collector source code
```

## Next Steps After Deployment

1. **Run initial setup**:
   ```bash
   ./setup.sh
   ```

2. **Deploy to production**:
   ```bash
   ./deploy.sh
   ```

3. **Verify pods running**:
   ```bash
   ssh dgorman@node01.olympusdrive.com 'kubectl get pods -n weatherflow'
   ```

4. **Check logs for data collection**:
   ```bash
   ssh dgorman@node01.olympusdrive.com 'kubectl logs -n weatherflow -l app=weatherflow-collector | tail -50'
   ```

5. **Import Grafana dashboards** (manual):
   - Access production Grafana
   - Import all 11 JSON files from `grafana/dashboards/weatherflow-collector/`
   - Configure datasource connection

6. **Verify dashboards display data**:
   - Current Conditions: Should show live observations
   - Forecast: Should show 10-day forecast
   - Historical: Should show past data trends

## Security Notes

⚠️ **Current State**: Credentials are stored as plain text in manifests

**Future Enhancement**: Migrate to Kubernetes Secrets
```bash
# Example (not yet implemented)
kubectl create secret generic influxdb-creds \
  --from-literal=admin-password=weatherflow-admin-password \
  --from-literal=admin-token=weatherflow-admin-token-12345 \
  -n weatherflow
```

## Support

For issues or questions:
- Check [k8s/README.md](k8s/README.md) for detailed documentation
- Review collector logs for errors
- Verify InfluxDB connectivity
- Confirm weather station hub on same network (for UDP)
