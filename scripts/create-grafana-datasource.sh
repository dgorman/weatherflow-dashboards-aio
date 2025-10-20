#!/bin/bash

# Create InfluxDB datasource in Grafana
# This script adds the WeatherFlow InfluxDB as a datasource

set -e

GRAFANA_URL="${GRAFANA_URL:-http://grafana.olympusdrive.com}"
GRAFANA_USER="${GRAFANA_USER:-}"
GRAFANA_PASS="${GRAFANA_PASS:-}"
DATASOURCE_NAME="InfluxDB - weatherflow"
GRAFANA_PORT_FORWARD_PID=""

# Cleanup function for port-forward
cleanup() {
    if [ -n "$GRAFANA_PORT_FORWARD_PID" ]; then
        echo ""
        echo "🧹 Cleaning up port-forward (PID: $GRAFANA_PORT_FORWARD_PID)"
        kill $GRAFANA_PORT_FORWARD_PID 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Check if running on production server
if [[ $(hostname) == *"olympusdrive"* ]] || [[ $(hostname) == "node"* ]]; then
    echo "📍 Running on production server, using K8s secret for credentials"
    
    # Get credentials from K8s secret
    if command -v kubectl &> /dev/null; then
        GRAFANA_USER=$(kubectl get secret grafana-credentials -n weatherflow -o jsonpath='{.data.username}' | base64 -d)
        GRAFANA_PASS=$(kubectl get secret grafana-credentials -n weatherflow -o jsonpath='{.data.password}' | base64 -d)
        
        # Get InfluxDB configuration from deployment
        INFLUXDB_URL=$(kubectl get deployment -n weatherflow weatherflow-collector -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="WEATHERFLOW_COLLECTOR_INFLUXDB_URL")].value}')
        INFLUXDB_TOKEN=$(kubectl get deployment -n weatherflow weatherflow-collector -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="WEATHERFLOW_COLLECTOR_INFLUXDB_TOKEN")].value}')
        INFLUXDB_ORG=$(kubectl get deployment -n weatherflow weatherflow-collector -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="WEATHERFLOW_COLLECTOR_INFLUXDB_ORG")].value}')
        INFLUXDB_BUCKET=$(kubectl get deployment -n weatherflow weatherflow-collector -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="WEATHERFLOW_COLLECTOR_INFLUXDB_BUCKET")].value}')
        
        # Use port-forward to access Grafana in solardashboard namespace
        echo "🔌 Setting up port-forward to Grafana service..."
        kubectl port-forward -n solardashboard svc/grafana 8080:3000 &>/dev/null &
        GRAFANA_PORT_FORWARD_PID=$!
        sleep 3  # Wait for port-forward to establish
        GRAFANA_URL="http://localhost:8080"
        echo "   Using: $GRAFANA_URL"
    fi
