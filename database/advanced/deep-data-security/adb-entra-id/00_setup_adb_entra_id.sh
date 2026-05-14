#!/bin/bash
# Create or reuse the ADB-S instance, wallet, and Microsoft Entra ID apps.
# Intended to run from OCI Cloud Shell after OCI CLI and Azure CLI are configured.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.adb-entra-id.env"

export DB_NAME="${DB_NAME:-deepsec1}"
export DB_DISPLAY_NAME="${DB_DISPLAY_NAME:-${DB_NAME}}"
export ADMIN_PWD="${ADMIN_PWD:-Oracle123+Oracle123+}"
export WALLET_PWD="${WALLET_PWD:-Oracle123+}"
export WALLET_DIR="${WALLET_DIR:-$HOME/adb_wallet/${DB_NAME}-entra}"
export ADB_SERVICE="${ADB_SERVICE:-${DB_NAME}_low}"
export ENTRA_DB_APP_NAME="${ENTRA_DB_APP_NAME:-Oracle Database 26ai ADB - ${DB_NAME}}"
export ENTRA_CLIENT_APP_NAME="${ENTRA_CLIENT_APP_NAME:-Oracle Client Interactive ADB - ${DB_NAME}}"
export ENTRA_SCOPE_VALUE="${ENTRA_SCOPE_VALUE:-session:scope:connect}"
export CREATE_APP_ROLE_ASSIGNMENTS="${CREATE_APP_ROLE_ASSIGNMENTS:-1}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 0: Create ADB-S, Wallet, and Microsoft Entra ID Objects          ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

for cmd in oci az python3 unzip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: ${cmd} is not available on PATH.${NC}"
    exit 1
  fi
done

if ! oci iam region list >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI cannot call OCI. In Cloud Shell, refresh the session or check your tenancy.${NC}"
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Azure CLI is not logged in.${NC}"
  echo -e "${YELLOW}Run: az login${NC}"
  exit 1
fi

if [ -z "${ROOT_COMP_ID:-}" ]; then
  echo -e "${RED}ERROR: ROOT_COMP_ID is not set.${NC}"
  echo "Example:"
  echo "  export ROOT_COMP_ID=ocid1.compartment.oc1..aaaa..."
  exit 1
fi

json_get() {
  local expr="$1"
  python3 -c "import json,sys; data=json.load(sys.stdin); print(${expr})"
}

json_get_or_empty() {
  local expr="$1"
  python3 -c "import json,sys; data=json.load(sys.stdin); v=${expr}; print('' if v is None else v)"
}

new_uuid() {
  python3 -c 'import uuid; print(uuid.uuid4())'
}

graph_patch() {
  local uri="$1"
  local body_file="$2"
  az rest --method PATCH \
    --uri "$uri" \
    --headers "Content-Type=application/json" \
    --body @"$body_file" \
    >/dev/null
}

find_app_json() {
  local display_name="$1"
  az ad app list --display-name "$display_name" -o json | APP_NAME="$display_name" python3 -c '
import json, os, sys
name = os.environ["APP_NAME"]
apps = [a for a in json.load(sys.stdin) if a.get("displayName") == name]
print(json.dumps(apps[0] if apps else {}))
'
}

ensure_service_principal() {
  local app_id="$1"
  if az ad sp show --id "$app_id" >/dev/null 2>&1; then
    return
  fi
  az ad sp create --id "$app_id" >/dev/null
}

discover_domain_name() {
  local discovered
  discovered=$(az rest --method GET \
    --uri "https://graph.microsoft.com/v1.0/domains?\$filter=isDefault eq true" \
    --query "value[0].id" \
    --output tsv 2>/dev/null || true)
  if [ -n "$discovered" ]; then
    printf '%s' "$discovered"
    return
  fi

  discovered=$(az ad signed-in-user show \
    --query userPrincipalName \
    --output tsv 2>/dev/null | awk -F@ 'NF == 2 { print $2; exit }' || true)
  if [ -n "$discovered" ]; then
    printf '%s' "$discovered"
  fi
}

domain_name="${DOMAIN_NAME:-}"
if [ -z "$domain_name" ]; then
  domain_name=$(discover_domain_name)
fi
if [ -z "$domain_name" ]; then
  echo -e "${RED}ERROR: Could not discover default Entra domain.${NC}"
  echo "Set it explicitly, for example:"
  echo "  export DOMAIN_NAME=example.onmicrosoft.com"
  exit 1
fi
export DOMAIN_NAME="$domain_name"

