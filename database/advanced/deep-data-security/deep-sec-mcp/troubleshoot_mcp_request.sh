#!/bin/bash
# Troubleshoot an OCI Database Tools MCP request from an opc-request-id.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"

usage() {
  cat <<'EOF'
Usage:
  ./troubleshoot_mcp_request.sh <opc-request-id> [--hours 2]
  OPC_REQUEST_ID=<opc-request-id> ./troubleshoot_mcp_request.sh [--hours 2]

Examples:
  ./troubleshoot_mcp_request.sh 'mcp-69_149_54_11/.../...'
  ./troubleshoot_mcp_request.sh 'mcp-69_149_54_11/.../...' --hours 6
  ./troubleshoot_mcp_request.sh --hours 6 'mcp-69_149_54_11/.../...'

The script reads .deep-sec-mcp.env, searches OCI Audit for the request, then
summarizes the MCP server app, MCP app roles, lab groups, and current grants.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: $1 is required but is not available in PATH.${NC}" >&2
    exit 1
  fi
}

oci_query() {
  PYTHONWARNINGS="${PYTHONWARNINGS:+${PYTHONWARNINGS},}ignore::FutureWarning:urllib3.poolmanager" \
    oci_with_profile "$@"
}

HOURS=2
OPC_REQUEST_ID="${OPC_REQUEST_ID:-}"
OPC_REQUEST_ID_FROM_ARG=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --hours)
      HOURS="${2:-}"
      shift 2
      ;;
    *)
      if [[ "$1" == -* ]]; then
        echo -e "${RED}ERROR: Unknown argument: $1${NC}" >&2
        usage
        exit 1
      fi
      if [ "$OPC_REQUEST_ID_FROM_ARG" = "1" ]; then
        echo -e "${RED}ERROR: Multiple opc-request-id values supplied.${NC}" >&2
        usage
        exit 1
      fi
      OPC_REQUEST_ID="$1"
      OPC_REQUEST_ID_FROM_ARG=1
      shift
      ;;
  esac
done

OPC_REQUEST_ID=$(printf '%s' "$OPC_REQUEST_ID" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
if [ -z "$OPC_REQUEST_ID" ]; then
  usage
  exit 0
fi

if ! [[ "$HOURS" =~ ^[0-9]+$ ]] || [ "$HOURS" -lt 1 ]; then
  echo -e "${RED}ERROR: --hours must be a positive integer.${NC}" >&2
  exit 1
fi

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo -e "${RED}ERROR: .deep-sec-mcp.env not found. Run ./00_configure_lab_env.sh first.${NC}" >&2
  exit 1
fi
source "${SCRIPT_DIR}/../lib_oci_profile.sh"

require_cmd oci
require_cmd python3

DOMAIN_ENDPOINT="${DOMAIN_ENDPOINT:-${OCI_DOMAIN_URL:-}}"
DOMAIN_ENDPOINT="${DOMAIN_ENDPOINT%/}"

if [ -z "${TENANCY_OCID:-}" ]; then
  echo -e "${RED}ERROR: TENANCY_OCID is not set in .deep-sec-mcp.env.${NC}" >&2
  exit 1
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/deepsec-mcp-troubleshoot.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

AUDIT_JSON="${WORK_DIR}/audit.json"
RECENT_AUDIT_JSON="${WORK_DIR}/recent-audit.json"
SUMMARY_ENV="${WORK_DIR}/summary.env"
APPS_JSON="${WORK_DIR}/apps.json"
ROLES_JSON="${WORK_DIR}/app-roles.json"
GROUPS_JSON="${WORK_DIR}/groups.json"
USERS_JSON="${WORK_DIR}/users.json"
GRANTS_JSON="${WORK_DIR}/grants.json"

TIME_START=$(date -u -d "${HOURS} hours ago" +%Y-%m-%dT%H:%M:%SZ)
TIME_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Troubleshoot DeepSec MCP Request                                      ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}OPC_REQUEST_ID       = ${OPC_REQUEST_ID}${NC}"
echo -e "${CYAN}TENANCY_OCID         = ${TENANCY_OCID}${NC}"
echo -e "${CYAN}MCP_SERVER_ID        = ${MCP_SERVER_ID:-}${NC}"
echo -e "${CYAN}MCP_SERVER_NAME      = ${MCP_SERVER_NAME:-}${NC}"
echo -e "${CYAN}DOMAIN_ENDPOINT      = ${DOMAIN_ENDPOINT:-}${NC}"
echo -e "${CYAN}Audit search window  = ${TIME_START} to ${TIME_END}${NC}"
echo

