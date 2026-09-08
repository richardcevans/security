#!/bin/bash
# Read-only status for the DeepSec MCP Database Tools connection and its work requests.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"
[ -f "$ENV_FILE" ] || { echo 'ERROR: .deep-sec-mcp.env not found.' >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib_oci_profile.sh"

for name in MCP_COMPARTMENT_OCID DATABASE_TOOLS_CONNECTION_ID; do
  [ -n "${!name:-}" ] || { echo "ERROR: $name is required." >&2; exit 1; }
done

oci_query() { oci_with_profile "$@"; }

echo
echo '============================================================================'
echo '  Database Tools Connection Status'
echo '============================================================================'
echo
echo "Connection  = $DATABASE_TOOLS_CONNECTION_ID"
echo "Compartment = $MCP_COMPARTMENT_OCID"
echo

echo 'Current connection configuration'
oci_query dbtools connection get \
  --connection-id "$DATABASE_TOOLS_CONNECTION_ID" \
  --query 'data.{state:"lifecycle-state",details:"lifecycle-details",runtime_identity:"runtime-identity",key_stores:"key-stores",updated:"time-updated"}' \
  --output json

echo
echo 'Most recent work requests for this connection'
work_requests=$(oci_query dbtools work-request list \
  --compartment-id "$MCP_COMPARTMENT_OCID" \
  --resource-identifier "$DATABASE_TOOLS_CONNECTION_ID" \
  --sort-by timeUpdated \
  --sort-order DESC \
  --limit 10 \
  --output json)
printf '%s\n' "$work_requests" | python3 -c '
import json, sys
data = json.load(sys.stdin).get("data") or []
if isinstance(data, dict):
    data = data.get("items") or []
if not data:
    print("No Database Tools work requests found for this connection.")
else:
    for item in data:
        print(json.dumps({
            "id": item.get("id"),
            "operation": item.get("operation-type"),
            "status": item.get("status"),
            "percent_complete": item.get("percent-complete"),
            "accepted": item.get("time-accepted"),
            "updated": item.get("time-updated"),
            "finished": item.get("time-finished"),
        }, indent=2))'

failed_ids=$(printf '%s\n' "$work_requests" | python3 -c '
import json, sys
data = json.load(sys.stdin).get("data") or []
if isinstance(data, dict):
    data = data.get("items") or []
for item in data:
    if item.get("status") in {"FAILED", "NEEDS_ATTENTION"} and item.get("id"):
        print(item["id"])')
if [ -n "$failed_ids" ]; then
  echo
  echo 'Errors for failed or attention-required work requests'
  while IFS= read -r request_id; do
    [ -n "$request_id" ] || continue
    echo "Work request: $request_id"
    oci_query dbtools work-request-error list --work-request-id "$request_id" --all --output json
  done <<< "$failed_ids"
fi