tenant_id="${TENANT_ID:-$(az account show --query tenantId --output tsv)}"
export TENANT_ID="$tenant_id"
app_id_uri="${APP_ID_URI:-https://${DOMAIN_NAME}/${DB_NAME}}"
export APP_ID_URI="$app_id_uri"
marvin_upn="${MARVIN_UPN:-$(az ad signed-in-user show --query userPrincipalName --output tsv 2>/dev/null || true)}"
if [ -z "$marvin_upn" ]; then
  marvin_upn="marvin@${DOMAIN_NAME}"
fi
export MARVIN_UPN="$marvin_upn"
export EMMA_UPN="${EMMA_UPN:-emma@${DOMAIN_NAME}}"

echo -e "${PURPLE}Configuration:${NC}"
echo -e "${CYAN}  ROOT_COMP_ID          = ${ROOT_COMP_ID}${NC}"
echo -e "${CYAN}  DB_NAME               = ${DB_NAME}${NC}"
echo -e "${CYAN}  ADB_SERVICE           = ${ADB_SERVICE}${NC}"
echo -e "${CYAN}  WALLET_DIR            = ${WALLET_DIR}${NC}"
echo -e "${CYAN}  TENANT_ID             = ${TENANT_ID}${NC}"
echo -e "${CYAN}  DOMAIN_NAME           = ${DOMAIN_NAME}${NC}"
echo -e "${CYAN}  APP_ID_URI            = ${APP_ID_URI}${NC}"
echo -e "${CYAN}  ENTRA_DB_APP_NAME     = ${ENTRA_DB_APP_NAME}${NC}"
echo -e "${CYAN}  ENTRA_CLIENT_APP_NAME = ${ENTRA_CLIENT_APP_NAME}${NC}"
echo -e "${CYAN}  MARVIN_UPN            = ${MARVIN_UPN}${NC}"
echo -e "${CYAN}  EMMA_UPN              = ${EMMA_UPN}${NC}"
echo

echo -e "${YELLOW}Step 1: Creating or reusing Autonomous Database...${NC}"
ADB_OCID=$(oci db autonomous-database list \
  --compartment-id "$ROOT_COMP_ID" \
  --all \
  --raw-output \
  --query "data[?\"db-name\"=='${DB_NAME}'].id | [0]")

if [ -z "$ADB_OCID" ] || [ "$ADB_OCID" = "null" ]; then
  oci db autonomous-database create \
    --compartment-id "$ROOT_COMP_ID" \
    --db-name "$DB_NAME" \
    --display-name "$DB_DISPLAY_NAME" \
    --is-free-tier true \
    --admin-password "$ADMIN_PWD" \
    --cpu-core-count 1 \
    --data-storage-size-in-tbs 1 \
    --wait-for-state AVAILABLE \
    >/dev/null

  ADB_OCID=$(oci db autonomous-database list \
    --compartment-id "$ROOT_COMP_ID" \
    --all \
    --raw-output \
    --query "data[?\"db-name\"=='${DB_NAME}'].id | [0]")
  echo -e "${CYAN}  Created ADB: ${ADB_OCID}${NC}"
else
  echo -e "${CYAN}  Reusing ADB: ${ADB_OCID}${NC}"
fi

echo
echo -e "${YELLOW}Step 2: Downloading wallet...${NC}"
mkdir -p "$WALLET_DIR"
oci db autonomous-database generate-wallet \
  --autonomous-database-id "$ADB_OCID" \
  --password "$WALLET_PWD" \
  --file "${WALLET_DIR}/${DB_NAME}_wallet.zip" \
  >/dev/null
(
  cd "$WALLET_DIR"
  unzip -oq "${DB_NAME}_wallet.zip"
)

echo
echo -e "${YELLOW}Step 3: Creating or reusing database/resource app...${NC}"
db_app_json=$(find_app_json "$ENTRA_DB_APP_NAME")
db_object_id=$(printf '%s' "$db_app_json" | json_get_or_empty 'data.get("id")')
db_app_id=$(printf '%s' "$db_app_json" | json_get_or_empty 'data.get("appId")')

if [ -z "$db_app_id" ]; then
  db_app_json=$(az ad app create \
    --display-name "$ENTRA_DB_APP_NAME" \
    --sign-in-audience AzureADMyOrg \
    -o json)
  db_object_id=$(printf '%s' "$db_app_json" | json_get 'data["id"]')
  db_app_id=$(printf '%s' "$db_app_json" | json_get 'data["appId"]')
  echo -e "${CYAN}  Created DB app: ${db_app_id}${NC}"
