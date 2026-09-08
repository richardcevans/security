#!/bin/bash
# Register a Cline OAuth public client for this lab's Database Tools MCP server.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"
CLIENT_NAME=""
REQUESTED_SCOPE="${MCP_CLIENT_SCOPE:-}"
ACCEPT=0
REPAIR_EXISTING=0
REDIRECT_URI="${MCP_CLINE_REDIRECT_URI:-http://localhost:8080/oauth/callback}"
CLIENT_LABEL="${MCP_CLIENT_LABEL:-Cline}"

usage() {
  cat <<'EOF'
Usage: ./02_register_cline_mcp_client.sh [options]

Registers an OCI IAM Identity Domains public OAuth client for Cline through
mcp-remote. It does not create or modify the MCP server, Database Tools
connection, database, or data grants.

Options:
  --name <display-name>  Client display name. Default: deep-sec-mcp-cline.
  --scope <fqs>          MCP scope. Use only when the resource app exposes
                         more than one scope and the script asks you to choose.
  --redirect-uri <uri>   OAuth redirect URI. Default: http://localhost:8080/oauth/callback.
  --accept               Skip the interactive CREATE acknowledgement after the
                         preview has been displayed.
  --repair-existing      Repair an existing same-named MCP public client by
                         removing ADB-only OAuth settings. The script displays
                         the change and requires UPDATE unless --accept is set.

The default registered redirect URI for the Cline/mcp-remote path is:
  http://localhost:8080/oauth/callback
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --name) CLIENT_NAME="${2:-}"; shift 2 ;;
    --scope) REQUESTED_SCOPE="${2:-}"; shift 2 ;;
    --redirect-uri) REDIRECT_URI="${2:-}"; shift 2 ;;
    --accept) ACCEPT=1; shift ;;
    --repair-existing) REPAIR_EXISTING=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo -e "${RED}ERROR: Unknown argument: $1${NC}" >&2; usage >&2; exit 2 ;;
  esac
done

if [ ! -f "$ENV_FILE" ]; then
  echo -e "${RED}ERROR: .deep-sec-mcp.env not found. Run ./00_configure_lab_env.sh first.${NC}" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib_oci_profile.sh"

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

