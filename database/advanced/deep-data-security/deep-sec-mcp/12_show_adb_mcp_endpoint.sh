#!/bin/bash
# Show and verify the native Autonomous AI Database MCP endpoint.
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"

[ -f "$ENV_FILE" ] || { echo -e "${RED}ERROR: .deep-sec-mcp.env not found. Run ./00_configure_lab_env.sh first.${NC}" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib_oci_profile.sh"

for command in oci python3 perl; do
  command -v "$command" >/dev/null || { echo -e "${RED}ERROR: $command is required.${NC}" >&2; exit 1; }
done
[ -n "${ADB_OCID:-}" ] || { echo -e "${RED}ERROR: ADB_OCID is required in .deep-sec-mcp.env.${NC}" >&2; exit 1; }

adb_json=$(oci_with_profile db autonomous-database get --autonomous-database-id "$ADB_OCID" --output json)
readarray -t values < <(ADB_JSON="$adb_json" ADB_MCP_FEATURE_TAG="${ADB_MCP_FEATURE_TAG:-adb\$feature}" python3 - <<'PY'
import json
import os
data = json.loads(os.environ['ADB_JSON'])['data']
tags = data.get('freeform-tags') or {}
print(data.get('db-name') or '')
print(data.get('lifecycle-state') or '')
print(data.get('region') or '')
print(tags.get(os.environ['ADB_MCP_FEATURE_TAG']) or '')
PY
)
db_name=${values[0]}
state=${values[1]}
region=${values[2]}
feature=${values[3]}
[ -n "$region" ] || region="${ADB_MCP_REGION:-}"
[ -n "$region" ] || region="${OCI_CLI_REGION:-${OCI_REGION:-}}"
if [ -z "$region" ]; then
  # The ADB GET response does not consistently include a region field. Use the
  # selected OCI CLI profile (or DEFAULT when no profile was selected).
  config_file="${OCI_CONFIG_FILE:-${OCI_CLI_CONFIG_FILE:-${HOME}/.oci/config}}"
  profile_name="${OCI_PROFILE_SELECTED:-DEFAULT}"
  if [ -r "$config_file" ]; then
    region=$(awk -v profile="$profile_name" '
      /^\[/{ active = (substr($0, 2, length($0) - 2) == profile); next }
      active && /^[[:space:]]*region[[:space:]]*=/ {
        sub(/^[^=]*=/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit
      }
    ' "$config_file")
  fi
fi
if [ -z "$region" ] && [ -n "${TENANCY_OCID:-}" ]; then
  # Fall back to the OCI region subscriptions. The region key is encoded in
  # the ADB OCID (for example, iad maps to us-ashburn-1).
  subscriptions=$(oci_with_profile iam region-subscription list --tenancy-id "$TENANCY_OCID" --output json)
  region=$(SUBSCRIPTIONS="$subscriptions" ADB_OCID="$ADB_OCID" python3 - <<'PY'
import json
import os

parts = os.environ['ADB_OCID'].split('.')
key = parts[3].lower() if len(parts) > 3 else ''
items = json.loads(os.environ['SUBSCRIPTIONS']).get('data') or []
for item in items:
    if (item.get('region-key') or '').lower() == key:
        print(item.get('region-name') or '')
        break
PY
)
fi
[ -n "$region" ] || { echo -e "${RED}ERROR: Could not determine the ADB region.${NC}" >&2; exit 1; }

enabled=$(FEATURE="$feature" python3 - <<'PY'
import json
import os
try:
    value = json.loads(os.environ['FEATURE'])
    print('true' if value == {'name': 'mcp_server', 'enable': True} else 'false')
except (json.JSONDecodeError, TypeError):
    print('false')
PY
)
endpoint="https://dataaccess.adb.${region}.oraclecloudapps.com/adb/mcp/v1/databases/${ADB_OCID}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}  Native Autonomous AI Database MCP Endpoint                              ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo "ADB name = $db_name"
echo "ADB state = $state"
echo "Region    = $region"
echo "Feature   = ${feature:-<absent>}"
echo "Endpoint  = $endpoint"
echo
if [ "$state" != AVAILABLE ] || [ "$enabled" != true ]; then
  echo -e "${YELLOW}NOT READY: Native ADB MCP Server is not enabled yet.${NC}" >&2
  echo 'Run ./11_enable_adb_mcp_server.sh, then rerun this verifier.' >&2
  exit 1
fi

for pair in "ADB_MCP_REGION=$region" "ADB_MCP_ENDPOINT=$endpoint" "ADB_MCP_ENABLED=1"; do
  key=${pair%%=*}; value=${pair#*=}
  if grep -q "^export ${key}=" "$ENV_FILE"; then
    perl -pi -e "s|^export ${key}=.*|export ${key}=\"${value}\"|" "$ENV_FILE"
  else
    printf 'export %s="%s"\n' "$key" "$value" >> "$ENV_FILE"
  fi
done

echo -e "${GREEN}PASS: Native ADB MCP Server is enabled and the endpoint has been recorded in .deep-sec-mcp.env.${NC}"
echo 'This verifies enablement only. It does not prove client authentication, tool visibility, or OCI IAM identity propagation.'
echo 'Next: register a narrow read-only Select AI Agent tool before connecting a client.'
