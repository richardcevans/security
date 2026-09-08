#!/bin/bash
# Enable the native Autonomous AI Database MCP Server for the ADB used by this lab.
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"
ACCEPT=false

usage() {
  cat <<'EOF'
Usage: ./11_enable_adb_mcp_server.sh [--accept]

Enables the native Autonomous AI Database MCP Server by setting this ADB's
free-form tag:
  adb$feature={"name":"mcp_server","enable":true}

All other existing free-form tags are retained. The script displays the exact
ADB and tag update before requiring ENABLE, unless --accept is supplied.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --accept) ACCEPT=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo -e "${RED}ERROR: Unknown argument: $1${NC}" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

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
readarray -t adb_values < <(ADB_JSON="$adb_json" ADB_MCP_FEATURE_TAG="${ADB_MCP_FEATURE_TAG:-adb\$feature}" python3 - <<'PY'
import json
import os
data = json.loads(os.environ['ADB_JSON'])['data']
tags = data.get('freeform-tags') or {}
key = os.environ['ADB_MCP_FEATURE_TAG']
print(data.get('db-name') or '')
print(data.get('lifecycle-state') or '')
print(json.dumps(tags, separators=(',', ':')))
print(tags.get(key) or '')
PY
)
db_name=${adb_values[0]}
state=${adb_values[1]}
existing_tags=${adb_values[2]}
existing_feature=${adb_values[3]}

if [ "$state" != AVAILABLE ]; then
  echo -e "${RED}ERROR: ADB ${db_name} is ${state}; it must be AVAILABLE before enabling MCP.${NC}" >&2
  exit 1
fi

updated_tags=$(EXISTING_TAGS="$existing_tags" ADB_MCP_FEATURE_TAG="${ADB_MCP_FEATURE_TAG:-adb\$feature}" python3 - <<'PY'
import json
import os
tags = json.loads(os.environ['EXISTING_TAGS'])
tags[os.environ['ADB_MCP_FEATURE_TAG']] = json.dumps({'name': 'mcp_server', 'enable': True}, separators=(',', ':'))
print(json.dumps(tags, separators=(',', ':')))
PY
)
already_enabled=$(EXISTING_FEATURE="$existing_feature" python3 - <<'PY'
import json
import os
try:
    value = json.loads(os.environ['EXISTING_FEATURE'])
    print('true' if value == {'name': 'mcp_server', 'enable': True} else 'false')
except (json.JSONDecodeError, TypeError):
    print('false')
PY
)

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}  Enable Native Autonomous AI Database MCP Server                          ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo "ADB name  = $db_name"
echo "ADB OCID  = $ADB_OCID"
echo "Tag       = ${ADB_MCP_FEATURE_TAG:-adb\$feature}"
echo "Current   = ${existing_feature:-<absent>}"
echo 'Requested = {"name":"mcp_server","enable":true}'
echo
if [ "$already_enabled" = true ]; then
  echo -e "${GREEN}PASS: Native ADB MCP Server is already enabled for this database.${NC}"
  exit 0
fi
echo 'Planned OCI change: update only this ADB free-form tag; existing free-form tags remain unchanged.'
if [ "$ACCEPT" != true ]; then
  read -r -p 'Type ENABLE to continue: ' answer
  [ "$answer" = ENABLE ] || { echo 'No resources were changed.'; exit 0; }
fi
echo 'Enabling native ADB MCP Server (waits for the ADB update to complete)'
oci_with_profile db autonomous-database update \
  --autonomous-database-id "$ADB_OCID" \
  --freeform-tags "$updated_tags" \
  --force \
  --wait-for-state AVAILABLE >/dev/null
if grep -q '^export ADB_MCP_ENABLED=' "$ENV_FILE"; then
  perl -pi -e 's|^export ADB_MCP_ENABLED=.*|export ADB_MCP_ENABLED="1"|' "$ENV_FILE"
else
  printf 'export ADB_MCP_ENABLED="1"\n' >> "$ENV_FILE"
fi
echo -e "${GREEN}Native ADB MCP Server is enabled.${NC}"
echo 'Next: run ./12_show_adb_mcp_endpoint.sh'