echo -e "${YELLOW}Searching OCI Audit for the request...${NC}"
if ! oci_query logging-search search-logs \
  --search-query "search \"${TENANCY_OCID}/_Audit\" | (data.request.id='${OPC_REQUEST_ID}') | sort by datetime desc" \
  --time-start "$TIME_START" \
  --time-end "$TIME_END" \
  --output json > "$AUDIT_JSON"; then
  echo -e "${RED}ERROR: Audit search failed.${NC}" >&2
  exit 1
fi

AUDIT_JSON="$AUDIT_JSON" SUMMARY_ENV="$SUMMARY_ENV" python3 - <<'PY'
import json
import os
import shlex

audit_path = os.environ["AUDIT_JSON"]
summary_path = os.environ["SUMMARY_ENV"]

with open(audit_path, encoding="utf-8") as f:
    raw = json.load(f)

results = (((raw.get("data") or {}).get("results")) or [])
if not results:
    print("FAIL: No Audit event found for this opc-request-id.")
    print("Try a larger window, for example: ./troubleshoot_mcp_request.sh '<id>' --hours 6")
    with open(summary_path, "w", encoding="utf-8") as out:
        out.write("AUDIT_FOUND=0\n")
    raise SystemExit(0)

data = (((results[0].get("data") or {}).get("logContent") or {}).get("data") or {})
identity = data.get("identity") or {}
request = data.get("request") or {}
response = data.get("response") or {}
details = data.get("additionalDetails") or {}

fields = {
    "AUDIT_FOUND": "1",
    "AUDIT_EVENT": data.get("eventName") or "",
    "AUDIT_MESSAGE": data.get("message") or "",
    "AUDIT_STATUS": str(response.get("status") or ""),
    "AUDIT_PRINCIPAL_NAME": identity.get("principalName") or "",
    "AUDIT_PRINCIPAL_ID": identity.get("principalId") or "",
    "AUDIT_CALLER_NAME": identity.get("callerName") or "",
    "AUDIT_CALLER_ID": identity.get("callerId") or "",
    "AUDIT_USER_AGENT": identity.get("userAgent") or "",
    "AUDIT_RESOURCE_ID": data.get("resourceId") or "",
    "AUDIT_METHOD": str(details.get("method") or ""),
    "AUDIT_REQUEST_PATH": request.get("path") or "",
}

print("Audit event")
for key in (
    "AUDIT_EVENT",
    "AUDIT_STATUS",
    "AUDIT_MESSAGE",
    "AUDIT_METHOD",
    "AUDIT_PRINCIPAL_NAME",
    "AUDIT_PRINCIPAL_ID",
    "AUDIT_CALLER_NAME",
    "AUDIT_CALLER_ID",
    "AUDIT_USER_AGENT",
    "AUDIT_RESOURCE_ID",
):
    print(f"  {key.replace('AUDIT_', '').lower():18} = {fields[key]}")

message = fields["AUDIT_MESSAGE"]
status = fields["AUDIT_STATUS"]
if status == "200" and "JSON-RPC reported an error" in message:
    print()
    print("Interpretation")
    print("  OCI accepted the InvokeMcpServer API request.")
    print("  The permission failure is coming from MCP/tool authorization after the request reached the MCP server.")
    print("  Check MCP app-role grants and then reconnect the client to get a fresh token.")

with open(summary_path, "w", encoding="utf-8") as out:
    for key, value in fields.items():
        out.write(f"{key}={shlex.quote(str(value))}\n")
PY

# shellcheck disable=SC1090
source "$SUMMARY_ENV"

