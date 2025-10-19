#!/bin/bash

# WeatherFlow Collector - Build and Deploy Script
# This script builds the Docker image, pushes to registry, and deploys to Kubernetes via Argo CD

set -e

# Configuration
REGISTRY="registry.olympusdrive.com"
IMAGE_NAME="weatherflow-collector"
TAG="${1:-latest}"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"
REMOTE_HOST="node01.olympusdrive.com"
REMOTE_USER="dgorman"
REMOTE_DIR="/home/dgorman/Apps/weatherflow-collector"
ARGO_APP_NAME="weatherflow-collector"

echo "========================================"
echo "WeatherFlow Collector Deployment"
echo "========================================"
echo "Image: ${FULL_IMAGE}"
echo "Remote: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"
echo ""

# Step 1: Sync code to remote server
echo "📦 Syncing code to ${REMOTE_HOST}..."
rsync -avz --exclude 'grafana/' --exclude '.git/' --exclude 'docs/' --exclude '*.backup' \
  ./ ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/

# Step 2: Build Docker image on remote server
echo ""
echo "🔨 Building Docker image on ${REMOTE_HOST}..."
ssh ${REMOTE_USER}@${REMOTE_HOST} << EOF
  set -e
  cd ${REMOTE_DIR}
  echo "Building ${FULL_IMAGE}..."
  docker build -t ${FULL_IMAGE} .
EOF

# Step 3: Push to registry
echo ""
echo "📤 Pushing image to registry..."
ssh ${REMOTE_USER}@${REMOTE_HOST} << EOF
  set -e
  echo "Pushing ${FULL_IMAGE}..."
  docker push ${FULL_IMAGE}
EOF

# Step 4: Apply Kubernetes manifests or sync Argo CD
echo ""
echo "🚀 Deploying to Kubernetes..."
ssh ${REMOTE_USER}@${REMOTE_HOST} << EOF
  set -e
  
  # Check if Argo CD app exists
  if kubectl get application ${ARGO_APP_NAME} -n argocd >/dev/null 2>&1; then
    echo "Argo CD app '${ARGO_APP_NAME}' exists, syncing..."
    kubectl -n argocd patch app ${ARGO_APP_NAME} --type merge -p '{"spec":{"source":{"targetRevision":"main"}}}'
    argocd app sync ${ARGO_APP_NAME} --force
  else
    echo "Argo CD app '${ARGO_APP_NAME}' not found, applying manifests directly..."
    kubectl apply -k ${REMOTE_DIR}/k8s/overlays/prod
  fi
  
  echo ""
  echo "Waiting for deployment rollout..."
  kubectl rollout status deployment/weatherflow-collector -n weatherflow --timeout=300s
  kubectl rollout status deployment/influxdb -n weatherflow --timeout=300s
EOF

echo ""
echo "✅ Deployment complete!"
echo ""
echo "To check status:"
echo "  ssh ${REMOTE_USER}@${REMOTE_HOST} 'kubectl get pods -n weatherflow'"
echo ""
echo "To view logs:"
echo "  ssh ${REMOTE_USER}@${REMOTE_HOST} 'kubectl logs -f -n weatherflow -l app=weatherflow-collector'"
echo "  ssh ${REMOTE_USER}@${REMOTE_HOST} 'kubectl logs -f -n weatherflow -l app=influxdb'"
echo ""