append_or_replace_env() {
  local key="$1" value="$2"
  if grep -q "^export ${key}=" "$ENV_FILE"; then
    perl -pi -e "s|^export ${key}=.*|export ${key}=\"${value}\"|" "$ENV_FILE"
  else
    printf 'export %s="%s"\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

app_field() {
  local app_id="$1" field="$2" response
  response=$(oci_query identity-domains app get --endpoint "$OCI_DOMAIN_URL" \
    --app-id "$app_id" --attribute-sets all --output json)
  APP_RESPONSE="$response" APP_FIELD="$field" python3 - <<'PY'
import json
import os

try:
    data = json.loads(os.environ["APP_RESPONSE"]).get("data") or {}
except (json.JSONDecodeError, KeyError):
    raise SystemExit(0)

aliases = {
    "client_id": ("client-id", "clientId", "client_id", "oauth-client-id", "o-auth-client-id", "id"),
}
for key in aliases.get(os.environ["APP_FIELD"], (os.environ["APP_FIELD"],)):
    value = data.get(key)
    if value:
        print(value)
        break
PY
}

require_cmd oci
require_cmd perl
require_cmd python3
require_var OCI_DOMAIN_URL
require_var MCP_SERVER_ID

CLIENT_NAME="${CLIENT_NAME:-${MCP_CLINE_CLIENT_NAME:-deep-sec-mcp-cline}}"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/deepsec-mcp-cline.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT
APPS_JSON="${WORK_DIR}/apps.json"
PLAN_JSON="${WORK_DIR}/plan.json"

oci_query identity-domains apps list \
  --endpoint "$OCI_DOMAIN_URL" \
  --all \
  --attribute-sets all \
  --output json > "$APPS_JSON"

APPS_JSON="$APPS_JSON" \
MCP_SERVER_ID="$MCP_SERVER_ID" \
MCP_SERVER_NAME="${MCP_SERVER_NAME:-}" \
CLIENT_NAME="$CLIENT_NAME" \
REQUESTED_SCOPE="$REQUESTED_SCOPE" \
REDIRECT_URI="$REDIRECT_URI" \
PLAN_JSON="$PLAN_JSON" \
python3 - <<'PY' > /dev/null
import json
import os
import sys

def resources(raw):
    data = raw.get("data") or {}
    return data.get("Resources") or data.get("resources") or data.get("items") or []

def value(item, *keys):
    for key in keys:
        if item.get(key) not in (None, ""):
            return item[key]
    return ""

apps = resources(json.load(open(os.environ["APPS_JSON"], encoding="utf-8")))
server_id = os.environ["MCP_SERVER_ID"]
server_name = os.environ["MCP_SERVER_NAME"]

def is_mcp_resource_app(app):
    audience = value(app, "audience")
    service_type = value(app, "service-type-urn", "serviceTypeUrn")
    service_instance = value(app, "service-instance-identifier", "serviceInstanceIdentifier")
    display = value(app, "display-name", "displayName")
    return (
        audience == f"urn:opc:dbtools:mcpserver:{server_id}"
        or (service_instance and service_instance in server_id)
        or (service_type == "DBTOOLS_MCP_SERVER" and server_name and display == server_name)
    )

resource_apps = [app for app in apps if is_mcp_resource_app(app)]
if len(resource_apps) != 1:
    print("ERROR: Could not uniquely identify the Identity Domain resource app for this MCP server.", file=sys.stderr)
    print("Run ./grant_mcp_app_roles.sh --dry-run to inspect the MCP application mapping.", file=sys.stderr)
    raise SystemExit(1)

resource_app = resource_apps[0]
available_scopes = [
    scope.get("fqs") for scope in resource_app.get("scopes") or []
    if scope.get("fqs")
]
requested = os.environ["REQUESTED_SCOPE"]
if requested:
    if requested not in available_scopes:
        print("ERROR: --scope is not one of the scopes published by this MCP resource app.", file=sys.stderr)
        print("Available scopes:\n  " + "\n  ".join(available_scopes), file=sys.stderr)
        raise SystemExit(2)
    selected_scope = requested
elif len(available_scopes) == 1:
    selected_scope = available_scopes[0]
else:
    print("ERROR: The MCP resource app has zero or multiple scopes; choose one explicitly with --scope.", file=sys.stderr)
    print("Available scopes:\n  " + "\n  ".join(available_scopes or ["<none>"]), file=sys.stderr)
    raise SystemExit(3)

client_name = os.environ["CLIENT_NAME"]
client_apps = [app for app in apps if value(app, "display-name", "displayName") == client_name]
if len(client_apps) > 1:
    print(f"ERROR: More than one Identity Domain app is named {client_name!r}.", file=sys.stderr)
    raise SystemExit(4)

existing = client_apps[0] if client_apps else None
if existing:
    grants = existing.get("allowed-grants") or existing.get("allowedGrants") or []
    allowed = existing.get("allowed-scopes") or existing.get("allowedScopes") or []
    redirect_uris = existing.get("redirect-uris") or existing.get("redirectUris") or []
    allowed_scopes = {item.get("fqs") for item in allowed if isinstance(item, dict)}
    redirects = {
        item.get("value") if isinstance(item, dict) else item
        for item in redirect_uris
    }
    is_resource = bool(value(existing, "is-o-auth-resource", "isOAuthResource"))
    if (value(existing, "client-type", "clientType").lower() != "public"
            or "authorization_code" not in grants
            or selected_scope not in allowed_scopes
            or os.environ["REDIRECT_URI"] not in redirects):
        print("ERROR: A same-named app exists but is not the required Cline public client.", file=sys.stderr)
        raise SystemExit(5)

plan = {
    "resource_app_id": resource_app.get("id", ""),
    "resource_app_display_name": value(resource_app, "display-name", "displayName"),
    "scope": selected_scope,
    "client_name": client_name,
    "redirect_uri": os.environ["REDIRECT_URI"],
    "existing_app_id": existing.get("id", "") if existing else "",
    "requires_public_client_repair": bool(existing and is_resource),
    "is_oauth_resource": bool(existing and is_resource),
    "has_allowed_operations": bool(existing and (
        existing.get("allowed-operations") or existing.get("allowedOperations")
    )),
}
json.dump(plan, open(os.environ["PLAN_JSON"], "w", encoding="utf-8"))
print(json.dumps(plan))
PY

resource_app_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["resource_app_id"])' "$PLAN_JSON")
selected_scope=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["scope"])' "$PLAN_JSON")
existing_app_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["existing_app_id"])' "$PLAN_JSON")
requires_public_client_repair=$(python3 -c 'import json,sys; print("1" if json.load(open(sys.argv[1]))["requires_public_client_repair"] else "0")' "$PLAN_JSON")
is_oauth_resource=$(python3 -c 'import json,sys; print("1" if json.load(open(sys.argv[1]))["is_oauth_resource"] else "0")' "$PLAN_JSON")
has_allowed_operations=$(python3 -c 'import json,sys; print("1" if json.load(open(sys.argv[1]))["has_allowed_operations"] else "0")' "$PLAN_JSON")

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Register ${CLIENT_LABEL} Public MCP Client${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}MCP resource app = ${resource_app_id}${NC}"
echo -e "${CYAN}OAuth scope      = ${selected_scope}${NC}"
echo -e "${CYAN}Client name      = ${CLIENT_NAME}${NC}"
echo -e "${CYAN}Client type      = public${NC}"
echo -e "${CYAN}Grant types      = authorization_code, refresh_token${NC}"
echo -e "${CYAN}Redirect URI     = ${REDIRECT_URI}${NC}"
echo -e "${CYAN}Allow URL schemes = true (required by this domain for localhost HTTP)${NC}"

