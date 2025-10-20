#!/bin/bash

# WeatherFlow InfluxDB - Restore from Backup
# Run this on production AFTER the InfluxDB pod is running

set -e

REMOTE_HOST="node01.olympusdrive.com"
REMOTE_USER="dgorman"

echo "========================================"
echo "WeatherFlow InfluxDB - Restore Backup"
echo "========================================"
echo ""

ssh ${REMOTE_USER}@${REMOTE_HOST} << 'EOF'
  set -e
  
  echo "📦 Checking for InfluxDB pod..."
  POD_NAME=$(kubectl get pod -n weatherflow -l app=influxdb -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  
  if [ -z "$POD_NAME" ]; then
    echo "❌ ERROR: No InfluxDB pod found!"
    echo "Deploy the application first, then run this script."
    exit 1
  fi
  
  echo "Found pod: ${POD_NAME}"
  echo ""
  
  echo "⏳ Waiting for InfluxDB pod to be ready..."
  kubectl wait --for=condition=ready pod -l app=influxdb -n weatherflow --timeout=300s
  
  echo ""
  echo "📥 Copying backup to pod..."
  kubectl cp /tmp/weatherflow-backup ${POD_NAME}:/tmp/backup -n weatherflow
  
  echo ""
  echo "🔄 Restoring backup..."
  kubectl exec -n weatherflow ${POD_NAME} -- influx restore \
    --host http://localhost:8086 \
    --token weatherflow-admin-token-12345 \
    --org weatherflow \
    /tmp/backup
  
  echo ""
  echo "✅ Restore complete!"
  echo ""
  echo "To verify data:"
  echo "  kubectl port-forward -n weatherflow svc/influxdb 8086:8086"
  echo "  Then open http://localhost:8086"
  echo ""
EOF

echo "✅ Done! Your production InfluxDB now has all the dev data."
echo ""
