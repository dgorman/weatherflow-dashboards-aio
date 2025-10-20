#!/bin/bash

# WeatherFlow Collector - Argo Workflow Deployment Trigger
# This script submits the Argo Workflow ON PRODUCTION to build and deploy

set -e

REMOTE_HOST="node01.olympusdrive.com"
REMOTE_USER="dgorman"

echo "========================================"
echo "WeatherFlow Collector - Argo Workflow Deploy"
echo "========================================"
echo ""
echo "🚀 Submitting Argo Workflow on production [prod]..."
echo ""

ssh ${REMOTE_USER}@${REMOTE_HOST} << 'EOF'
  set -e
  cd /home/dgorman/Apps/weatherflow-collector
  
  echo "📦 Pulling latest workflow definition from GitHub..."
  git pull origin main
  
  echo ""
  echo "🚀 Submitting Argo Workflow..."
  kubectl create -n argo -f argo/weatherflow-collector-deploy.yaml
  
  echo ""
  echo "✅ Workflow submitted!"
  echo ""
  echo "The workflow will now:"
  echo "  1. Clone from GitHub"
  echo "  2. Build Docker image"
  echo "  3. Push to registry"
  echo "  4. Deploy to Kubernetes"
  echo ""
  echo "To monitor the workflow:"
  echo "  argo list -n argo"
  echo "  argo logs -n argo @latest -f"
  echo "  argo get -n argo @latest"
EOF

echo ""
echo "To view workflow status from your browser:"
echo "  Open Argo Workflows UI at https://argo.olympusdrive.com"
echo ""
