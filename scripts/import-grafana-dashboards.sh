#!/bin/bash

# Import WeatherFlow Dashboards to Grafana
# This script creates a "Weather" folder and imports all dashboards

set -e

GRAFANA_URL="${GRAFANA_URL:-http://grafana.olympusdrive.com}"
GRAFANA_USER="${GRAFANA_USER:-}"
GRAFANA_PASS="${GRAFANA_PASS:-}"
DASHBOARD_DIR="/Users/dgorman/Dev/weatherflow-collector/grafana/dashboards/weatherflow-collector"
FOLDER_NAME="Weather"

# Check if running on production server
if [[ $(hostname) == *"olympusdrive"* ]] || [[ $(hostname) == "node"* ]]; then
    echo "📍 Running on production server, using K8s secret for credentials"
    DASHBOARD_DIR="/home/dgorman/Apps/weatherflow-collector/grafana/dashboards/weatherflow-collector"
    
    # Get credentials from K8s secret
    if command -v kubectl &> /dev/null; then
        GRAFANA_USER=$(kubectl get secret grafana-credentials -n weatherflow -o jsonpath='{.data.username}' | base64 -d)
        GRAFANA_PASS=$(kubectl get secret grafana-credentials -n weatherflow -o jsonpath='{.data.password}' | base64 -d)
    fi
fi

# Prompt for credentials if not provided and not on production
if [ -z "$GRAFANA_USER" ]; then
    read -p "Grafana Username: " GRAFANA_USER
fi

if [ -z "$GRAFANA_PASS" ]; then
    read -sp "Grafana Password: " GRAFANA_PASS
    echo ""
fi

echo "========================================="
echo "WeatherFlow Dashboard Import to Grafana"
echo "========================================="
echo ""

# Function to create folder
create_folder() {
    echo "📁 Creating folder: $FOLDER_NAME"
    
    FOLDER_RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "$GRAFANA_USER:$GRAFANA_PASS" \
        "$GRAFANA_URL/api/folders" \
        -d "{\"title\":\"$FOLDER_NAME\"}")
    
    FOLDER_UID=$(echo $FOLDER_RESPONSE | grep -o '"uid":"[^"]*"' | sed 's/"uid":"\([^"]*\)"/\1/')
    
    if [ -z "$FOLDER_UID" ]; then
        # Folder might already exist, try to get it
        echo "   Folder might already exist, fetching..."
        FOLDER_RESPONSE=$(curl -s -X GET \
            -u "$GRAFANA_USER:$GRAFANA_PASS" \
            "$GRAFANA_URL/api/folders")
        
        FOLDER_UID=$(echo $FOLDER_RESPONSE | grep -o "\"uid\":\"[^\"]*\",\"title\":\"$FOLDER_NAME\"" | sed 's/.*"uid":"\([^"]*\)".*/\1/')
    fi
    
    if [ -z "$FOLDER_UID" ]; then
        echo "❌ Failed to create or find folder"
        exit 1
    fi
    
    echo "✅ Folder UID: $FOLDER_UID"
    echo "$FOLDER_UID"
}

# Function to import dashboard
import_dashboard() {
    local file=$1
    local folder_uid=$2
    local filename=$(basename "$file")
    local dashboard_name=$(echo "$filename" | sed 's/weatherflow_collector-//g' | sed 's/-influxdb.json//g' | sed 's/_/ /g' | sed 's/\b\(.\)/\u\1/g')
    
    echo "📊 Importing: $dashboard_name"
    
    # Read dashboard JSON
    DASHBOARD_JSON=$(cat "$file")
    
    # Create import payload
    IMPORT_PAYLOAD=$(cat <<EOF
{
  "dashboard": $DASHBOARD_JSON,
  "folderUid": "$folder_uid",
  "overwrite": true,
  "message": "Imported via script"
}
EOF
)
    
    # Import dashboard
    IMPORT_RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "$GRAFANA_USER:$GRAFANA_PASS" \
        "$GRAFANA_URL/api/dashboards/db" \
        -d "$IMPORT_PAYLOAD")
    
    if echo "$IMPORT_RESPONSE" | grep -q '"status":"success"'; then
        DASHBOARD_URL=$(echo $IMPORT_RESPONSE | grep -o '"url":"[^"]*"' | sed 's/"url":"\([^"]*\)"/\1/')
        echo "   ✅ Success: $GRAFANA_URL$DASHBOARD_URL"
        return 0
    else
        echo "   ❌ Failed: $(echo $IMPORT_RESPONSE | head -c 200)"
        return 1
    fi
}

# Main execution
echo "🔍 Checking Grafana connectivity..."
GRAFANA_CHECK=$(curl -s -o /dev/null -w "%{http_code}" -u "$GRAFANA_USER:$GRAFANA_PASS" "$GRAFANA_URL/api/org")

if [ "$GRAFANA_CHECK" != "200" ]; then
    echo "❌ Cannot connect to Grafana at $GRAFANA_URL (HTTP $GRAFANA_CHECK)"
    exit 1
fi

echo "✅ Connected to Grafana"
echo ""

# Create folder
FOLDER_UID=$(create_folder)
echo ""

# Import all dashboards
echo "📦 Importing dashboards..."
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

for dashboard in "$DASHBOARD_DIR"/*.json; do
    # Skip backup files
    if [[ "$dashboard" == *".backup"* ]]; then
        continue
    fi
    
    if import_dashboard "$dashboard" "$FOLDER_UID"; then
        ((SUCCESS_COUNT++))
    else
        ((FAIL_COUNT++))
    fi
    echo ""
done

echo "========================================="
echo "Import Summary"
echo "========================================="
echo "✅ Successfully imported: $SUCCESS_COUNT dashboards"
echo "❌ Failed: $FAIL_COUNT dashboards"
echo ""
echo "🌐 View dashboards at: $GRAFANA_URL/dashboards"
echo ""
