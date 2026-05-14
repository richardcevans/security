#!/bin/bash
# Create or reuse an Autonomous Database Serverless instance and wallet.
# Intended to run from OCI Cloud Shell.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.adb-oci-iam.env"
WORK_DIR="${SCRIPT_DIR}/.oci-iam-setup"

usage() {
  cat <<'EOF'
Usage:
  ./00_setup_adb.sh [compartment-name|compartment-ocid|root]

Compartment selection:
  ROOT_COMP_ID       Direct compartment OCID. Highest priority.
  OCI_COMPARTMENT    Compartment name, compartment OCID, or root.
  argument           Same as OCI_COMPARTMENT.

If none is provided, the script uses the root compartment.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

show_cmd() {
  printf '  $'
  printf ' %q' "$@"
  printf '\n'
}

export DB_NAME="${DB_NAME:-deepsec1}"
export DB_DISPLAY_NAME="${DB_DISPLAY_NAME:-${DB_NAME}}"
if [ "$DB_NAME" != "deepsec1" ] && [ "$DB_DISPLAY_NAME" = "deepsec1" ]; then
  DB_DISPLAY_NAME="$DB_NAME"
fi
export DB_DISPLAY_NAME
export DB_VERSION="${DB_VERSION:-26ai}"
export ADMIN_PWD="${ADMIN_PWD:-Oracle123+Oracle123+}"
export WALLET_PWD="${WALLET_PWD:-Oracle123+}"
export WALLET_DIR="${WALLET_DIR:-$HOME/adb_wallet/${DB_NAME}}"
export ADB_SERVICE="${ADB_SERVICE:-${DB_NAME}_low}"
export OCI_IAM_EMPLOYEE_GROUP="${OCI_IAM_EMPLOYEE_GROUP:-EMPLOYEES}"
export OCI_IAM_MANAGER_GROUP="${OCI_IAM_MANAGER_GROUP:-MANAGERS}"
export TENANCY_OCID="${TENANCY_OCID:-${OCI_TENANCY:-}}"
export OCI_COMPARTMENT="${1:-${OCI_COMPARTMENT:-root}}"
export OCI_DB_APP_NAME="${OCI_DB_APP_NAME:-${DB_NAME} ADB OCI IAM DB Resource}"
export OCI_CLIENT_APP_NAME="${OCI_CLIENT_APP_NAME:-${DB_NAME} ADB OCI IAM Public Client}"
export OCI_DOMAIN_NAME="${OCI_DOMAIN_NAME:-Default}"
export OCI_DB_AUDIENCE="${OCI_DB_AUDIENCE:-${DB_NAME}OracleDB}"
export OCI_DB_SCOPE_VALUE="${OCI_DB_SCOPE_VALUE:-${DB_NAME}_DB_ACCESS_SCOPE}"
export OCI_SCOPE="${OCI_SCOPE:-${OCI_DB_AUDIENCE}${OCI_DB_SCOPE_VALUE}}"
DEFAULT_REDIRECT_URIS="http://localhost:8888/callback,http://localhost:8889/callback,http://localhost:8890/callback,http://127.0.0.1:8888/callback,http://127.0.0.1:8889/callback,http://127.0.0.1:8890/callback"
export OCI_REDIRECT_URI="${OCI_REDIRECT_URI:-http://localhost:8888/callback}"
export OCI_REDIRECT_URIS="${OCI_REDIRECT_URIS:-$DEFAULT_REDIRECT_URIS}"

if [ "$OCI_DB_APP_NAME" = "ADB OCI IAM DB Resource" ]; then
  OCI_DB_APP_NAME="${DB_NAME} ADB OCI IAM DB Resource"
  export OCI_DB_APP_NAME
fi
if [ "$OCI_CLIENT_APP_NAME" = "ADB OCI IAM Public Client" ]; then
  OCI_CLIENT_APP_NAME="${DB_NAME} ADB OCI IAM Public Client"
  export OCI_CLIENT_APP_NAME
fi
if [ "$OCI_DB_AUDIENCE" = "OracleDB" ]; then
  OCI_DB_AUDIENCE="${DB_NAME}OracleDB"
  export OCI_DB_AUDIENCE
fi
if [ "$OCI_DB_SCOPE_VALUE" = "DB_ACCESS_SCOPE" ]; then
  OCI_DB_SCOPE_VALUE="${DB_NAME}_DB_ACCESS_SCOPE"
  export OCI_DB_SCOPE_VALUE
fi
if [ "$OCI_SCOPE" = "OracleDBDB_ACCESS_SCOPE" ]; then
  OCI_SCOPE="${OCI_DB_AUDIENCE}${OCI_DB_SCOPE_VALUE}"
  export OCI_SCOPE
fi

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 0: Create OCI IAM Apps, ADB-S Instance, and Wallet               ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

if ! command -v oci >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI is not available. Run this from OCI Cloud Shell or install OCI CLI.${NC}"
  exit 1
fi

if ! oci iam region list >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI cannot call OCI. In Cloud Shell, refresh the session or check your tenancy.${NC}"
  exit 1
fi

mkdir -p "$WORK_DIR"

oci_global_args=()
[ -n "${OCI_CONFIG_FILE:-${OCI_CLI_CONFIG_FILE:-}}" ] && oci_global_args+=(--config-file "${OCI_CONFIG_FILE:-${OCI_CLI_CONFIG_FILE:-}}")
[ -n "${OCI_PROFILE:-${OCI_CLI_PROFILE:-}}" ] && oci_global_args+=(--profile "${OCI_PROFILE:-${OCI_CLI_PROFILE:-}}")

read_oci_config_value() {
  local key="$1"
  local profile="${OCI_PROFILE:-${OCI_CLI_PROFILE:-DEFAULT}}"
  local config_file="${OCI_CONFIG_FILE:-${OCI_CLI_CONFIG_FILE:-$HOME/.oci/config}}"

  if [ ! -f "$config_file" ]; then
    return 0
  fi

  awk -F= -v section="[$profile]" -v key="$key" '
    $0 == section { in_section = 1; next }
    /^\[/ { in_section = 0 }
    in_section && $1 == key {
      value = $2
      sub(/^[ \t]+/, "", value)
      sub(/[ \t]+$/, "", value)
      print value
      exit
    }
  ' "$config_file"
}

normalize_redirect_uri() {
  local first_uri
  if [[ "$OCI_REDIRECT_URI" == *":8080/"* ]] || [[ "$OCI_REDIRECT_URIS" != *"localhost:8888/callback"* ]]; then
    echo -e "${YELLOW}Replacing stale OAuth redirect settings with lab defaults.${NC}"
    OCI_REDIRECT_URIS="$DEFAULT_REDIRECT_URIS"
    export OCI_REDIRECT_URIS
  fi

  first_uri="${OCI_REDIRECT_URIS%%,*}"
  if [ -n "$OCI_REDIRECT_URIS" ] && [[ ",${OCI_REDIRECT_URIS}," != *",${OCI_REDIRECT_URI},"* ]]; then
    echo -e "${YELLOW}Ignoring stale OCI_REDIRECT_URI=${OCI_REDIRECT_URI}${NC}"
    echo -e "${YELLOW}Using OCI_REDIRECT_URI=${first_uri}${NC}"
    OCI_REDIRECT_URI="$first_uri"
    export OCI_REDIRECT_URI
  fi
}

discover_domain_url() {
  if [ -n "${OCI_DOMAIN_URL:-}" ]; then
    printf '%s' "$OCI_DOMAIN_URL"
    return
  fi

  local url
  url=$(oci iam domain list \
    --compartment-id "$TENANCY_OCID" \
    --all \
    "${oci_global_args[@]}" \
    --query "data[?lifecycleState==\`ACTIVE\` && displayName==\`${OCI_DOMAIN_NAME}\`].url | [0]" \
    --raw-output 2>/dev/null || true)

  if [ -z "$url" ] || [ "$url" = "null" ] || [ "$url" = "None" ]; then
    url=$(oci iam domain list \
      --compartment-id "$TENANCY_OCID" \
      --all \
      "${oci_global_args[@]}" \
      --query 'data[?lifecycleState==`ACTIVE`].url | [0]' \
      --raw-output 2>/dev/null || true)
  fi

  if [ -z "$url" ] || [ "$url" = "null" ] || [ "$url" = "None" ]; then
    echo -e "${RED}ERROR: Could not discover an active OCI IAM domain URL.${NC}" >&2
    echo -e "${YELLOW}Export OCI_DOMAIN_URL from Console -> Identity & Security -> Domains -> Overview.${NC}" >&2
    exit 1
  fi

  printf '%s' "$url"
}

domain_cmd() {
  oci identity-domains "$@" --endpoint "$OCI_DOMAIN_URL" "${oci_global_args[@]}"
}

raw_request() {
  oci raw-request "$@" "${oci_global_args[@]}"
}

first_query() {
  local command="$1"
  local q1="$2"
  local q2="$3"
  local value
  value=$(eval "$command --query '$q1' --raw-output" 2>/dev/null || true)
  if [ -z "$value" ] || [ "$value" = "null" ] || [ "$value" = "None" ]; then
    value=$(eval "$command --query '$q2' --raw-output" 2>/dev/null || true)
  fi
  [ "$value" = "null" ] || [ "$value" = "None" ] && value=""
  printf '%s' "$value"
}

find_domain_app_id() {
  local name="$1"
  first_query \
    "domain_cmd apps list --all --attribute-sets all --filter 'displayName eq \"${name}\"'" \
    'data.Resources[0].id' \
    'data.resources[0].id'
}

get_domain_app_field() {
  local app_id="$1"
  local field="$2"
  local response
  response=$(domain_cmd app get --app-id "$app_id" --attribute-sets all 2>/dev/null || true)
  [ -z "$response" ] && return

  APP_RESPONSE="$response" python3 - "$field" <<'PY'
import json
import os
import sys

field = sys.argv[1]
try:
    raw = json.loads(os.environ.get("APP_RESPONSE", "{}"))
except Exception:
    sys.exit(0)

data = raw.get("data") or {}
aliases = {
    "client_id": [
        "clientId",
        "client_id",
        "clientID",
        "oauthClientId",
        "oAuthClientId",
        "appId",
        "app_id",
        "name",
        "id",
    ],
    "client_secret": [
        "clientSecret",
        "client_secret",
        "oauthClientSecret",
        "oAuthClientSecret",
    ],
}

for key in aliases.get(field, [field]):
    value = data.get(key)
    if value:
        print(value)
        break
PY
}

generate_secret() {
  local secret
  secret=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48 || true)
  printf '%s' "$secret"
}

regenerate_app_client_secret() {
  local app_id="$1"
  local body="${WORK_DIR}/regenerate-client-secret-${app_id}.json"
  local response

  cat > "$body" <<EOF
{
  "schemas": [
    "urn:ietf:params:scim:schemas:oracle:idcs:AppClientSecretRegenerator"
  ],
  "appId": "${app_id}"
}
EOF

  response=$(raw_request \
    --http-method POST \
    --target-uri "${OCI_DOMAIN_URL}/admin/v1/AppClientSecretRegenerator?attributeSets=all" \
    --request-headers '{"Content-Type":"application/scim+json"}' \
    --request-body "file://${body}" 2>/dev/null || true)

  RAW_RESPONSE="$response" python3 - <<'PY'
import json
import os
import sys

try:
    raw = json.loads(os.environ.get("RAW_RESPONSE", "{}"))
except Exception:
    sys.exit(0)

data = raw.get("data") or raw
secret = data.get("clientSecret") or data.get("client_secret")
if secret:
    print(secret)
PY
}

redirect_uris_json() {
  REDIRECT_URIS="$OCI_REDIRECT_URIS" python3 - <<'PY'
import json
import os

uris = [uri.strip() for uri in os.environ["REDIRECT_URIS"].split(",") if uri.strip()]
print(json.dumps(uris))
PY
}

create_or_reuse_db_resource_app() {
  local app_id
  local generated_secret
  app_id=$(find_domain_app_id "$OCI_DB_APP_NAME")
  if [ -n "$app_id" ]; then
    echo -e "${CYAN}  Reusing DB resource app ${OCI_DB_APP_NAME}: ${app_id}${NC}" >&2
  else
    generated_secret=$(generate_secret)
    echo -e "${CYAN}  Creating DB resource app ${OCI_DB_APP_NAME}:${NC}" >&2
    show_cmd oci identity-domains app create \
      --endpoint "$OCI_DOMAIN_URL" \
      --display-name "$OCI_DB_APP_NAME" \
      --audience "$OCI_DB_AUDIENCE" \
      --scopes "[{\"value\":\"${OCI_DB_SCOPE_VALUE}\"}]" >&2
    app_id=$(domain_cmd app create \
      --schemas '["urn:ietf:params:scim:schemas:oracle:idcs:App"]' \
      --based-on-template '{"value":"CustomWebAppTemplateId","wellKnownId":"CustomWebAppTemplateId"}' \
      --display-name "$OCI_DB_APP_NAME" \
      --description "Database resource app for the ADB OCI IAM Deep Data Security lab" \
      --active true \
      --is-o-auth-client true \
      --is-o-auth-resource true \
      --client-type confidential \
      --client-secret "$generated_secret" \
      --audience "$OCI_DB_AUDIENCE" \
      --scopes "[{\"value\":\"${OCI_DB_SCOPE_VALUE}\",\"displayName\":\"DB Access\",\"description\":\"Access the ADB lab database\",\"requiresConsent\":false}]" \
      --allowed-grants '["client_credentials"]' \
      --bypass-consent true \
      --attribute-sets all \
      --query 'data.id' \
      --raw-output)
    OCI_DB_CLIENT_SECRET="$generated_secret"
    echo -e "${CYAN}  Created DB resource app: ${app_id}${NC}" >&2
  fi
  printf '%s' "$app_id"
}

configure_public_client_app() {
  local app_id="$1"
  local redirect_json
  redirect_json=$(redirect_uris_json)

  domain_cmd app patch \
    --app-id "$app_id" \
    --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
    --operations "[{\"op\":\"replace\",\"path\":\"allowedGrants\",\"value\":[\"authorization_code\"]},{\"op\":\"replace\",\"path\":\"redirectUris\",\"value\":${redirect_json}},{\"op\":\"replace\",\"path\":\"allowedScopes\",\"value\":[{\"fqs\":\"${OCI_SCOPE}\"}]}]" \
    >/dev/null
}

create_or_reuse_public_client_app() {
  local app_id
  local redirect_json
  redirect_json=$(redirect_uris_json)
  app_id=$(find_domain_app_id "$OCI_CLIENT_APP_NAME")
  if [ -n "$app_id" ]; then
    echo -e "${CYAN}  Reusing public client app ${OCI_CLIENT_APP_NAME}: ${app_id}${NC}" >&2
  else
    echo -e "${CYAN}  Creating public client app ${OCI_CLIENT_APP_NAME}:${NC}" >&2
    show_cmd oci identity-domains app create \
      --endpoint "$OCI_DOMAIN_URL" \
      --display-name "$OCI_CLIENT_APP_NAME" \
      --client-type public \
      --allowed-grants '["authorization_code"]' \
      --allowed-scopes "[{\"fqs\":\"${OCI_SCOPE}\"}]" >&2
    app_id=$(domain_cmd app create \
      --schemas '["urn:ietf:params:scim:schemas:oracle:idcs:App"]' \
      --based-on-template '{"value":"CustomWebAppTemplateId","wellKnownId":"CustomWebAppTemplateId"}' \
      --display-name "$OCI_CLIENT_APP_NAME" \
      --description "Public interactive OAuth client for the ADB OCI IAM Deep Data Security lab" \
      --active true \
      --is-o-auth-client true \
      --client-type public \
      --allowed-grants '["authorization_code"]' \
      --allowed-scopes "[{\"fqs\":\"${OCI_SCOPE}\"}]" \
      --redirect-uris "$redirect_json" \
      --all-url-schemes-allowed true \
      --attribute-sets all \
      --query 'data.id' \
      --raw-output)
    echo -e "${CYAN}  Created public client app: ${app_id}${NC}" >&2
  fi

  configure_public_client_app "$app_id"
  printf '%s' "$app_id"
}

create_group_claim() {
  local body="${WORK_DIR}/custom-claim-group.json"
  cat > "$body" <<'JSON'
{
  "schemas": [
    "urn:ietf:params:scim:schemas:oracle:idcs:CustomClaim"
  ],
  "name": "group",
  "value": "$user.groups.*.display",
  "expression": true,
  "mode": "always",
  "tokenType": "AT",
  "allScopes": true
}
JSON

  raw_request \
    --http-method POST \
    --target-uri "${OCI_DOMAIN_URL}/admin/v1/CustomClaims" \
    --request-headers '{"Content-Type":"application/scim+json"}' \
    --request-body "file://${body}" \
    >/dev/null 2>&1 || {
      echo -e "${YELLOW}  Could not create the group custom claim automatically.${NC}"
      echo -e "${YELLOW}  If data roles do not activate, create a custom access-token claim named group with value '\$user.groups.*.display'.${NC}"
    }
}

setup_oauth_apps() {
  normalize_redirect_uri
  OCI_DOMAIN_URL=$(discover_domain_url)
  export OCI_DOMAIN_URL

  echo
  echo -e "${YELLOW}Step 1: Creating or reusing OCI IAM OAuth applications...${NC}"
  echo -e "${CYAN}  OCI_DOMAIN_URL    = ${OCI_DOMAIN_URL}${NC}"
  echo -e "${CYAN}  OCI_DB_APP_NAME   = ${OCI_DB_APP_NAME}${NC}"
  echo -e "${CYAN}  OCI_CLIENT_APP    = ${OCI_CLIENT_APP_NAME}${NC}"
  echo -e "${CYAN}  OCI_SCOPE         = ${OCI_SCOPE}${NC}"
  echo -e "${CYAN}  OCI_REDIRECT_URIS = ${OCI_REDIRECT_URIS}${NC}"

  OCI_DB_APP_ID=$(create_or_reuse_db_resource_app)
  OCI_DB_CLIENT_ID=$(get_domain_app_field "$OCI_DB_APP_ID" client_id)
  if [ -z "${OCI_DB_CLIENT_SECRET:-}" ]; then
    OCI_DB_CLIENT_SECRET=$(get_domain_app_field "$OCI_DB_APP_ID" client_secret)
  fi
  if [ -z "${OCI_DB_CLIENT_SECRET:-}" ]; then
    echo -e "${CYAN}  Resetting DB resource app secret for database-side OAuth validation...${NC}"
    OCI_DB_CLIENT_SECRET=$(regenerate_app_client_secret "$OCI_DB_APP_ID")
  fi
  OCI_CLIENT_APP_ID=$(create_or_reuse_public_client_app)
  OCI_CLIENT_ID=$(get_domain_app_field "$OCI_CLIENT_APP_ID" client_id)

  if [ -z "$OCI_DB_CLIENT_ID" ]; then
    echo -e "${RED}ERROR: Could not determine OAuth client id for DB resource app ${OCI_DB_APP_ID}.${NC}"
    echo -e "${YELLOW}Inspect it with:${NC}"
    echo "  oci identity-domains app get --endpoint '${OCI_DOMAIN_URL}' --app-id '${OCI_DB_APP_ID}' --attribute-sets all"
    exit 1
  fi
  if [ -z "$OCI_DB_CLIENT_SECRET" ]; then
    echo -e "${RED}ERROR: Could not determine or reset the DB resource app client secret for ${OCI_DB_APP_ID}.${NC}"
    exit 1
  fi
  if [ -z "$OCI_CLIENT_ID" ]; then
    echo -e "${RED}ERROR: Could not determine OAuth client id for app ${OCI_CLIENT_APP_ID}.${NC}"
    echo -e "${YELLOW}Inspect it with:${NC}"
    echo "  oci identity-domains app get --endpoint '${OCI_DOMAIN_URL}' --app-id '${OCI_CLIENT_APP_ID}' --attribute-sets all"
    exit 1
  fi

  echo
  echo -e "${YELLOW}Step 2: Creating access-token group claim...${NC}"
  create_group_claim
}

if [ -z "$TENANCY_OCID" ]; then
  TENANCY_OCID="$(read_oci_config_value tenancy)"
fi

if [ -z "${ROOT_COMP_ID:-}" ]; then
  if [ -z "$TENANCY_OCID" ]; then
    echo -e "${RED}ERROR: Could not determine the tenancy OCID needed to resolve compartments.${NC}"
    echo -e "${YELLOW}Set one of these values, then rerun:${NC}"
    echo "  export TENANCY_OCID=ocid1.tenancy.oc1..aaaa..."
    echo "  export OCI_TENANCY=ocid1.tenancy.oc1..aaaa..."
    echo "  export ROOT_COMP_ID=ocid1.compartment.oc1..aaaa..."
    exit 1
  fi

  if [ "${OCI_COMPARTMENT,,}" = "root" ]; then
    ROOT_COMP_ID="$TENANCY_OCID"
  elif [[ "$OCI_COMPARTMENT" == ocid1.compartment.* ]]; then
    ROOT_COMP_ID="$OCI_COMPARTMENT"
  else
    ROOT_COMP_ID=$(oci iam compartment list \
      --compartment-id "$TENANCY_OCID" \
      --compartment-id-in-subtree true \
      --access-level ACCESSIBLE \
      --lifecycle-state ACTIVE \
      --all \
      --raw-output \
      --query "data[?name=='${OCI_COMPARTMENT}'].id | [0]")

    if [ -z "$ROOT_COMP_ID" ] || [ "$ROOT_COMP_ID" = "null" ]; then
      echo -e "${RED}ERROR: Could not find an accessible active compartment named ${OCI_COMPARTMENT}.${NC}"
      echo -e "${YELLOW}Use one of these options:${NC}"
      echo "  ./00_setup_adb.sh root"
      echo "  ./00_setup_adb.sh <compartment-name>"
      echo "  export OCI_COMPARTMENT=<compartment-name>"
      echo "  export ROOT_COMP_ID=ocid1.compartment.oc1..aaaa..."
      exit 1
    fi
  fi
fi
export ROOT_COMP_ID

setup_oauth_apps

echo -e "${CYAN}Configuration:${NC}"
echo -e "${CYAN}  OCI_COMPARTMENT = ${OCI_COMPARTMENT}${NC}"
echo -e "${CYAN}  ROOT_COMP_ID    = ${ROOT_COMP_ID}${NC}"
echo -e "${CYAN}  DB_NAME         = ${DB_NAME}${NC}"
echo -e "${CYAN}  DB_DISPLAY_NAME = ${DB_DISPLAY_NAME}${NC}"
echo -e "${CYAN}  DB_VERSION      = ${DB_VERSION}${NC}"
echo -e "${CYAN}  ADB_SERVICE     = ${ADB_SERVICE}${NC}"
echo -e "${CYAN}  WALLET_DIR      = ${WALLET_DIR}${NC}"
echo -e "${CYAN}  IAM groups      = ${OCI_IAM_EMPLOYEE_GROUP}, ${OCI_IAM_MANAGER_GROUP}${NC}"
echo -e "${CYAN}  OAuth client    = ${OCI_CLIENT_ID}${NC}"
echo -e "${CYAN}  Deep Data Security end-user context grants require Autonomous Database 26ai.${NC}"
echo

echo -e "${YELLOW}Step 3: Creating or reusing Autonomous Database...${NC}"
echo -e "${CYAN}  Checking for existing ADB:${NC}"
show_cmd oci db autonomous-database list \
  --compartment-id "$ROOT_COMP_ID" \
  --lifecycle-state AVAILABLE \
  --all \
  --raw-output \
  --query "data[?\"db-name\"=='${DB_NAME}'].id | [0]"
ADB_OCID=$(oci db autonomous-database list \
  --compartment-id "$ROOT_COMP_ID" \
  --lifecycle-state AVAILABLE \
  --all \
  --raw-output \
  --query "data[?\"db-name\"=='${DB_NAME}'].id | [0]")
ADB_DB_VERSION=$(oci db autonomous-database list \
  --compartment-id "$ROOT_COMP_ID" \
  --lifecycle-state AVAILABLE \
  --all \
  --raw-output \
  --query "data[?\"db-name\"=='${DB_NAME}'].\"db-version\" | [0]")
ADB_ANY_STATE=$(oci db autonomous-database list \
  --compartment-id "$ROOT_COMP_ID" \
  --all \
  --raw-output \
  --query "data[?\"db-name\"=='${DB_NAME}'].\"lifecycle-state\" | [0]")

if [ -z "$ADB_OCID" ] || [ "$ADB_OCID" = "null" ]; then
  if [ -n "$ADB_ANY_STATE" ] && [ "$ADB_ANY_STATE" != "null" ]; then
    echo -e "${YELLOW}  Found ${DB_NAME} in lifecycle state ${ADB_ANY_STATE}; it is not reusable for this lab.${NC}"
  fi
  echo -e "${CYAN}  Creating ADB:${NC}"
  show_cmd oci db autonomous-database create \
    --compartment-id "$ROOT_COMP_ID" \
    --db-name "$DB_NAME" \
    --display-name "$DB_DISPLAY_NAME" \
    --db-version "$DB_VERSION" \
    --is-free-tier true \
    --admin-password '<hidden>' \
    --cpu-core-count 1 \
    --data-storage-size-in-tbs 1 \
    --wait-for-state AVAILABLE
  oci db autonomous-database create \
    --compartment-id "$ROOT_COMP_ID" \
    --db-name "$DB_NAME" \
    --display-name "$DB_DISPLAY_NAME" \
    --db-version "$DB_VERSION" \
    --is-free-tier true \
    --admin-password "$ADMIN_PWD" \
    --cpu-core-count 1 \
    --data-storage-size-in-tbs 1 \
    --wait-for-state AVAILABLE \
    >/dev/null

  ADB_OCID=$(oci db autonomous-database list \
    --compartment-id "$ROOT_COMP_ID" \
    --lifecycle-state AVAILABLE \
    --all \
    --raw-output \
    --query "data[?\"db-name\"=='${DB_NAME}'].id | [0]")
  ADB_DB_VERSION=$(oci db autonomous-database list \
    --compartment-id "$ROOT_COMP_ID" \
    --lifecycle-state AVAILABLE \
    --all \
    --raw-output \
    --query "data[?\"db-name\"=='${DB_NAME}'].\"db-version\" | [0]")
  echo -e "${CYAN}  Created ADB: ${ADB_OCID}${NC}"
  echo -e "${CYAN}  Created ADB version: ${ADB_DB_VERSION}${NC}"
else
  if [ "$ADB_DB_VERSION" != "$DB_VERSION" ]; then
    echo -e "${RED}ERROR: Found existing ADB ${DB_NAME}, but it is ${ADB_DB_VERSION}, not ${DB_VERSION}.${NC}"
    echo -e "${YELLOW}This lab requires Autonomous Database ${DB_VERSION} for Deep Data Security end-user context privileges.${NC}"
    echo -e "${YELLOW}Use a different DB_NAME or delete/recreate the existing database as ${DB_VERSION}.${NC}"
    exit 1
  fi
  echo -e "${CYAN}  Reusing ADB: ${ADB_OCID}${NC}"
  echo -e "${CYAN}  Existing ADB version: ${ADB_DB_VERSION}${NC}"
fi

echo
echo -e "${YELLOW}Step 4: Downloading wallet...${NC}"
mkdir -p "$WALLET_DIR"
show_cmd oci db autonomous-database generate-wallet \
  --autonomous-database-id "$ADB_OCID" \
  --password '<hidden>' \
  --file "${WALLET_DIR}/${DB_NAME}_wallet.zip"
oci db autonomous-database generate-wallet \
  --autonomous-database-id "$ADB_OCID" \
  --password "$WALLET_PWD" \
  --file "${WALLET_DIR}/${DB_NAME}_wallet.zip" \
  >/dev/null

(
  cd "$WALLET_DIR"
  unzip -oq "${DB_NAME}_wallet.zip"
)

if [ -f "${WALLET_DIR}/sqlnet.ora" ]; then
  echo -e "${CYAN}  Rewriting sqlnet.ora wallet directory to ${WALLET_DIR}:${NC}"
  show_cmd sed -i.bak-wallet-dir -E "s#DIRECTORY=\"\\?/network/admin\"#DIRECTORY=\"${WALLET_DIR}\"#g" "${WALLET_DIR}/sqlnet.ora"
  sed -i.bak-wallet-dir -E "s#DIRECTORY=\"\\?/network/admin\"#DIRECTORY=\"${WALLET_DIR}\"#g" "${WALLET_DIR}/sqlnet.ora"
fi

echo
echo -e "${YELLOW}Step 5: Creating or reusing IAM groups for the lab...${NC}"

ensure_group() {
  local group_name="$1"
  local group_id

  echo -e "${CYAN}  Checking IAM group ${group_name}:${NC}" >&2
  show_cmd oci iam group list \
    --all \
    --raw-output \
    --query "data[?name=='${group_name}'].id | [0]" >&2
  group_id=$(oci iam group list \
    --all \
    --raw-output \
    --query "data[?name=='${group_name}'].id | [0]" 2>/dev/null || true)

  if [ -z "$group_id" ] || [ "$group_id" = "null" ]; then
    if [ -z "$TENANCY_OCID" ]; then
      echo -e "${RED}ERROR: TENANCY_OCID is not set and group ${group_name} does not exist.${NC}" >&2
      echo "Set TENANCY_OCID to the tenancy OCID, then rerun this script." >&2
      exit 1
    fi
    echo -e "${CYAN}  Creating IAM group ${group_name}:${NC}" >&2
    show_cmd oci iam group create \
      --compartment-id "$TENANCY_OCID" \
      --name "$group_name" \
      --description "Deep Data Security ADB lab group ${group_name}" \
      --raw-output \
      --query 'data.id' >&2
    group_id=$(oci iam group create \
      --compartment-id "$TENANCY_OCID" \
      --name "$group_name" \
      --description "Deep Data Security ADB lab group ${group_name}" \
      --raw-output \
      --query 'data.id')
    echo -e "${CYAN}  Created group ${group_name}: ${group_id}${NC}" >&2
  else
    echo -e "${CYAN}  Reusing group ${group_name}: ${group_id}${NC}" >&2
  fi

  printf '%s' "$group_id"
}

EMPLOYEES_OCID=$(ensure_group "$OCI_IAM_EMPLOYEE_GROUP")
MANAGERS_OCID=$(ensure_group "$OCI_IAM_MANAGER_GROUP")

ADB_LAB_USER_OCID="${ADB_LAB_USER_OCID:-${OCI_CS_USER_OCID:-}}"
ADB_LAB_USERNAME="${ADB_LAB_USERNAME:-}"

if [ -n "$ADB_LAB_USER_OCID" ]; then
  echo -e "${CYAN}  Resolving lab user name:${NC}"
  show_cmd oci iam user get \
    --user-id "$ADB_LAB_USER_OCID" \
    --raw-output \
    --query 'data.name'
  ADB_LAB_USERNAME=$(oci iam user get \
    --user-id "$ADB_LAB_USER_OCID" \
    --raw-output \
    --query 'data.name')

  add_user_to_group() {
    local group_id="$1"
    local group_name="$2"
    local already_member

    echo -e "${CYAN}  Checking ${ADB_LAB_USERNAME} membership in ${group_name}:${NC}"
    show_cmd oci iam group list-users \
      --group-id "$group_id" \
      --all \
      --raw-output \
      --query "data[?id=='${ADB_LAB_USER_OCID}'].id | [0]"
    already_member=$(oci iam group list-users \
      --group-id "$group_id" \
      --all \
      --raw-output \
      --query "data[?id=='${ADB_LAB_USER_OCID}'].id | [0]" 2>/dev/null || true)

    if [ -z "$already_member" ] || [ "$already_member" = "null" ]; then
      echo -e "${CYAN}  Adding ${ADB_LAB_USERNAME} to ${group_name}:${NC}"
      show_cmd oci iam group add-user \
        --group-id "$group_id" \
        --user-id "$ADB_LAB_USER_OCID"
      oci iam group add-user \
        --group-id "$group_id" \
        --user-id "$ADB_LAB_USER_OCID" \
        >/dev/null
      echo -e "${CYAN}  Added ${ADB_LAB_USERNAME} to ${group_name}${NC}"
    else
      echo -e "${CYAN}  ${ADB_LAB_USERNAME} is already in ${group_name}${NC}"
    fi
  }

  add_user_to_group "$EMPLOYEES_OCID" "$OCI_IAM_EMPLOYEE_GROUP"
  add_user_to_group "$MANAGERS_OCID" "$OCI_IAM_MANAGER_GROUP"
else
  echo -e "${YELLOW}  OCI_CS_USER_OCID was not set, so current-user group membership was skipped.${NC}"
  echo -e "${YELLOW}  Set ADB_LAB_USER_OCID and rerun this script if you want it to add a user to the lab groups.${NC}"
fi

cat > "$ENV_FILE" <<EOF
export OCI_COMPARTMENT='${OCI_COMPARTMENT}'
export ROOT_COMP_ID='${ROOT_COMP_ID}'
export DB_NAME='${DB_NAME}'
export DB_DISPLAY_NAME='${DB_DISPLAY_NAME}'
export DB_VERSION='${DB_VERSION}'
export ADB_OCID='${ADB_OCID}'
export ADB_SERVICE='${ADB_SERVICE}'
export ADMIN_PWD='${ADMIN_PWD}'
export WALLET_PWD='${WALLET_PWD}'
export WALLET_DIR='${WALLET_DIR}'
export TNS_ADMIN='${WALLET_DIR}'
export OCI_TOKEN_DIR='${OCI_TOKEN_DIR:-$HOME/.oci/adb-oci-iam}'
export TENANCY_OCID='${TENANCY_OCID}'
export OCI_DOMAIN_URL='${OCI_DOMAIN_URL}'
export OCI_DB_APP_ID='${OCI_DB_APP_ID}'
export OCI_DB_CLIENT_ID='${OCI_DB_CLIENT_ID}'
export OCI_DB_CLIENT_SECRET='${OCI_DB_CLIENT_SECRET}'
export OCI_CLIENT_APP_ID='${OCI_CLIENT_APP_ID}'
export OCI_CLIENT_ID='${OCI_CLIENT_ID}'
export OCI_AUDIENCE='${OCI_DB_AUDIENCE}'
export OCI_SCOPE='${OCI_SCOPE}'
export OCI_REDIRECT_URI='${OCI_REDIRECT_URI}'
export OCI_REDIRECT_URIS='${OCI_REDIRECT_URIS}'
export OCI_DB_APP_NAME='${OCI_DB_APP_NAME}'
export OCI_CLIENT_APP_NAME='${OCI_CLIENT_APP_NAME}'
export OCI_IAM_EMPLOYEE_GROUP='${OCI_IAM_EMPLOYEE_GROUP}'
export OCI_IAM_MANAGER_GROUP='${OCI_IAM_MANAGER_GROUP}'
export EMPLOYEES_OCID='${EMPLOYEES_OCID}'
export MANAGERS_OCID='${MANAGERS_OCID}'
export ADB_LAB_USER_OCID='${ADB_LAB_USER_OCID}'
export ADB_LAB_USERNAME='${ADB_LAB_USERNAME}'
EOF
chmod 600 "$ENV_FILE"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 0 Completed: OCI IAM Apps, ADB, and Wallet Ready                 ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}Environment file: ${ENV_FILE}${NC}"
echo "Load it before continuing:"
echo "  source ./.adb-oci-iam.env"
echo
