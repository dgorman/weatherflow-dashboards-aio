# WeatherFlow Collector - Project Status

## Current State

✅ **Repository Structure Complete**
- Fork of `weatherflow-dashboards-aio` (Grafana dashboards)
- Source code from `lux4rd0/weatherflow-collector` added
- Dockerfile and requirements.txt included
- Argo Workflow deployment configured

## What We Have

### Source Code (from upstream)
```
src/
├── collector/          # Data collection modules
│   ├── rest_*.py      # REST API collectors
│   ├── udp.py         # UDP broadcast collector
│   └── websocket.py   # WebSocket collector
├── handlers/          # Data handlers
├── processor/         # Data processing
├── storage/           # InfluxDB storage
└── weatherflow-collector.py  # Main entry point
```

### Deployment Files
```
argo/
├── weatherflow-collector-deploy.yaml  # Argo Workflow
└── trigger-deploy.sh                  # Helper script

k8s/
├── base/                             # Base manifests
│   ├── influxdb-*.yaml
│   └── weatherflow-deployment.yaml
└── overlays/prod/                    # Production overlay
```

### Build Configuration
- **Dockerfile**: Multi-stage Python build
- **requirements.txt**: Python dependencies
- **Image**: `registry.olympusdrive.com/weatherflow-collector:latest`

## Deployment Process (When AWS Recovers)

### Step 1: Wait for AWS US-East-1 Recovery
Currently blocked by:
- ❌ quay.io (502 Bad Gateway) - needed for Argo Workflows executor
- ❌ DockerHub (503 Service Unavailable) - needed for base images

### Step 2: Deploy via Argo Workflow
```bash
# Once AWS recovers, run:
cd /Users/dgorman/Dev/weatherflow-collector
./argo/trigger-deploy.sh
```

The workflow will:
1. Clone from GitHub: `dgorman/weatherflow-dashboards-aio`
2. Build Docker image with git SHA tag
3. Push to `registry.olympusdrive.com/weatherflow-collector`
4. Deploy to Kubernetes namespace `weatherflow`
5. Start collecting weather data

### Step 3: Validate Deployment
```bash
# Check pods
ssh dgorman@node01.olympusdrive.com 'kubectl get pods -n weatherflow'

# Check logs
ssh dgorman@node01.olympusdrive.com 'kubectl logs -n weatherflow -l app=weatherflow-collector -f'

# Verify InfluxDB data
ssh dgorman@node01.olympusdrive.com 'kubectl port-forward -n weatherflow svc/influxdb 8086:8086'
# Then open http://localhost:8086
```

## Current Blockers

### AWS US-East-1 Outage (October 20, 2025)
Affecting:
- quay.io/argoproj/argoexec:latest (Argo Workflows init container)
- docker.io registry (DockerHub base images)

**Workaround Options:**
1. Wait for AWS recovery (recommended)
2. Manual build on node01 when registries recover
3. Use cached images if available

## What's Ready to Go

✅ Source code committed and pushed to GitHub  
✅ Argo Workflow configured (similar to solardashboard)  
✅ Kubernetes manifests ready  
✅ InfluxDB persistent storage configured  
✅ Grafana dashboards available  
✅ Git-based deployment (no rsync!)  

## Configuration

### Collector Settings
- **API Token**: `a1af9766-cf15-429b-8bbc-8c40bcda2314`
- **Collectors Enabled**: REST API, WebSocket, UDP
- **Host Network**: `true` (for UDP port 50222)

### InfluxDB
- **URL**: `http://influxdb.weatherflow.svc.cluster.local:8086`
- **Org**: `weatherflow`
- **Bucket**: `weatherflow`
- **Token**: `weatherflow-admin-token-12345`
- **Storage**: 10Gi PVC (Longhorn)

## Next Steps (After AWS Recovery)

1. ✅ Source code is ready
2. ⏳ Wait for AWS US-East-1 / quay.io / DockerHub recovery
3. 🚀 Run `./argo/trigger-deploy.sh`
4. 📊 Import Grafana dashboards
5. ✅ Validate data collection

## Repository URLs

- **This Repo**: https://github.com/dgorman/weatherflow-dashboards-aio
- **Upstream Dashboards**: https://github.com/lux4rd0/weatherflow-dashboards-aio
- **Upstream Collector**: https://github.com/lux4rd0/weatherflow-collector

## Comparison with SolarDashboard

Both now use identical deployment pattern:

| Feature | SolarDashboard | WeatherFlow Collector |
|---------|----------------|----------------------|
| Deployment | Argo Workflow | Argo Workflow ✅ |
| Source | Git clone from GitHub | Git clone from GitHub ✅ |
| Build | Docker-in-Docker | Docker-in-Docker ✅ |
| Tagging | Git SHA | Git SHA ✅ |
| Registry | registry.olympusdrive.com | registry.olympusdrive.com ✅ |
| Monitoring | Argo UI + logs | Argo UI + logs ✅ |

## Support

Once deployed, monitor at:
- **Argo Workflows UI**: https://argo.olympusdrive.com
- **Production Logs**: `ssh dgorman@node01.olympusdrive.com 'kubectl logs -n weatherflow -l app=weatherflow-collector -f'`
- **InfluxDB UI**: Port-forward to localhost:8086
