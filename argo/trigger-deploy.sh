#!/bin/bash

# WeatherFlow Collector - Argo Workflow Deployment Trigger
# This script submits the Argo Workflow to build and deploy the application

set -e

REMOTE_HOST="node01.olympusdrive.com"
REMOTE_USER="dgorman"
WORKFLOW_FILE="argo/weatherflow-collector-deploy.yaml"

echo "========================================"
echo "WeatherFlow Collector - Argo Workflow Deploy"
echo "========================================"
echo ""

# Check if running on remote or local
if [ "$(hostname)" = "node01.olympusdrive.com" ]; then
  # Running on production server
  echo "🚀 Submitting Argo Workflow..."
  kubectl create -n argo -f ${WORKFLOW_FILE}
  
  echo ""
  echo "✅ Workflow submitted!"
  echo ""
  echo "To monitor the workflow:"
  echo "  argo list -n argo"
  echo "  argo logs -n argo @latest -f"
  echo "  argo get -n argo @latest"
else
  # Running from local machine
  echo "📦 This script should be run on ${REMOTE_HOST}"
  echo "Connecting to remote server..."
  echo ""
  
  ssh ${REMOTE_USER}@${REMOTE_HOST} << 'EOF'
    set -e
    cd /home/dgorman/Apps/weatherflow-collector
    
    echo "🚀 Submitting Argo Workflow..."
    kubectl create -n argo -f argo/weatherflow-collector-deploy.yaml
    
    echo ""
    echo "✅ Workflow submitted!"
    echo ""
    echo "To monitor the workflow:"
    echo "  ssh dgorman@node01.olympusdrive.com 'argo list -n argo'"
    echo "  ssh dgorman@node01.olympusdrive.com 'argo logs -n argo @latest -f'"
    echo "  ssh dgorman@node01.olympusdrive.com 'argo get -n argo @latest'"
EOF
fi

echo ""
echo "To view workflow status from your browser:"
echo "  Open Argo Workflows UI at https://argo.olympusdrive.com"
echo ""
