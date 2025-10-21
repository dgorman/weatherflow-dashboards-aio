#!/bin/bash

# Update WeatherFlow Dashboards for Single Station
# Removes station_name and tz template variables and hardcodes values

set -e

DASHBOARD_DIR="/Users/dgorman/Dev/weatherflow-collector/grafana/dashboards/weatherflow-collector"
STATION_NAME="Olympus"
TIMEZONE="America/Denver"

echo "========================================"
echo "Update Dashboards for Single Station"
echo "========================================"
echo ""
echo "Station: ${STATION_NAME}"
echo "Timezone: ${TIMEZONE}"
echo ""

# Count dashboards
DASHBOARD_COUNT=$(find "${DASHBOARD_DIR}" -name "*.json" ! -name "*.backup" | wc -l)
echo "Found ${DASHBOARD_COUNT} dashboards to update"
echo ""

# Process each dashboard
for file in "${DASHBOARD_DIR}"/*.json; do
  # Skip backup files
  if [[ "$file" == *.backup ]]; then
    continue
  fi
  
  FILENAME=$(basename "$file")
  echo -n "Processing ${FILENAME}... "
  
  # Update the dashboard JSON - first remove template variables, then replace strings
  jq --arg station "${STATION_NAME}" --arg tz "${TIMEZONE}" '
    # Remove tz and station_name variables from templating
    .templating.list |= map(select(.name != "tz" and .name != "station_name"))
  ' "${file}" | \
  jq --arg station "${STATION_NAME}" --arg tz "${TIMEZONE}" '
    # Replace $station_name and $tz in all string values throughout the JSON
    walk(
      if type == "string" then
        gsub("\\$station_name"; $station) | gsub("\\$tz"; $tz)
      else . end
    )
  ' | \
  jq '
    # Remove tz() function calls from queries as they cause grouping issues
    walk(
      if type == "string" then
        gsub(" tz\\([^)]+\\)"; "")
      else . end
    )
  ' > "${file}.tmp"
  
  # Replace original with updated version
  mv "${file}.tmp" "${file}"
  
  echo "✅"
done

echo ""
echo "✅ All dashboards updated!"
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff"
echo "  2. Import to DEV: ./scripts/import-grafana-dashboards.sh (local docker)"
echo "  3. Validate in DEV: http://localhost:3000"
echo "  4. Import to PROD: ./scripts/import-grafana-dashboards.sh (production)"
echo "  5. Validate in PROD: https://grafana.olympusdrive.com"
echo "  6. Import to Hosted: Update hosted dashboards via API"
echo ""