if [ "${AUDIT_FOUND:-0}" != "1" ]; then
  echo
  echo -e "${YELLOW}Searching for recent InvokeMcpServer Audit events for this MCP server...${NC}"
  if oci_query logging-search search-logs \
    --search-query "search \"${TENANCY_OCID}/_Audit\" | (data.eventName='InvokeMcpServer' && data.resourceId='${MCP_SERVER_ID:-}') | sort by datetime desc" \
    --time-start "$TIME_START" \
    --time-end "$TIME_END" \
    --output json > "$RECENT_AUDIT_JSON"; then
    RECENT_AUDIT_JSON="$RECENT_AUDIT_JSON" python3 - <<'PY'
import json
import os

with open(os.environ["RECENT_AUDIT_JSON"], encoding="utf-8") as f:
    raw = json.load(f)

results = (((raw.get("data") or {}).get("results")) or [])
if not results:
    print("No recent InvokeMcpServer Audit events found for this MCP server in the same window.")
    print("Wait 1-2 minutes for Audit ingestion, then rerun with --hours 6.")
    raise SystemExit(0)

print("Recent InvokeMcpServer Audit events")
for item in results[:10]:
    data = (((item.get("data") or {}).get("logContent") or {}).get("data") or {})
    identity = data.get("identity") or {}
    request = data.get("request") or {}
    response = data.get("response") or {}
    details = data.get("additionalDetails") or {}
    print(f"  time      = {(((item.get('data') or {}).get('logContent') or {}).get('time') or '')}")
    print(f"  requestId = {request.get('id') or ''}")
    print(f"  status    = {response.get('status') or ''}")
    print(f"  method    = {details.get('method') or ''}")
    print(f"  principal = {identity.get('principalName') or ''}")
    print(f"  caller    = {identity.get('callerName') or ''}")
    print(f"  message   = {data.get('message') or ''}")
    print()
PY
  else
    echo -e "${RED}Fallback Audit search failed.${NC}" >&2
  fi
  exit 1
fi

if [ -z "$DOMAIN_ENDPOINT" ]; then
  echo
  echo -e "${YELLOW}Skipping Identity Domains checks because OCI_DOMAIN_URL is not set.${NC}"
  exit 0
fi

echo
echo -e "${YELLOW}Inspecting Identity Domains MCP app, roles, groups, and grants...${NC}"
oci_query identity-domains apps list \
  --endpoint "$DOMAIN_ENDPOINT" \
  --all \
  --attribute-sets all \
  --output json > "$APPS_JSON" || true

oci_query identity-domains app-roles list \
  --endpoint "$DOMAIN_ENDPOINT" \
  --all \
  --attribute-sets all \
  --output json > "$ROLES_JSON" || true

oci_query identity-domains groups list \
  --endpoint "$DOMAIN_ENDPOINT" \
  --all \
  --attribute-sets all \
  --output json > "$GROUPS_JSON" || true

oci_query identity-domains users list \
  --endpoint "$DOMAIN_ENDPOINT" \
  --all \
  --attribute-sets all \
  --output json > "$USERS_JSON" || true

oci_query identity-domains grants list \
  --endpoint "$DOMAIN_ENDPOINT" \
  --all \
  --output json > "$GRANTS_JSON" || true

APPS_JSON="$APPS_JSON" \
ROLES_JSON="$ROLES_JSON" \
GROUPS_JSON="$GROUPS_JSON" \
USERS_JSON="$USERS_JSON" \
GRANTS_JSON="$GRANTS_JSON" \
MCP_SERVER_ID="${MCP_SERVER_ID:-}" \
MCP_SERVER_NAME="${MCP_SERVER_NAME:-}" \
OCI_IAM_EMPLOYEE_GROUP_DISPLAY_NAME="${OCI_IAM_EMPLOYEE_GROUP_DISPLAY_NAME:-}" \
OCI_IAM_MANAGER_GROUP_DISPLAY_NAME="${OCI_IAM_MANAGER_GROUP_DISPLAY_NAME:-}" \
AUDIT_PRINCIPAL_ID="${AUDIT_PRINCIPAL_ID:-}" \
AUDIT_PRINCIPAL_NAME="${AUDIT_PRINCIPAL_NAME:-}" \
python3 - <<'PY'
import json
import os

