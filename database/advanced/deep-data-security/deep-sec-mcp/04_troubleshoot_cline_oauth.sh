#!/bin/bash
# Read-only diagnostics for Cline, OCI IAM OAuth, and Database Tools MCP.

set -uo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"
MINUTES=120
ECID=""
CLIENT_APP_ID=""
OAUTH_CLIENT_ID=""
CLIENT_APP_ID_EXPLICIT=0

usage() {
  cat <<'EOF'
Usage: ./04_troubleshoot_cline_oauth.sh [options]

Read-only diagnostic report for Cline OAuth and Database Tools MCP errors.
It prints no access tokens, refresh tokens, client secrets, or wallet passwords.

Options:
  --minutes <n>   OCI Audit lookback window in minutes. Default: 120.
  --ecid <value>  OCI IAM error correlation ID from an invalid_client page.
  --client-app-id <id>
                  OAuth public-client app ID to inspect. Default: Cline client.
  --client-id <id> OAuth client ID to search for in OCI Audit. Default: app ID.
  -h, --help      Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --minutes) MINUTES="${2:-}"; shift 2 ;;
    --ecid) ECID="${2:-}"; shift 2 ;;
    --client-app-id) CLIENT_APP_ID="${2:-}"; CLIENT_APP_ID_EXPLICIT=1; shift 2 ;;
    --client-id) OAUTH_CLIENT_ID="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo -e "${RED}ERROR: Unknown argument: $1${NC}" >&2; usage >&2; exit 2 ;;
  esac
done

if ! [[ "$MINUTES" =~ ^[1-9][0-9]*$ ]]; then
  echo -e "${RED}ERROR: --minutes must be a positive integer.${NC}" >&2
  exit 2
fi

if [ ! -f "$ENV_FILE" ]; then
  echo -e "${RED}ERROR: .deep-sec-mcp.env not found. Run ./00_configure_lab_env.sh first.${NC}" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib_oci_profile.sh"
if [ "$CLIENT_APP_ID_EXPLICIT" != 1 ]; then
  CLIENT_APP_ID="${MCP_CLINE_CLIENT_APP_ID:-}"
fi
OAUTH_CLIENT_ID="${OAUTH_CLIENT_ID:-$CLIENT_APP_ID}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo -e "${RED}ERROR: $1 is required but is not available in PATH.${NC}" >&2
    exit 1
  }
}

require_var() {
  [ -n "${!1:-}" ] || {
    echo -e "${RED}ERROR: $1 is required in .deep-sec-mcp.env.${NC}" >&2
    exit 1
  }
}

oci_query() {
  PYTHONWARNINGS="${PYTHONWARNINGS:+${PYTHONWARNINGS},}ignore::FutureWarning:urllib3.poolmanager" \
    oci_with_profile "$@"
}

section() {
  echo
  echo -e "${GREEN}============================================================================${NC}"
  echo -e "${GREEN}  $1${NC}"
  echo -e "${GREEN}============================================================================${NC}"
}

run_json_summary() {
  local label="$1"
  shift
  local response
  if ! response=$(oci_query "$@" 2>&1); then
    echo -e "${RED}ERROR: ${label} check failed.${NC}" >&2
    printf '%s\n' "$response" >&2
    return 0
  fi
  printf '%s\n' "$response"
}

require_cmd oci
require_cmd python3
require_cmd date
require_var TENANCY_OCID
require_var MCP_COMPARTMENT_OCID
require_var MCP_SERVER_ID
require_var OCI_DOMAIN_URL

start_time=$(date -u -d "${MINUTES} minutes ago" '+%Y-%m-%dT%H:%M:00Z')
end_time=$(date -u '+%Y-%m-%dT%H:%M:00Z')

section 'Troubleshoot Database Tools MCP client connection'
echo -e "${CYAN}OCI profile       = ${OCI_PROFILE_SELECTED:-DEFAULT}${NC}"
echo -e "${CYAN}Audit window      = ${start_time} to ${end_time}${NC}"
echo -e "${CYAN}MCP server        = ${MCP_SERVER_ID}${NC}"
echo -e "${CYAN}Identity domain   = ${OCI_DOMAIN_URL}${NC}"
[ -n "$ECID" ] && echo -e "${CYAN}OCI IAM ECID      = ${ECID}${NC}"
echo 'This report is read-only and intentionally excludes OAuth tokens and secrets.'

section '1. MCP server status and endpoint'
run_json_summary 'MCP server' dbtools mcp-server get --mcp-server-id "$MCP_SERVER_ID" --output json | \
  python3 -c 'import json,sys
try:
 d=json.load(sys.stdin).get("data") or {}
 print(json.dumps({"name": d.get("display-name"), "state": d.get("lifecycle-state"), "runtime_identity": d.get("runtime-identity"), "domain_app_id": d.get("domain-app-id"), "domain_id": d.get("domain-id"), "endpoints": d.get("endpoints")}, indent=2))
except Exception as exc:
 print("Unable to summarize MCP server response: " + str(exc), file=sys.stderr)'

