# UDP Packet Forwarder Sidecar

## Overview

The UDP packet forwarder solves a cross-VLAN broadcast limitation where WeatherFlow Tempest broadcasts (255.255.255.255) don't get delivered to application sockets on Kubernetes nodes in a different subnet.

## Problem

- **Tempest Location**: 192.168.1.36 (VLAN 1 "Internal")
- **K8s Nodes**: 192.168.2.x (VLAN 2 "Lab")
- **Issue**: Linux kernel doesn't deliver global broadcasts (255.255.255.255) to application sockets when source and destination are on different subnets
- **Evidence**: `tcpdump` can see packets at the interface level, but UDP sockets don't receive them

## Solution: Sidecar Container Pattern

The forwarder runs as a **sidecar container** alongside the WeatherFlow collector in the same pod. This approach provides:

- **Automatic co-location**: Forwarder always runs on the same node as the collector
- **Automatic failover**: When the collector pod moves, the forwarder moves with it
- **No wasted resources**: Only runs where needed (with the collector)
- **Clean architecture**: Separation of concerns between packet capture and data processing
- **CI/CD integration**: Deployed automatically via Argo Workflows

### How It Works

1. **Sidecar container** captures UDP port 50222 packets at interface level using scapy (libpcap/BPF)
2. Extracts the UDP payload from each broadcast packet
3. Forwards to `localhost:50222` where the collector container is listening
4. Both containers share the pod's network namespace via `hostNetwork: true`
5. Localhost delivery works because both containers are in the same network namespace

## Deployment

### Production (Kubernetes)

The UDP forwarder is deployed automatically as part of the WeatherFlow collector deployment:

```bash
# Deploy via Argo Workflows (recommended)
cd /home/dgorman/Apps/weatherflow-collector/argo
./trigger-deploy.sh

# Or deploy directly with kubectl
kubectl apply -k /home/dgorman/Apps/weatherflow-collector/k8s/overlays/prod
```

The sidecar container is defined in `k8s/base/weatherflow-deployment.yaml`:

```yaml
containers:
  - name: collector
    image: registry.olympusdrive.com/weatherflow-collector:latest
    # ... collector configuration ...
  
  - name: udp-forwarder
    image: registry.olympusdrive.com/weatherflow-udp-forwarder:latest
    securityContext:
      privileged: true  # Required for raw packet capture
      capabilities:
        add:
        - NET_RAW
        - NET_ADMIN
    resources:
      requests:
        memory: "32Mi"
        cpu: "50m"
      limits:
        memory: "128Mi"
        cpu: "200m"
```

### Local Development (Docker Compose)

The UDP forwarder is included in `docker-compose.yml`:

```bash
cd /Users/dgorman/Dev/weatherflow-collector
docker-compose up -d
```

**Note**: UDP forwarder requires `privileged: true` which doesn't work the same way on Docker Desktop for Mac. For local development, the REST and WebSocket collectors provide full functionality.

## Monitoring

### Check Pod Status

```bash
# Both containers should show as Running (2/2 Ready)
kubectl get pods -n weatherflow -o wide
```

Expected output:
```
NAME                                    READY   STATUS    RESTARTS   AGE     NODE
weatherflow-collector-5b49fc7548-xxxxx  2/2     Running   0          5m      node02
```

### View Forwarder Logs

```bash
# View forwarder sidecar logs
kubectl logs -n weatherflow deployment/weatherflow-collector udp-forwarder --tail=50

# Follow forwarder logs in real-time
kubectl logs -n weatherflow deployment/weatherflow-collector udp-forwarder -f
```

### Verify UDP Data Flow

```bash
# Check if UDP data is being written to InfluxDB
kubectl exec -n weatherflow deployment/influxdb -- \
  influx query 'from(bucket: "weatherflow") 
                |> range(start: -10m) 
                |> filter(fn: (r) => r.collector_type == "collector_udp") 
                |> count()' \
  --org weatherflow \
  --token weatherflow-admin-token-12345
```

