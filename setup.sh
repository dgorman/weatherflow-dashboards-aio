#!/bin/bash

# Initial setup script for WeatherFlow Collector on prod
# Run this once to create the Argo CD application

set -e

REMOTE_HOST="node01.olympusdrive.com"
REMOTE_USER="dgorman"
REMOTE_DIR="/home/dgorman/Apps/weatherflow-collector"

echo "========================================"
echo "WeatherFlow Collector - Initial Setup"
echo "========================================"
echo ""

# Step 1: Sync code to remote server
echo "📦 Syncing code to ${REMOTE_HOST}..."
rsync -avz --exclude '.git/' --exclude 'grafana/' --exclude 'docs/' --exclude '*.backup' \
  ./ ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/

# Step 2: Create Argo CD application
echo ""
echo "🔧 Creating Argo CD application..."
ssh ${REMOTE_USER}@${REMOTE_HOST} << 'EOF'
  set -e
  cd /home/dgorman/Apps/weatherflow-collector
  
  echo "Applying Argo CD application..."
  kubectl apply -f k8s/argocd-application.yaml
  
  echo ""
  echo "Waiting for application to be created..."
  sleep 5
  
  echo ""
  echo "Application status:"
  argocd app get weatherflow-collector || echo "Argo CD app created, run initial sync manually"
EOF

echo ""
echo "✅ Initial setup complete!"
echo ""
echo "Next steps:"
echo "  1. Run ./deploy.sh to build and push the first image"
echo "  2. Check status: ssh ${REMOTE_USER}@${REMOTE_HOST} 'kubectl get pods -n weatherflow'"
echo "  3. Import Grafana dashboards manually from grafana/dashboards/weatherflow-collector/"
echo ""