if [ -n "$existing_app_id" ]; then
  client_app_id="$existing_app_id"
  echo -e "${YELLOW}Reusing compatible Cline client app: ${client_app_id}${NC}"
  if [ "$requires_public_client_repair" = 1 ] || [ "$has_allowed_operations" = 1 ]; then
    if [ "$REPAIR_EXISTING" != 1 ]; then
      echo -e "${YELLOW}The existing client has settings that do not match a Database Tools MCP public client.${NC}"
      echo "Repair it with: ./02_register_cline_mcp_client.sh --repair-existing"
      exit 1
    fi
    echo
    echo 'Planned update:'
    echo "  App: ${CLIENT_NAME} (${client_app_id})"
    if [ "$has_allowed_operations" = 1 ]; then
      echo '  Remove allowed OAuth operations (MCP clients do not use them)'
    fi
    if [ "$is_oauth_resource" = 1 ]; then
      echo '  Set OAuth resource app: false'
    fi
    if [ "$ACCEPT" != 1 ]; then
      read -r -p 'Type UPDATE to repair this public client: ' confirmation
      if [ "$confirmation" != 'UPDATE' ]; then
        echo 'No client application was changed.'
        exit 0
      fi
    fi
    patch_json=$(HAS_ALLOWED_OPERATIONS="$has_allowed_operations" IS_OAUTH_RESOURCE="$is_oauth_resource" python3 - <<'PY'
import json
import os

operations = []
if os.environ["HAS_ALLOWED_OPERATIONS"] == "1":
    operations.append({"op": "remove", "path": "allowedOperations"})
if os.environ["IS_OAUTH_RESOURCE"] == "1":
    operations.append({"op": "replace", "path": "isOAuthResource", "value": False})
print(json.dumps(operations))
PY
)
    echo -e "${CYAN}Repairing MCP public client settings: ${CLIENT_NAME}${NC}"
    oci_query identity-domains app patch \
      --endpoint "$OCI_DOMAIN_URL" \
      --app-id "$client_app_id" \
      --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
      --operations "$patch_json" \
      --output json >/dev/null
  fi
else
  echo
  if [ "$ACCEPT" != 1 ]; then
    read -r -p 'Type CREATE to register this public client: ' confirmation
    if [ "$confirmation" != 'CREATE' ]; then
      echo 'No client application was created.'
      exit 0
    fi
  fi

  redirect_json=$(python3 -c 'import json,sys; print(json.dumps([sys.argv[1]]))' "$REDIRECT_URI")
  echo -e "${CYAN}Creating public client app: ${CLIENT_NAME}${NC}"
  client_app_id=$(oci_query identity-domains app create \
    --endpoint "$OCI_DOMAIN_URL" \
    --schemas '["urn:ietf:params:scim:schemas:oracle:idcs:App"]' \
    --based-on-template '{"value":"CustomBrowserMobileTemplateId","wellKnownId":"CustomBrowserMobileTemplateId"}' \
    --display-name "$CLIENT_NAME" \
    --description "${CLIENT_LABEL} public OAuth client for the DeepSec MCP lab" \
    --active true \
    --is-o-auth-client true \
    --is-o-auth-resource false \
    --client-type public \
    --allowed-grants '["authorization_code","refresh_token"]' \
    --allowed-scopes "[{\"fqs\":\"${selected_scope}\"}]" \
    --redirect-uris "$redirect_json" \
    --all-url-schemes-allowed true \
    --attribute-sets all \
    --query 'data.id' \
    --raw-output)
fi

client_id=$(app_field "$client_app_id" client_id)
if [ -z "$client_id" ]; then
  echo -e "${RED}ERROR: Could not determine OAuth client ID for app ${client_app_id}.${NC}" >&2
  exit 1
fi

append_or_replace_env MCP_CLINE_CLIENT_NAME "$CLIENT_NAME"
append_or_replace_env MCP_CLINE_CLIENT_APP_ID "$client_app_id"
append_or_replace_env MCP_CLINE_CLIENT_ID "$client_id"
append_or_replace_env MCP_CLINE_CLIENT_SCOPE "$selected_scope"
append_or_replace_env MCP_CLINE_REDIRECT_URI "$REDIRECT_URI"

echo
echo -e "${GREEN}${CLIENT_LABEL} public MCP client is ready.${NC}"
echo "  App ID    = ${client_app_id}"
echo "  Client ID = ${client_id}"
echo "  State     = ${ENV_FILE}"
echo 'Next: run ./create_cline_mcp_config.sh to generate the mcp-remote configuration.'