else
  echo -e "${CYAN}  Reusing DB app: ${db_app_id}${NC}"
fi
ensure_service_principal "$db_app_id"

db_app_full=$(az ad app show --id "$db_app_id" -o json)
employees_role_id=$(printf '%s' "$db_app_full" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((r["id"] for r in d.get("appRoles",[]) if r.get("value")=="EMPLOYEES"), ""))')
managers_role_id=$(printf '%s' "$db_app_full" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((r["id"] for r in d.get("appRoles",[]) if r.get("value")=="MANAGERS"), ""))')
scope_id=$(printf '%s' "$db_app_full" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((s["id"] for s in d.get("api",{}).get("oauth2PermissionScopes",[]) if s.get("value")=="session:scope:connect"), ""))')

[ -n "$employees_role_id" ] || employees_role_id=$(new_uuid)
[ -n "$managers_role_id" ] || managers_role_id=$(new_uuid)
[ -n "$scope_id" ] || scope_id=$(new_uuid)

db_patch=$(mktemp)
APP_ID_URI="$APP_ID_URI" EMPLOYEES_ROLE_ID="$employees_role_id" MANAGERS_ROLE_ID="$managers_role_id" SCOPE_ID="$scope_id" ENTRA_SCOPE_VALUE="$ENTRA_SCOPE_VALUE" python3 - <<'PY' > "$db_patch"
import json, os
print(json.dumps({
    "identifierUris": [os.environ["APP_ID_URI"]],
    "api": {"oauth2PermissionScopes": [{
        "adminConsentDescription": "Connect to Oracle Autonomous Database",
        "adminConsentDisplayName": "Connect to Oracle Autonomous Database",
        "id": os.environ["SCOPE_ID"],
        "isEnabled": True,
        "type": "User",
        "userConsentDescription": "Connect to Oracle Autonomous Database",
        "userConsentDisplayName": "Connect to Oracle Autonomous Database",
        "value": os.environ["ENTRA_SCOPE_VALUE"],
    }]},
    "appRoles": [
        {"allowedMemberTypes": ["User", "Application"], "description": "EMPLOYEES", "displayName": "EMPLOYEES", "id": os.environ["EMPLOYEES_ROLE_ID"], "isEnabled": True, "value": "EMPLOYEES"},
        {"allowedMemberTypes": ["User", "Application"], "description": "MANAGERS", "displayName": "MANAGERS", "id": os.environ["MANAGERS_ROLE_ID"], "isEnabled": True, "value": "MANAGERS"},
    ],
}))
PY
graph_patch "https://graph.microsoft.com/v1.0/applications/${db_object_id}" "$db_patch"
rm -f "$db_patch"
echo -e "${CYAN}  Ensured DB app URI, scope, and app roles.${NC}"

echo
echo -e "${YELLOW}Step 4: Creating or reusing interactive client app...${NC}"
client_app_json=$(find_app_json "$ENTRA_CLIENT_APP_NAME")
client_object_id=$(printf '%s' "$client_app_json" | json_get_or_empty 'data.get("id")')
client_app_id=$(printf '%s' "$client_app_json" | json_get_or_empty 'data.get("appId")')

if [ -z "$client_app_id" ]; then
  client_app_json=$(az ad app create \
    --display-name "$ENTRA_CLIENT_APP_NAME" \
    --sign-in-audience AzureADMyOrg \
    --public-client-redirect-uris "http://localhost" \
    --is-fallback-public-client true \
    -o json)
  client_object_id=$(printf '%s' "$client_app_json" | json_get 'data["id"]')
  client_app_id=$(printf '%s' "$client_app_json" | json_get 'data["appId"]')
  echo -e "${CYAN}  Created client app: ${client_app_id}${NC}"
else
  echo -e "${CYAN}  Reusing client app: ${client_app_id}${NC}"
fi
ensure_service_principal "$client_app_id"

client_patch=$(mktemp)
DB_APP_ID="$db_app_id" SCOPE_ID="$scope_id" python3 - <<'PY' > "$client_patch"
import json, os
print(json.dumps({
    "isFallbackPublicClient": True,
    "publicClient": {"redirectUris": ["http://localhost"]},
    "requiredResourceAccess": [{
        "resourceAppId": os.environ["DB_APP_ID"],
        "resourceAccess": [{"id": os.environ["SCOPE_ID"], "type": "Scope"}],
    }],
}))
PY
graph_patch "https://graph.microsoft.com/v1.0/applications/${client_object_id}" "$client_patch"
rm -f "$client_patch"
echo -e "${CYAN}  Ensured client redirect URI and API permission.${NC}"