def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}

def resources(raw):
    data = raw.get("data") or {}
    return data.get("Resources") or data.get("resources") or data.get("items") or []

apps = resources(load(os.environ["APPS_JSON"]))
roles = resources(load(os.environ["ROLES_JSON"]))
groups = resources(load(os.environ["GROUPS_JSON"]))
users = resources(load(os.environ["USERS_JSON"]))
grants = resources(load(os.environ["GRANTS_JSON"]))

mcp_server_id = os.environ.get("MCP_SERVER_ID", "")
mcp_server_name = os.environ.get("MCP_SERVER_NAME", "")
principal_ocid = os.environ.get("AUDIT_PRINCIPAL_ID", "")
principal_name = os.environ.get("AUDIT_PRINCIPAL_NAME", "")
employee_group_name = os.environ.get("OCI_IAM_EMPLOYEE_GROUP_DISPLAY_NAME", "")
manager_group_name = os.environ.get("OCI_IAM_MANAGER_GROUP_DISPLAY_NAME", "")

def app_display(app):
    return app.get("display-name") or app.get("displayName") or app.get("display") or ""

def group_display(group):
    return group.get("display-name") or group.get("displayName") or group.get("display") or ""

def role_display(role):
    return role.get("display-name") or role.get("displayName") or role.get("display") or ""

def user_display(user):
    return user.get("display-name") or user.get("displayName") or user.get("display") or user.get("user-name") or user.get("userName") or ""

def ocid_of(item):
    return item.get("ocid") or item.get("idcsCreatedBy", {}).get("ocid") or ""

def app_matches(app):
    audience = app.get("audience") or ""
    service_type = app.get("service-type-urn") or app.get("serviceTypeUrn") or ""
    return (
        (mcp_server_name and app_display(app) == mcp_server_name)
        or (mcp_server_id and audience == f"urn:opc:dbtools:mcpserver:{mcp_server_id}")
        or (mcp_server_id and app.get("service-instance-identifier") and app.get("service-instance-identifier") in mcp_server_id)
        or service_type == "DBTOOLS_MCP_SERVER"
    )

mcp_apps = [app for app in apps if app_matches(app)]
if mcp_server_id and len(mcp_apps) > 1:
    filtered = [
        app for app in mcp_apps
        if app.get("audience") == f"urn:opc:dbtools:mcpserver:{mcp_server_id}"
        or app_display(app) == mcp_server_name
        or (app.get("service-instance-identifier") and app.get("service-instance-identifier") in mcp_server_id)
    ]
    if filtered:
        mcp_apps = filtered

print()
print("MCP identity-domain app")
if not mcp_apps:
    print("  FAIL: Could not find the DBTOOLS_MCP_SERVER app in this identity domain.")
    mcp_app = None
else:
    mcp_app = mcp_apps[0]
    print(f"  app_id       = {mcp_app.get('id')}")
    print(f"  display_name = {app_display(mcp_app)}")
    print(f"  app_ocid     = {mcp_app.get('ocid')}")
    print(f"  service_type = {mcp_app.get('service-type-urn') or mcp_app.get('serviceTypeUrn')}")

mcp_app_id = mcp_app.get("id") if mcp_app else ""
role_by_id = {}
mcp_roles = []
for role in roles:
    app = role.get("app") or {}
    if app.get("value") == mcp_app_id or (mcp_app_id and mcp_app_id in str(role)):
        mcp_roles.append(role)
        role_by_id[role.get("id")] = role_display(role)

print()
print("MCP app roles")
if not mcp_roles:
    print("  FAIL: No app roles found for the MCP app.")
else:
    for role in mcp_roles:
        print(f"  {role_display(role):20} {role.get('id')}")

target_group_names = [name for name in (employee_group_name, manager_group_name) if name]
target_groups = []
for group in groups:
    if group_display(group) in target_group_names:
        target_groups.append(group)

print()
print("Lab groups")
if not target_group_names:
    print("  WARN: OCI_IAM_EMPLOYEE_GROUP_DISPLAY_NAME and OCI_IAM_MANAGER_GROUP_DISPLAY_NAME are not set.")
