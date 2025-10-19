# WeatherFlow Collector - Kubernetes Deployment

This directory contains Kubernetes manifests and deployment scripts for the WeatherFlow Collector.

## Architecture

- **InfluxDB 2.7**: Time-series database for storing weather data
- **WeatherFlow Collector**: Collects data from WeatherFlow API and local UDP broadcasts
- **Storage**: Longhorn persistent volume for InfluxDB data
- **Networking**: Collector uses hostNetwork to receive UDP broadcasts on port 50222

## Deployment Methods

### Method 1: Automated Deployment Script (Recommended)

The `deploy.sh` script handles the complete deployment process:

```bash
# Deploy with default 'latest' tag
./deploy.sh

# Deploy with specific tag
./deploy.sh v1.0.0
```

The script will:
1. Sync code to `node01.olympusdrive.com:/home/dgorman/Apps/weatherflow-collector`
2. Build Docker image on the remote server
3. Push image to `registry.olympusdrive.com`
4. Deploy to Kubernetes via Argo CD or kubectl

### Method 2: Argo CD Application

Create the Argo CD application:

```bash
ssh dgorman@node01.olympusdrive.com
kubectl apply -f /home/dgorman/Apps/weatherflow-collector/k8s/argocd-application.yaml
```

Sync manually:
```bash
argocd app sync weatherflow-collector
```

### Method 3: Direct kubectl Apply

```bash
ssh dgorman@node01.olympusdrive.com
kubectl apply -k /home/dgorman/Apps/weatherflow-collector/k8s/overlays/prod
```

## Configuration

### Environment Variables

The collector is configured via environment variables in `k8s/base/weatherflow-deployment.yaml`:

- `WEATHERFLOW_COLLECTOR_TOKEN`: Your WeatherFlow API token
- `WEATHERFLOW_COLLECTOR_INFLUXDB_URL`: InfluxDB URL (http://influxdb.weatherflow.svc.cluster.local:8086)
- `WEATHERFLOW_COLLECTOR_INFLUXDB_TOKEN`: InfluxDB admin token
- `WEATHERFLOW_COLLECTOR_INFLUXDB_ORG`: Organization name (weatherflow)
- `WEATHERFLOW_COLLECTOR_INFLUXDB_BUCKET`: Bucket name (weatherflow)
- Collector enable/disable flags for REST, WebSocket, UDP, etc.

### InfluxDB Configuration

InfluxDB is configured in `k8s/base/influxdb-deployment.yaml`:

- **Username**: admin
- **Password**: weatherflow-admin-password
- **Organization**: weatherflow
- **Bucket**: weatherflow
- **Admin Token**: weatherflow-admin-token-12345
- **Storage**: 10Gi persistent volume (Longhorn)

## Monitoring

### Check Pod Status

```bash
ssh dgorman@node01.olympusdrive.com 'kubectl get pods -n weatherflow'
```

### View Logs

```bash
# Collector logs
ssh dgorman@node01.olympusdrive.com 'kubectl logs -f -n weatherflow -l app=weatherflow-collector'

# InfluxDB logs
ssh dgorman@node01.olympusdrive.com 'kubectl logs -f -n weatherflow -l app=influxdb'
```

### Check Argo CD Status

```bash
ssh dgorman@node01.olympusdrive.com 'argocd app get weatherflow-collector'
```

## Accessing Services

### InfluxDB UI

InfluxDB is only accessible within the cluster. To access the UI:

```bash
kubectl port-forward -n weatherflow svc/influxdb 8086:8086
```

Then open http://localhost:8086

### Grafana Integration

Import the dashboards from `grafana/dashboards/weatherflow-collector/` into your Grafana instance.

Configure the InfluxDB datasource:
- **URL**: http://influxdb.weatherflow.svc.cluster.local:8086
- **Organization**: weatherflow
- **Token**: weatherflow-admin-token-12345
- **Default Bucket**: weatherflow
- **Query Language**: InfluxQL

## Troubleshooting

### Collector Not Receiving UDP Data

The collector runs with `hostNetwork: true` to receive UDP broadcasts. Ensure:
- The weather station hub is on the same network as the Kubernetes node
- UDP port 50222 is not blocked by firewall
- Check logs: `kubectl logs -n weatherflow -l app=weatherflow-collector | grep UDP`

### InfluxDB Data Persistence

Data is stored in a Longhorn PersistentVolume. Check:
```bash
kubectl get pvc -n weatherflow
kubectl get pv | grep weatherflow
```

### Restarting Services

```bash
# Restart collector
kubectl rollout restart deployment/weatherflow-collector -n weatherflow

# Restart InfluxDB
kubectl rollout restart deployment/influxdb -n weatherflow
```

## Directory Structure

```
k8s/
├── argocd-application.yaml       # Argo CD Application definition
├── base/                          # Base Kubernetes manifests
│   ├── namespace.yaml
│   ├── influxdb-pvc.yaml
│   ├── influxdb-deployment.yaml
│   ├── influxdb-service.yaml
│   ├── weatherflow-deployment.yaml
│   └── kustomization.yaml
└── overlays/
    └── prod/                      # Production overlay
        └── kustomization.yaml
```

## Update Process

1. Make code changes locally
2. Run `./deploy.sh` to build and deploy
3. Argo CD will automatically sync the application
4. Monitor rollout: `kubectl rollout status deployment/weatherflow-collector -n weatherflow`

## Notes

- InfluxDB uses a Recreate strategy to prevent data corruption (single instance)
- Collector uses hostNetwork for UDP reception (port 50222)
- All sensitive credentials are in plain text - consider using Kubernetes Secrets for production
- The collector uses the same API token as the local development environment