if [ -z "$CLIENT_APP_ID" ]; then
  echo -e "${YELLOW}INFO: No Identity Domains application ID was supplied.${NC}"
  echo 'This is expected for a client registered from the Database Tools MCP Server Clients tab.'
else
  section '2. Cline public OAuth client registration'
  run_json_summary 'Cline public client' identity-domains app get \
    --endpoint "$OCI_DOMAIN_URL" \
    --app-id "$CLIENT_APP_ID" \
    --attribute-sets all \
    --output json | python3 -c 'import json,sys
try:
 d=json.load(sys.stdin).get("data") or {}
 print(json.dumps({"app_id": d.get("id"), "name": d.get("display-name"), "active": d.get("active"), "client_type": d.get("client-type"), "oauth_client": d.get("is-o-auth-client"), "oauth_resource": d.get("is-o-auth-resource"), "allowed_grants": d.get("allowed-grants"), "allowed_operations": d.get("allowed-operations"), "allowed_scopes": d.get("allowed-scopes"), "redirect_uris": d.get("redirect-uris"), "all_url_schemes_allowed": d.get("all-url-schemes-allowed")}, indent=2))
except Exception as exc:
 print("Unable to summarize public-client response: " + str(exc), file=sys.stderr)'
fi

section '3. Local Cline configuration and runtime'
if [ -f "${SCRIPT_DIR}/cline_mcp_settings.generated.json" ]; then
  echo "Generated configuration: ${SCRIPT_DIR}/cline_mcp_settings.generated.json"
  python3 - "${SCRIPT_DIR}/cline_mcp_settings.generated.json" <<'PY'
import json
import sys

try:
    server = json.load(open(sys.argv[1], encoding="utf-8"))["mcpServers"]["deep-sec-mcp"]
    args = server.get("args") or []
    endpoint = args[2] if len(args) > 2 else None
    print(json.dumps({"command": server.get("command"), "endpoint": endpoint, "transport": "http-only" if "http-only" in args else None, "has_static_client_id": "--static-oauth-client-info" in args, "has_static_scope": "--static-oauth-client-metadata" in args}, indent=2))
except Exception as exc:
    print("Unable to summarize generated Cline configuration: " + str(exc), file=sys.stderr)
PY
else
  echo -e "${YELLOW}WARNING: cline_mcp_settings.generated.json is absent. Run ./create_cline_mcp_config.sh.${NC}"
fi
if [ -x "${SCRIPT_DIR}/03_verify_cline_runtime.sh" ]; then
  "${SCRIPT_DIR}/03_verify_cline_runtime.sh" || true
fi

audit_summary() {
  local label="$1"
  local compartment_id="$2"
  section "$label"
  if ! oci_query audit event list \
    --compartment-id "$compartment_id" \
    --start-time "$start_time" \
    --end-time "$end_time" \
    --all \
    --output json | python3 -c '
import json
import sys

server_id, client_id = sys.argv[1:]
try:
    events = json.load(sys.stdin).get("data") or []
except Exception as exc:
    print("Unable to read OCI Audit response: " + str(exc), file=sys.stderr)
    raise SystemExit(1)

selected = []
for event in events:
    serialized = json.dumps(event).lower()
    event_type = (event.get("event-type") or "").lower()
    if not (
        "invokemcpserver" in event_type
        or "oauth" in serialized
        or "sso." in serialized
        or (client_id and client_id.lower() in serialized)
    ):
        continue
    data = event.get("data") or {}
    details = data.get("additionalDetails") or {}
    selected.append({
        "time_utc": event.get("event-time"),
        "event_type": event.get("event-type"),
        "identity_event_id": details.get("eventId"),
        "actor": details.get("actorName"),
        "target": details.get("adminResourceName"),
        "request_id": details.get("opcRequestId") or details.get("opc-request-id"),
        "audit_event_id": event.get("event-id"),
    })

if selected:
    print(json.dumps(selected, indent=2))
else:
    print("No matching MCP invocation, OAuth, or SSO events found in this audit window.")
    print("OCI Audit can be delayed. For Identity Domains OAuth details, also check Domain > Reports > Audit Log for Application access failed.")
' "$MCP_SERVER_ID" "$OAUTH_CLIENT_ID"
  then
    echo -e "${RED}ERROR: OCI Audit query failed for this compartment.${NC}" >&2
  fi
}

audit_summary '4. OCI Audit: MCP compartment' "$MCP_COMPARTMENT_OCID"
if [ "$TENANCY_OCID" != "$MCP_COMPARTMENT_OCID" ]; then
  audit_summary '5. OCI Audit: tenancy root / Identity Domain compartment' "$TENANCY_OCID"
fi

section 'Next actions when OAuth succeeds but no MCP tools appear'
echo '1. A successful OCI IAM consent page plus InvokeMcpServer audit records proves the client reached Database Tools.'
echo '2. Verify that the built-in SQL toolset is ACTIVE and attached to this exact MCP server.'
echo '3. In the Database Tools console, review the MCP Server, its connection, and its toolset configuration.'
echo '4. Preserve the client error reference and OCI Audit event IDs for Oracle Support if the server remains ACTIVE but tool discovery fails.'