### Resource Usage

Check sidecar resource consumption:

```bash
kubectl top pod -n weatherflow
```

Expected usage:
- CPU: 0-5m (minimal when idle, brief spikes during packet capture)
- Memory: 32-70Mi

## Troubleshooting

### Pod Shows 1/2 Ready

If the pod shows only 1 container ready:

```bash
# Check which container is failing
kubectl describe pod -n weatherflow <pod-name>

# Check forwarder logs for errors
kubectl logs -n weatherflow <pod-name> udp-forwarder
```

Common issues:
- **Scapy import error**: Verify `pip install scapy` in Dockerfile (not apt-get)
- **Insufficient privileges**: Verify `privileged: true` in deployment

### No UDP Data in InfluxDB

1. Verify packets are reaching the node:
   ```bash
   # SSH to the node running the collector pod
   ssh dgorman@<node-ip>
   sudo tcpdump -i any -n udp port 50222 -c 5
   ```

2. Check if collector is receiving data:
   ```bash
   kubectl logs -n weatherflow deployment/weatherflow-collector collector | grep -i udp
   ```

   Expected output:
   ```
   collector_udp enabled.
   Listening for UDP traffic on port 50222 with SO_BROADCAST enabled
   ```

3. Verify hostNetwork is working:
   ```bash
   kubectl get pod -n weatherflow <pod-name> -o jsonpath='{.spec.hostNetwork}'
   # Should output: true
   ```

### Forwarder Container Restarts

Check restart reason:

```bash
kubectl describe pod -n weatherflow <pod-name>
```

Common reasons:
- OOMKilled: Increase memory limits in deployment
- CrashLoopBackOff: Check logs for Python errors

## Building the Forwarder Image

### On Production Cluster

The forwarder image is built automatically via Argo Workflows, but you can build manually:

```bash
cd /Users/dgorman/Dev/weatherflow-collector
./build-forwarder.sh
```

This builds on `node01.olympusdrive.com` and pushes to `registry.olympusdrive.com`.

### Image Details

- **Base image**: python:3.12-slim
- **Dependencies**: scapy (via pip), tcpdump
- **Script**: udp_interface_forwarder.py
- **Registry**: registry.olympusdrive.com/weatherflow-udp-forwarder
- **Tags**: latest, <git-sha>

## Architecture Benefits

### Sidecar vs. Systemd Service

**Sidecar Advantages** (Current Implementation):
- ✅ Automatic co-location with collector
- ✅ No manual node setup required
- ✅ Moves automatically when pod is rescheduled
- ✅ No wasted resources on unused nodes
- ✅ Integrated with CI/CD pipeline
- ✅ Container restart policies handled by Kubernetes

**Previous Systemd Approach**:
- ❌ Required manual installation on each node
- ❌ Wasted resources running on nodes without collector
- ❌ Manual updates required on each node
- ❌ Doesn't follow pod movement

## Requirements

- **Privileged container**: Required for raw packet capture (NET_RAW, NET_ADMIN capabilities)
- **scapy**: Python packet capture library (installed via pip)
- **hostNetwork: true**: Both collector and forwarder must share host network
- **Node placement**: Runs wherever collector pod is scheduled

## Performance

- **CPU**: ~0-5m (minimal overhead)
- **Memory**: 32-70Mi (lightweight)
- **Network**: No additional latency (localhost forwarding)
- **Automatic restart**: Kubernetes restarts on failure
- **Graceful shutdown**: Handles SIGTERM/SIGINT properly

## Related Files

- `udp_interface_forwarder.py` - Forwarder Python script
- `Dockerfile.forwarder` - Container image definition
- `build-forwarder.sh` - Script to build and push forwarder image
- `k8s/base/weatherflow-deployment.yaml` - Sidecar container definition
- `docker-compose.yml` - Local development configuration
