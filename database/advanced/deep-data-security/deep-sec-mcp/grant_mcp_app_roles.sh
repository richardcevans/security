#!/bin/bash
# Grant Database Tools MCP application roles to a lab group or user.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"

TARGET_GROUP=""
TARGET_USER=""
ROLE_NAMES="MCP_User,MCP_Operator"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  ./grant_mcp_app_roles.sh [options]

Options:
  --group <display-name>    Identity-domain group display name.
                            Default: OCI_IAM_EMPLOYEE_GROUP_DISPLAY_NAME from .deep-sec-mcp.env.
  --user <user-name-or-display-name>
                            Also grant roles directly to this identity-domain user.
  --roles <csv>             App roles to grant. Default: MCP_User,MCP_Operator
  --dry-run                 Discover and print planned grants without creating them.

Examples:
  ./grant_mcp_app_roles.sh
  ./grant_mcp_app_roles.sh --user marvin
  ./grant_mcp_app_roles.sh --group deepsec-employees-022b5f --roles MCP_User

This script avoids fragile OCI CLI --query filters and parses raw Identity
Domains JSON with Python because SCIM responses use mixed field naming.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --group)
      TARGET_GROUP="${2:-}"
      shift 2
      ;;
    --user)
      TARGET_USER="${2:-}"
      shift 2
      ;;
    --roles)
      ROLE_NAMES="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo -e "${RED}ERROR: Unknown argument: $1${NC}" >&2
      usage
      exit 1
      ;;
  esac
done

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

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo -e "${RED}ERROR: .deep-sec-mcp.env not found. Run ./00_configure_lab_env.sh first.${NC}" >&2
  exit 1
fi
source "${SCRIPT_DIR}/lib_oci_profile.sh"

require_cmd oci
require_cmd python3

DOMAIN_ENDPOINT="${DOMAIN_ENDPOINT:-${OCI_DOMAIN_URL:-}}"
DOMAIN_ENDPOINT="${DOMAIN_ENDPOINT%/}"
TARGET_GROUP="${TARGET_GROUP:-${OCI_IAM_EMPLOYEE_GROUP_DISPLAY_NAME:-}}"

if [ -z "$DOMAIN_ENDPOINT" ]; then
  echo -e "${RED}ERROR: OCI_DOMAIN_URL is not set in .deep-sec-mcp.env.${NC}" >&2
  exit 1
fi
if [ -z "${MCP_SERVER_ID:-}" ] && [ -z "${MCP_SERVER_NAME:-}" ]; then
  echo -e "${RED}ERROR: MCP_SERVER_ID or MCP_SERVER_NAME is required in .deep-sec-mcp.env.${NC}" >&2
  exit 1
fi
if [ -z "$TARGET_GROUP" ] && [ -z "$TARGET_USER" ]; then
  echo -e "${RED}ERROR: Provide --group, --user, or set OCI_IAM_EMPLOYEE_GROUP_DISPLAY_NAME.${NC}" >&2
  exit 1
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/deepsec-mcp-grants.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

APPS_JSON="${WORK_DIR}/apps.json"
ROLES_JSON="${WORK_DIR}/app-roles.json"
GROUPS_JSON="${WORK_DIR}/groups.json"
USERS_JSON="${WORK_DIR}/users.json"
GRANTS_JSON="${WORK_DIR}/grants.json"
PLAN_JSON="${WORK_DIR}/plan.json"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Grant DeepSec MCP Application Roles                                   ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}DOMAIN_ENDPOINT = ${DOMAIN_ENDPOINT}${NC}"
echo -e "${CYAN}MCP_SERVER_ID   = ${MCP_SERVER_ID:-}${NC}"
echo -e "${CYAN}MCP_SERVER_NAME = ${MCP_SERVER_NAME:-}${NC}"
echo -e "${CYAN}TARGET_GROUP    = ${TARGET_GROUP:-}${NC}"
echo -e "${CYAN}TARGET_USER     = ${TARGET_USER:-}${NC}"
echo -e "${CYAN}ROLE_NAMES      = ${ROLE_NAMES}${NC}"
echo

echo -e "${YELLOW}Loading Identity Domains data...${NC}"
oci_query identity-domains apps list \
  --endpoint "$DOMAIN_ENDPOINT" \
  --all \
  --attribute-sets all \
  --output json > "$APPS_JSON"

oci_query identity-domains app-roles list \
  --endpoint "$DOMAIN_ENDPOINT" \
  --all \
  --attribute-sets all \
  --output json > "$ROLES_JSON"

