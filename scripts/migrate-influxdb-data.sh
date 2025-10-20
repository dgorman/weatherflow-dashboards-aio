#!/bin/bash

# WeatherFlow InfluxDB Data Migration Script
# Migrates data from local dev InfluxDB to production InfluxDB

set -e

# Configuration
LOCAL_INFLUXDB_URL="http://localhost:8086"
LOCAL_INFLUXDB_TOKEN="weatherflow-admin-token-12345"
LOCAL_INFLUXDB_ORG="weatherflow"
LOCAL_INFLUXDB_BUCKET="weatherflow"

PROD_INFLUXDB_SERVICE="influxdb.weatherflow.svc.cluster.local"
PROD_INFLUXDB_URL="http://${PROD_INFLUXDB_SERVICE}:8086"
PROD_INFLUXDB_TOKEN="weatherflow-admin-token-12345"
PROD_INFLUXDB_ORG="weatherflow"
PROD_INFLUXDB_BUCKET="weatherflow"

REMOTE_HOST="node01.olympusdrive.com"
REMOTE_USER="dgorman"

BACKUP_DIR="/tmp/weatherflow-influxdb-backup-$(date +%Y%m%d-%H%M%S)"

echo "========================================"
echo "WeatherFlow InfluxDB Data Migration"
echo "========================================"
echo ""
echo "📦 Step 1: Backing up local InfluxDB data..."
echo ""

# Create backup directory
mkdir -p ${BACKUP_DIR}

# Export data from local InfluxDB
docker exec wxfdashboardsaio_influxdb influx backup \
  --host ${LOCAL_INFLUXDB_URL} \
  --token ${LOCAL_INFLUXDB_TOKEN} \
  --org ${LOCAL_INFLUXDB_ORG} \
  /tmp/backup

# Copy backup from container to local filesystem
docker cp wxfdashboardsaio_influxdb:/tmp/backup ${BACKUP_DIR}/

echo "✅ Local backup complete: ${BACKUP_DIR}"
echo ""
echo "📤 Step 2: Transferring backup to production..."
echo ""

# Transfer to production server
rsync -avz --progress ${BACKUP_DIR}/ ${REMOTE_USER}@${REMOTE_HOST}:/tmp/weatherflow-backup/

echo "✅ Transfer complete"
echo ""
echo "📥 Step 3: Restoring to production InfluxDB..."
echo ""

# Restore on production
ssh ${REMOTE_USER}@${REMOTE_HOST} << 'ENDSSH'
  set -e
  
  # Wait for InfluxDB pod to be ready
  echo "Waiting for InfluxDB pod to be ready..."
  kubectl wait --for=condition=ready pod -l app=influxdb -n weatherflow --timeout=300s
  
  # Get the InfluxDB pod name
  POD_NAME=$(kubectl get pod -n weatherflow -l app=influxdb -o jsonpath='{.items[0].metadata.name}')
  
  echo "Found InfluxDB pod: ${POD_NAME}"
  
  # Copy backup to pod
  echo "Copying backup to pod..."
  kubectl cp /tmp/weatherflow-backup ${POD_NAME}:/tmp/backup -n weatherflow
  
  # Restore the backup
  echo "Restoring backup..."
  kubectl exec -n weatherflow ${POD_NAME} -- influx restore \
    --host http://localhost:8086 \
    --token weatherflow-admin-token-12345 \
    --org weatherflow \
    /tmp/backup
  
  echo "✅ Restore complete!"
  
  # Clean up
  rm -rf /tmp/weatherflow-backup
ENDSSH

echo ""
echo "✅ Migration complete!"
echo ""
echo "To verify:"
echo "  ssh ${REMOTE_USER}@${REMOTE_HOST} 'kubectl port-forward -n weatherflow svc/influxdb 8086:8086'"
echo "  Then open http://localhost:8086 and check the data"
echo ""
echo "Backup saved locally at: ${BACKUP_DIR}"
echo ""
