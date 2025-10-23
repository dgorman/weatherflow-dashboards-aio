#!/bin/bash
#
# Deploy WeatherFlow UDP Forwarder to Kubernetes nodes
# This script installs the forwarder as a systemd service on each node
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORWARDER_SCRIPT="${SCRIPT_DIR}/../udp_interface_forwarder.py"
SERVICE_FILE="${SCRIPT_DIR}/weatherflow-udp-forwarder.service"
INSTALL_DIR="/opt/weatherflow"
SERVICE_NAME="weatherflow-udp-forwarder"

# Production nodes (adjust as needed)
NODES=(
    "dgorman@192.168.2.22"  # node01
    "dgorman@192.168.2.23"  # node02
    "dgorman@192.168.2.24"  # node03
)

echo "=========================================="
echo "WeatherFlow UDP Forwarder Deployment"
echo "=========================================="
echo ""

for NODE in "${NODES[@]}"; do
    echo "Deploying to ${NODE}..."
    
    # Create installation directory
    ssh "${NODE}" "sudo mkdir -p ${INSTALL_DIR}"
    
    # Check if scapy is installed
    echo "  - Checking dependencies..."
    if ! ssh "${NODE}" "python3 -c 'import scapy' 2>/dev/null"; then
        echo "  - Installing python3-scapy..."
        ssh "${NODE}" "sudo apt-get update -qq && sudo apt-get install -y python3-scapy"
    else
        echo "  - Dependencies OK"
    fi
    
    # Copy forwarder script
    echo "  - Copying forwarder script..."
    scp "${FORWARDER_SCRIPT}" "${NODE}:${INSTALL_DIR}/udp_interface_forwarder.py"
    ssh "${NODE}" "sudo chmod +x ${INSTALL_DIR}/udp_interface_forwarder.py"
    
    # Copy systemd service file
    echo "  - Installing systemd service..."
    scp "${SERVICE_FILE}" "${NODE}:/tmp/${SERVICE_NAME}.service"
    ssh "${NODE}" "sudo mv /tmp/${SERVICE_NAME}.service /etc/systemd/system/"
    ssh "${NODE}" "sudo chmod 644 /etc/systemd/system/${SERVICE_NAME}.service"
    
    # Reload systemd and enable service
    echo "  - Enabling and starting service..."
    ssh "${NODE}" "sudo systemctl daemon-reload"
    ssh "${NODE}" "sudo systemctl enable ${SERVICE_NAME}"
    ssh "${NODE}" "sudo systemctl restart ${SERVICE_NAME}"
    
    # Check status
    echo "  - Checking service status..."
    if ssh "${NODE}" "sudo systemctl is-active --quiet ${SERVICE_NAME}"; then
        echo "  ✓ Service running on ${NODE}"
    else
        echo "  ✗ Service failed to start on ${NODE}"
        ssh "${NODE}" "sudo systemctl status ${SERVICE_NAME} --no-pager -l"
    fi
    
    echo ""
done

echo "=========================================="
echo "Deployment complete!"
echo ""
echo "To check logs on a node:"
echo "  ssh <node> sudo journalctl -u ${SERVICE_NAME} -f"
echo ""
echo "To restart on a node:"
echo "  ssh <node> sudo systemctl restart ${SERVICE_NAME}"
echo "=========================================="