oci_query identity-domains groups list \
  --endpoint "$DOMAIN_ENDPOINT" \
  --all \
  --attribute-sets all \
  --output json > "$GROUPS_JSON"

oci_query identity-domains users list \
  --endpoint "$DOMAIN_ENDPOINT" \
  --all \
  --attribute-sets all \
  --output json > "$USERS_JSON"

oci_query identity-domains grants list \
  --endpoint "$DOMAIN_ENDPOINT" \
  --all \
  --output json > "$GRANTS_JSON" || printf '{"data":{"Resources":[]}}\n' > "$GRANTS_JSON"

APPS_JSON="$APPS_JSON" \
ROLES_JSON="$ROLES_JSON" \
GROUPS_JSON="$GROUPS_JSON" \
USERS_JSON="$USERS_JSON" \
GRANTS_JSON="$GRANTS_JSON" \
PLAN_JSON="$PLAN_JSON" \
MCP_SERVER_ID="${MCP_SERVER_ID:-}" \
MCP_SERVER_NAME="${MCP_SERVER_NAME:-}" \
TARGET_GROUP="$TARGET_GROUP" \
TARGET_USER="$TARGET_USER" \
ROLE_NAMES="$ROLE_NAMES" \
python3 - <<'PY'
import json
import os
import sys

def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)

def resources(raw):
    data = raw.get("data") or {}
    return data.get("Resources") or data.get("resources") or data.get("items") or []

def first_value(obj, *keys):
    for key in keys:
        if isinstance(obj, dict) and obj.get(key) not in (None, ""):
            return obj.get(key)
    return ""

apps = resources(load(os.environ["APPS_JSON"]))
roles = resources(load(os.environ["ROLES_JSON"]))
groups = resources(load(os.environ["GROUPS_JSON"]))
users = resources(load(os.environ["USERS_JSON"]))
grants = resources(load(os.environ["GRANTS_JSON"]))

mcp_server_id = os.environ.get("MCP_SERVER_ID", "")
mcp_server_name = os.environ.get("MCP_SERVER_NAME", "")
target_group_name = os.environ.get("TARGET_GROUP", "")
target_user_name = os.environ.get("TARGET_USER", "")
role_names = [name.strip() for name in os.environ.get("ROLE_NAMES", "").split(",") if name.strip()]

def app_display(app):
    return first_value(app, "display-name", "displayName", "display")

def group_display(group):
    return first_value(group, "display-name", "displayName", "display")

def user_display(user):
    return first_value(user, "display-name", "displayName", "display", "name")

def user_name(user):
    return first_value(user, "user-name", "userName")

def role_display(role):
    return first_value(role, "display-name", "displayName", "display")

def app_matches(app):
    audience = first_value(app, "audience")
    service_type = first_value(app, "service-type-urn", "serviceTypeUrn")
    service_instance = first_value(app, "service-instance-identifier", "serviceInstanceIdentifier")
    return (
        (mcp_server_name and app_display(app) == mcp_server_name)
        or (mcp_server_id and audience == f"urn:opc:dbtools:mcpserver:{mcp_server_id}")
        or (mcp_server_id and service_instance and service_instance in mcp_server_id)
        or (service_type == "DBTOOLS_MCP_SERVER" and (not mcp_server_name or app_display(app) == mcp_server_name))
    )

mcp_apps = [app for app in apps if app_matches(app)]
if not mcp_apps:
    print("ERROR: Could not find DBTOOLS_MCP_SERVER app for the MCP server.", file=sys.stderr)
    raise SystemExit(2)
if len(mcp_apps) > 1:
    exact = [
        app for app in mcp_apps
        if app_display(app) == mcp_server_name
        or first_value(app, "audience") == f"urn:opc:dbtools:mcpserver:{mcp_server_id}"
    ]
    if exact:
        mcp_apps = exact

mcp_app = mcp_apps[0]
mcp_app_id = mcp_app.get("id")
print("MCP app")
print(f"  id           = {mcp_app_id}")
print(f"  display_name = {app_display(mcp_app)}")
print(f"  ocid         = {mcp_app.get('ocid')}")

selected_roles = []
for role in roles:
    app = role.get("app") or {}
    if app.get("value") == mcp_app_id and role_display(role) in role_names:
        selected_roles.append(role)

missing_roles = sorted(set(role_names) - {role_display(role) for role in selected_roles})
if missing_roles:
    print(f"ERROR: Could not find MCP app role(s): {', '.join(missing_roles)}", file=sys.stderr)
    raise SystemExit(3)

print()
print("Selected roles")
for role in selected_roles:
    print(f"  {role_display(role):18} {role.get('id')}")

