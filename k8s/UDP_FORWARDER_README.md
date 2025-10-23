# UDP Packet Forwarder

## Overview

The UDP packet forwarder solves a cross-VLAN broadcast limitation where WeatherFlow Tempest broadcasts (255.255.255.255) don't get delivered to application sockets on Kubernetes nodes in a different subnet.

## Problem

- **Tempest Location**: 192.168.1.36 (VLAN 1 "Internal")
- **K8s Nodes**: 192.168.2.x (VLAN 2 "Lab")
- **Issue**: Linux kernel doesn't deliver global broadcasts (255.255.255.255) to application sockets when source and destination are on different subnets
- **Evidence**: `tcpdump` can see packets at the interface level, but UDP sockets don't receive them

## Solution

The forwarder uses `scapy` (libpcap/BPF) to capture UDP packets at the network interface level (same mechanism as `tcpdump`), bypassing the kernel's socket delivery mechanism. It then forwards these packets to `localhost:50222` where the WeatherFlow collector is listening.

### How It Works

1. Captures UDP port 50222 packets at the interface level using scapy
2. Extracts the UDP payload from each packet
3. Forwards the payload to localhost:50222 as unicast
4. Localhost delivery works because it doesn't involve cross-subnet routing

## Installation

### Automated Deployment

Deploy to all Kubernetes nodes:

```bash
cd k8s
./deploy-udp-forwarder.sh
```

This script will:
- Install python3-scapy on each node
- Copy the forwarder script to /opt/weatherflow/
- Install and enable the systemd service
- Start the forwarder

### Manual Installation

On each Kubernetes node:

```bash
# Install dependencies
sudo apt-get update
sudo apt-get install -y python3-scapy

# Create directory
sudo mkdir -p /opt/weatherflow

# Copy forwarder script
sudo cp udp_interface_forwarder.py /opt/weatherflow/
sudo chmod +x /opt/weatherflow/udp_interface_forwarder.py

# Install systemd service
sudo cp k8s/weatherflow-udp-forwarder.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable weatherflow-udp-forwarder
sudo systemctl start weatherflow-udp-forwarder
```

## Management

### Check Status

```bash
sudo systemctl status weatherflow-udp-forwarder
```

### View Logs

```bash
# Follow logs in real-time
sudo journalctl -u weatherflow-udp-forwarder -f

# View recent logs
sudo journalctl -u weatherflow-udp-forwarder -n 100
```

### Restart Service

```bash
sudo systemctl restart weatherflow-udp-forwarder
```

### Stop Service

```bash
sudo systemctl stop weatherflow-udp-forwarder
```

### Disable Service

```bash
sudo systemctl disable weatherflow-udp-forwarder
```

## Monitoring

The forwarder logs to systemd journal with INFO level by default. Each forwarded packet is logged at DEBUG level.

To enable debug logging, edit `/etc/systemd/system/weatherflow-udp-forwarder.service` and change:

```ini
ExecStart=/usr/bin/python3 -u /opt/weatherflow/udp_interface_forwarder.py
```

to:

```ini
Environment="LOGLEVEL=DEBUG"
ExecStart=/usr/bin/python3 -u /opt/weatherflow/udp_interface_forwarder.py
```

Then reload and restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart weatherflow-udp-forwarder
```

## Troubleshooting

### Service Fails to Start

1. Check if scapy is installed:
   ```bash
   python3 -c "import scapy"
   ```

2. Verify the script has execute permissions:
   ```bash
   ls -l /opt/weatherflow/udp_interface_forwarder.py
   ```

3. Check for detailed errors:
   ```bash
   sudo journalctl -u weatherflow-udp-forwarder -n 50
   ```

### No Packets Being Forwarded

1. Verify packets are arriving at the interface:
   ```bash
   sudo tcpdump -i any -n udp port 50222
   ```

2. Check if the collector is listening:
   ```bash
   sudo lsof -i UDP:50222
   ```

3. Verify the forwarder is running:
   ```bash
   ps aux | grep udp_interface_forwarder
   ```

### Testing the Forwarder

Run the forwarder manually to see debug output:

```bash
sudo python3 -u /opt/weatherflow/udp_interface_forwarder.py
```

You should see messages like:
```
2025-10-22 22:07:13 - INFO - ============================================================
2025-10-22 22:07:13 - INFO - UDP Packet Forwarder (Interface Level)
2025-10-22 22:07:13 - INFO - ============================================================
2025-10-22 22:07:13 - INFO - Capturing UDP packets on port 50222
2025-10-22 22:07:13 - INFO - Forwarding to: 127.0.0.1:50222
```

## Requirements

- **Root privileges**: Required for packet capture at interface level
- **python3-scapy**: Packet capture library
- **Network access**: Must be running on the same node as the WeatherFlow collector pod (due to hostNetwork: true)

## Architecture Notes

- The WeatherFlow collector deployment uses `hostNetwork: true`, so the collector pod listens on the host's localhost:50222
- The forwarder must run on the same node as the collector pod to forward to localhost
- Currently deployed on all three Kubernetes nodes for redundancy
- Only the node running the collector pod will successfully forward data to the application

## Performance

- Minimal CPU overhead (packet forwarding is very lightweight)
- No memory accumulation (packets are processed and discarded immediately)
- Automatically stops when receiving SIGTERM or SIGINT
- Restarts automatically on failure (RestartSec=10)