else
    # Local development - prompt for values
    if [ -z "$GRAFANA_USER" ]; then
        read -p "Grafana Username: " GRAFANA_USER
    fi
    
    if [ -z "$GRAFANA_PASS" ]; then
        read -sp "Grafana Password: " GRAFANA_PASS
        echo ""
    fi
    
    read -p "InfluxDB URL [http://influxdb.weatherflow.svc.cluster.local:8086]: " INFLUXDB_URL
    INFLUXDB_URL=${INFLUXDB_URL:-http://influxdb.weatherflow.svc.cluster.local:8086}
    
    read -p "InfluxDB Token: " INFLUXDB_TOKEN
    read -p "InfluxDB Organization [weatherflow]: " INFLUXDB_ORG
    INFLUXDB_ORG=${INFLUXDB_ORG:-weatherflow}
    
    read -p "InfluxDB Bucket [weatherflow]: " INFLUXDB_BUCKET
    INFLUXDB_BUCKET=${INFLUXDB_BUCKET:-weatherflow}
fi

echo "========================================="
echo "Grafana Datasource Creation"
echo "========================================="
echo ""

# Check Grafana connectivity
echo "🔍 Checking Grafana connectivity..."
GRAFANA_CHECK=$(curl -s -o /dev/null -w "%{http_code}" -u "$GRAFANA_USER:$GRAFANA_PASS" "$GRAFANA_URL/api/org")

if [ "$GRAFANA_CHECK" != "200" ]; then
    echo "❌ Cannot connect to Grafana at $GRAFANA_URL (HTTP $GRAFANA_CHECK)"
    exit 1
fi

echo "✅ Connected to Grafana"
echo ""

# Check if datasource already exists
echo "🔍 Checking if datasource already exists..."
EXISTING_DS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" "$GRAFANA_URL/api/datasources/name/$DATASOURCE_NAME" 2>/dev/null || echo "")

if echo "$EXISTING_DS" | grep -q '"id":'; then
    DS_ID=$(echo "$EXISTING_DS" | jq -r '.id')
    echo "⚠️  Datasource '$DATASOURCE_NAME' already exists (ID: $DS_ID)"
    read -p "Update existing datasource? (y/n): " UPDATE_DS
    
    if [[ ! "$UPDATE_DS" =~ ^[Yy]$ ]]; then
        echo "❌ Aborted"
        exit 1
    fi
    
    METHOD="PUT"
    URL="$GRAFANA_URL/api/datasources/$DS_ID"
else
    echo "✅ Datasource does not exist, will create new"
    METHOD="POST"
    URL="$GRAFANA_URL/api/datasources"
fi

echo ""

# Create datasource JSON payload
# Note: InfluxDB 2.x with InfluxQL compatibility requires:
# - user = organization
# - database = bucket name
# - password = token (in secureJsonData)
# - No version specified (uses InfluxQL by default for backward compatibility)
DATASOURCE_JSON=$(cat <<EOF
{
  "name": "$DATASOURCE_NAME",
  "type": "influxdb",
  "access": "proxy",
  "url": "$INFLUXDB_URL",
  "user": "$INFLUXDB_ORG",
  "database": "$INFLUXDB_BUCKET",
  "basicAuth": false,
  "isDefault": true,
  "jsonData": {
    "httpMode": "POST",
    "organization": "$INFLUXDB_ORG",
    "defaultBucket": "$INFLUXDB_BUCKET",
    "tlsSkipVerify": true
  },
  "secureJsonData": {
    "password": "$INFLUXDB_TOKEN"
  }
}
EOF
)

# Create/Update datasource
echo "📊 ${METHOD}ing datasource: $DATASOURCE_NAME"
echo "   URL: $INFLUXDB_URL"
echo "   Organization: $INFLUXDB_ORG"
echo "   Bucket: $INFLUXDB_BUCKET"
echo ""

RESPONSE=$(curl -s -X $METHOD \
    -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASS" \
    "$URL" \
    -d "$DATASOURCE_JSON")

if echo "$RESPONSE" | grep -q '"message":"Datasource added"' || echo "$RESPONSE" | grep -q '"message":"Datasource updated"'; then
    echo "✅ Datasource created/updated successfully"
    DS_ID=$(echo "$RESPONSE" | jq -r '.datasource.id // .id')
    echo "   Datasource ID: $DS_ID"
    echo ""
    
    # Test the datasource
    echo "🧪 Testing datasource connection..."
    TEST_RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "$GRAFANA_USER:$GRAFANA_PASS" \
        "$GRAFANA_URL/api/datasources/$DS_ID/health")
    
    if echo "$TEST_RESPONSE" | grep -q '"status":"OK"'; then
        echo "✅ Datasource connection test successful"
    else
        echo "⚠️  Datasource connection test failed:"
        echo "$TEST_RESPONSE" | jq '.'
    fi
else
    echo "❌ Failed to create datasource:"
    echo "$RESPONSE" | jq '.'
    exit 1
fi

echo ""
echo "========================================="
echo "✅ Datasource Configuration Complete"
echo "========================================="
echo ""
echo "🌐 View datasources at: $GRAFANA_URL/datasources"
echo ""