elif not target_groups:
    print(f"  FAIL: Could not find lab groups: {', '.join(target_group_names)}")
else:
    for group in target_groups:
        print(f"  {group_display(group):32} {group.get('id')}")

principal_user = None
for user in users:
    if user.get("ocid") == principal_ocid:
        principal_user = user
        break
if not principal_user and principal_name:
    for user in users:
        if principal_name.lower() in user_display(user).lower():
            principal_user = user
            break

print()
print("Audit principal user")
if principal_user:
    print(f"  scim_user_id = {principal_user.get('id')}")
    print(f"  display_name = {user_display(principal_user)}")
    print(f"  user_name    = {principal_user.get('user-name') or principal_user.get('userName')}")
    print(f"  ocid         = {principal_user.get('ocid')}")
else:
    print(f"  WARN: Could not map audit principal to an identity-domain user: {principal_name} / {principal_ocid}")

target_grantee_ids = {group.get("id") for group in target_groups if group.get("id")}
if principal_user and principal_user.get("id"):
    target_grantee_ids.add(principal_user.get("id"))
target_role_ids = {role.get("id") for role in mcp_roles if role.get("id")}

print()
print("Relevant MCP app-role grants")
found = False
principal_role_names = set()
unfulfilled_grants = []
for grant in grants:
    app = grant.get("app") or {}
    entitlement = grant.get("entitlement") or {}
    grantee = grant.get("grantee") or {}
    app_value = app.get("value")
    role_id = entitlement.get("attribute-value") or entitlement.get("attributeValue")
    grantee_id = grantee.get("value")
    fulfilled = grant.get('is-fulfilled') if 'is-fulfilled' in grant else grant.get('isFulfilled')
    if app_value == mcp_app_id and (role_id in target_role_ids or grantee_id in target_grantee_ids):
        found = True
        role_name = role_by_id.get(role_id, role_id)
        print(f"  grant_id  = {grant.get('id')}")
        print(f"    role    = {role_name} ({role_id})")
        print(f"    grantee = {grantee.get('display') or grantee_id} ({grantee.get('type')})")
        print(f"    mode    = {grant.get('grant-mechanism') or grant.get('grantMechanism')}")
        print(f"    fulfilled = {fulfilled}")
        if grantee_id == (principal_user or {}).get("id") and fulfilled is True:
            principal_role_names.add(str(role_name))
        if fulfilled is False:
            unfulfilled_grants.append((role_name, grantee.get('display') or grantee_id))

if not found:
    print("  FAIL: No MCP app-role grants found for the lab groups or audit principal.")

print()
print("MCP role assessment")
if {"MCP_User", "MCP_Operator", "MCP_Administrator"} & principal_role_names:
    print(f"  PASS: Audit principal has fulfilled MCP app role(s): {', '.join(sorted(principal_role_names))}")
    print("  If Cursor still fails, force a fresh OAuth token by logging out of the MCP server and reconnecting.")
    print("  If a fresh token still fails, run ./verify_oci_policies.sh and then check Database Tools/database authorization.")
elif found:
    print("  WARN: Relevant grants exist, but the audit principal does not show a fulfilled MCP_User, MCP_Operator, or MCP_Administrator grant.")
if unfulfilled_grants:
    print("  WARN: Some administrator-created grants are not fulfilled yet:")
    for role_name, grantee in unfulfilled_grants:
        print(f"    {role_name} -> {grantee}")

print()
print("Next checks")
if not found:
    print("  Add MCP_User to the lab employee group or directly to the audit principal user.")
elif {"MCP_User", "MCP_Operator", "MCP_Administrator"} & principal_role_names:
    print("  Do not add more MCP app-role grants for this principal; run ./verify_oci_policies.sh next.")
else:
    print("  If grants were just added, sign out and reconnect the MCP client to get a fresh token.")
    print("  If the error persists and grants show fulfilled=false, wait for Identity Domains propagation or verify in the Console Roles tab.")
print("  If Audit shows HTTP 200 with a JSON-RPC error, the request reached the MCP server and the remaining issue is app-role/tool authorization.")
PY