echo
echo -e "${YELLOW}Step 5: Granting admin consent and app role assignments...${NC}"
if az ad app permission admin-consent --id "$client_app_id" >/dev/null 2>&1; then
  echo -e "${CYAN}  Admin consent granted.${NC}"
else
  echo -e "${YELLOW}  WARNING: Could not grant admin consent automatically.${NC}"
  echo -e "${YELLOW}  In Azure Portal, grant admin consent for ${ENTRA_CLIENT_APP_NAME}.${NC}"
fi

assign_role_to_user() {
  local upn="$1"
  local role_name="$2"
  local role_id="$3"
  local user_id
  local sp_id
  local existing

  user_id=$(az ad user show --id "$upn" --query id --output tsv 2>/dev/null || true)
  if [ -z "$user_id" ]; then
    echo -e "${YELLOW}  User not found, skipping ${role_name} assignment: ${upn}${NC}"
    return
  fi

  sp_id=$(az ad sp show --id "$db_app_id" --query id --output tsv)
  existing=$(az rest --method GET \
    --uri "https://graph.microsoft.com/v1.0/users/${user_id}/appRoleAssignments" \
    --query "value[?resourceId=='${sp_id}' && appRoleId=='${role_id}'].id | [0]" \
    --output tsv 2>/dev/null || true)

  if [ -n "$existing" ]; then
    echo -e "${CYAN}  Assignment already exists: ${upn} -> ${role_name}${NC}"
    return
  fi

  body=$(mktemp)
  USER_ID="$user_id" SP_ID="$sp_id" ROLE_ID="$role_id" python3 - <<'PY' > "$body"
import json, os
print(json.dumps({
    "principalId": os.environ["USER_ID"],
    "resourceId": os.environ["SP_ID"],
    "appRoleId": os.environ["ROLE_ID"],
}))
PY
  if az rest --method POST \
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${sp_id}/appRoleAssignedTo" \
    --headers "Content-Type=application/json" \
    --body @"$body" >/dev/null 2>&1; then
    echo -e "${CYAN}  Assigned ${upn} -> ${role_name}${NC}"
  else
    echo -e "${YELLOW}  WARNING: Could not assign ${upn} -> ${role_name}${NC}"
  fi
  rm -f "$body"
}

if [ "$CREATE_APP_ROLE_ASSIGNMENTS" = "1" ]; then
  assign_role_to_user "$MARVIN_UPN" "EMPLOYEES" "$employees_role_id"
  assign_role_to_user "$MARVIN_UPN" "MANAGERS" "$managers_role_id"
  assign_role_to_user "$EMMA_UPN" "EMPLOYEES" "$employees_role_id"
else
  echo -e "${YELLOW}  Skipping app role assignments because CREATE_APP_ROLE_ASSIGNMENTS=${CREATE_APP_ROLE_ASSIGNMENTS}.${NC}"
fi

cat > "$ENV_FILE" <<EOF
export ROOT_COMP_ID='${ROOT_COMP_ID}'
export DB_NAME='${DB_NAME}'
export DB_DISPLAY_NAME='${DB_DISPLAY_NAME}'
export ADB_OCID='${ADB_OCID}'
export ADB_SERVICE='${ADB_SERVICE}'
export ADMIN_PWD='${ADMIN_PWD}'
export WALLET_PWD='${WALLET_PWD}'
export WALLET_DIR='${WALLET_DIR}'
export TNS_ADMIN='${WALLET_DIR}'
export TENANT_ID='${TENANT_ID}'
export DOMAIN_NAME='${DOMAIN_NAME}'
export APP_ID='${db_app_id}'
export APP_ID_URI='${APP_ID_URI}'
export CLIENT_ID='${client_app_id}'
export ENTRA_DB_APP_NAME='${ENTRA_DB_APP_NAME}'
export ENTRA_CLIENT_APP_NAME='${ENTRA_CLIENT_APP_NAME}'
export MARVIN_UPN='${MARVIN_UPN}'
export EMMA_UPN='${EMMA_UPN}'
EOF
chmod 600 "$ENV_FILE"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 0 Completed: ADB, Wallet, and Entra ID Objects Ready             ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}Environment file: ${ENV_FILE}${NC}"
echo "Load it before continuing:"
echo "  source ./.adb-entra-id.env"
echo