targets = []
if target_group_name:
    matches = [group for group in groups if group_display(group) == target_group_name]
    if not matches:
        print(f"ERROR: Could not find group display name: {target_group_name}", file=sys.stderr)
        raise SystemExit(4)
    group = matches[0]
    targets.append({
        "type": "Group",
        "id": group.get("id"),
        "display": group_display(group),
    })

if target_user_name:
    needle = target_user_name.lower()
    matches = [
        user for user in users
        if user_name(user).lower() == needle
        or user_display(user).lower() == needle
        or needle in user_display(user).lower()
    ]
    if not matches:
        print(f"ERROR: Could not find user: {target_user_name}", file=sys.stderr)
        raise SystemExit(5)
    user = matches[0]
    targets.append({
        "type": "User",
        "id": user.get("id"),
        "display": user_display(user) or user_name(user),
    })

print()
print("Targets")
for target in targets:
    print(f"  {target['type']:5} {target['display']} ({target['id']})")

def grant_attr(grant, outer, inner=None):
    value = grant.get(outer)
    if inner and isinstance(value, dict):
        return first_value(value, inner, inner.replace("-", ""))
    return value

existing = set()
for grant in grants:
    app = grant.get("app") or {}
    entitlement = grant.get("entitlement") or {}
    grantee = grant.get("grantee") or {}
    app_value = app.get("value")
    role_id = first_value(entitlement, "attribute-value", "attributeValue")
    grantee_id = grantee.get("value")
    if app_value and role_id and grantee_id:
        existing.add((app_value, role_id, grantee_id))

planned = []
already = []
for target in targets:
    for role in selected_roles:
        item = {
            "app_id": mcp_app_id,
            "app_display": app_display(mcp_app),
            "role_id": role.get("id"),
            "role_name": role_display(role),
            "grantee_id": target["id"],
            "grantee_type": target["type"],
            "grantee_display": target["display"],
        }
        if (mcp_app_id, role.get("id"), target["id"]) in existing:
            already.append(item)
        else:
            planned.append(item)

print()
if already:
    print("Already granted")
    for item in already:
        print(f"  {item['role_name']} -> {item['grantee_type']} {item['grantee_display']}")

if planned:
    print("Planned grants")
    for item in planned:
        print(f"  {item['role_name']} -> {item['grantee_type']} {item['grantee_display']}")
else:
    print("No new grants required.")

with open(os.environ["PLAN_JSON"], "w", encoding="utf-8") as f:
    json.dump({"planned": planned, "already": already}, f)
PY

if [ "$DRY_RUN" = "1" ]; then
  echo
  echo -e "${YELLOW}Dry run only. No grants created.${NC}"
  exit 0
fi

planned_count=$(python3 - "$PLAN_JSON" <<'PY'
import json, sys
print(len(json.load(open(sys.argv[1])).get("planned", [])))
PY
)

if [ "$planned_count" = "0" ]; then
  echo
  echo -e "${GREEN}MCP app-role grants are already present.${NC}"
  exit 0
fi

echo
echo -e "${YELLOW}Creating missing grants...${NC}"
python3 - "$PLAN_JSON" <<'PY' | while IFS=$'\t' read -r app_id role_id grantee_id grantee_type role_name grantee_display; do
import json, sys
plan = json.load(open(sys.argv[1]))
for item in plan.get("planned", []):
    print("\t".join([
        item["app_id"],
        item["role_id"],
        item["grantee_id"],
        item["grantee_type"],
        item["role_name"],
        item["grantee_display"],
    ]))
PY
  echo -e "${CYAN}Granting ${role_name} to ${grantee_type} ${grantee_display}${NC}"
  oci_query identity-domains grant create \
    --endpoint "$DOMAIN_ENDPOINT" \
    --schemas '["urn:ietf:params:scim:schemas:oracle:idcs:Grant"]' \
    --grant-mechanism "ADMINISTRATOR_TO_${grantee_type^^}" \
    --app "{\"value\":\"${app_id}\"}" \
    --entitlement "{\"attributeName\":\"appRoles\",\"attributeValue\":\"${role_id}\"}" \
    --grantee "{\"value\":\"${grantee_id}\",\"type\":\"${grantee_type}\"}" \
    --query 'data.{id:id,role:entitlement."attribute-value",grantee:grantee.value,fulfilled:"is-fulfilled"}' \
    --output json
done

echo
echo -e "${GREEN}MCP app-role grant processing complete.${NC}"
echo -e "${YELLOW}Next: sign out and reconnect the MCP client so the user receives a fresh token.${NC}"
