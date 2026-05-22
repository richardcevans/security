#!/bin/bash
# Create the OCI IAM domain objects used by this lab.
# Prerequisite: OCI CLI is installed and ~/.oci/config is configured.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.oci-iam-data-grants.env"
INSTANCE_FILE="${SCRIPT_DIR}/.oci-iam-data-grants.instance"
WORK_DIR="${SCRIPT_DIR}/.oci-iam-setup"
source "${SCRIPT_DIR}/lib_lab_instance.sh"

OCI_IAM_LAB_INSTANCE_ID=$(make_lab_instance_id "dbsec-lab-machine" "$INSTANCE_FILE" "OCI_IAM_LAB_INSTANCE_ID")
export OCI_IAM_LAB_INSTANCE_ID
OCI_IAM_LAB_INSTANCE_SHORT=$(short_lab_instance_id "$OCI_IAM_LAB_INSTANCE_ID" 6)
export OCI_IAM_LAB_INSTANCE_SHORT

export DB_SID="${DB_SID:-FREE}"
export PDB_NAME="${PDB_NAME:-FREEPDB1}"
export OCI_DOMAIN_NAME="${OCI_DOMAIN_NAME:-Default}"
legacy_oci_db_app_name="Oracle DB"
legacy_oci_client_app_name="Oracle Confidential Client"
if [ -z "${OCI_DB_APP_NAME:-}" ] || [ "$OCI_DB_APP_NAME" = "$legacy_oci_db_app_name" ]; then
  OCI_DB_APP_NAME="Oracle DB - ${PDB_NAME:-FREEPDB1} - ${OCI_IAM_LAB_INSTANCE_ID}"
fi
if [ -z "${OCI_CLIENT_APP_NAME:-}" ] || [ "$OCI_CLIENT_APP_NAME" = "$legacy_oci_client_app_name" ]; then
  OCI_CLIENT_APP_NAME="Oracle Confidential Client - ${PDB_NAME:-FREEPDB1} - ${OCI_IAM_LAB_INSTANCE_ID}"
fi
export OCI_DB_APP_NAME
export OCI_CLIENT_APP_NAME
if [ -z "${OCI_DB_AUDIENCE:-}" ] || [ "$OCI_DB_AUDIENCE" = "OracleDB" ]; then
  OCI_DB_AUDIENCE="OracleDB-${PDB_NAME:-FREEPDB1}-${OCI_IAM_LAB_INSTANCE_SHORT}"
fi
if [ -z "${OCI_DB_SCOPE_VALUE:-}" ] || [ "$OCI_DB_SCOPE_VALUE" = "DB_ACCESS_SCOPE" ]; then
  OCI_DB_SCOPE_VALUE="DB_ACCESS_SCOPE_${OCI_IAM_LAB_INSTANCE_SHORT}"
fi
export OCI_DB_AUDIENCE
export OCI_DB_SCOPE_VALUE
export OCI_SCOPE="${OCI_SCOPE:-${OCI_DB_AUDIENCE}${OCI_DB_SCOPE_VALUE}}"
DEFAULT_REDIRECT_URIS="http://localhost:8888/callback,http://localhost:8889/callback,http://localhost:8890/callback,http://127.0.0.1:8888/callback,http://127.0.0.1:8889/callback,http://127.0.0.1:8890/callback"
export OCI_REDIRECT_URI="${OCI_REDIRECT_URI:-http://localhost:8888/callback}"
export OCI_REDIRECT_URIS="${OCI_REDIRECT_URIS:-$DEFAULT_REDIRECT_URIS}"
export OCI_USERNAME_DOMAIN="${OCI_USERNAME_DOMAIN:-}"
export MARVIN_USERNAME="${MARVIN_USERNAME:-marvin}"
export EMMA_USERNAME="${EMMA_USERNAME:-emma}"
export CREATE_DEMO_USERS="${CREATE_DEMO_USERS:-1}"

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

normalize_redirect_uri

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 0: Create OCI IAM Objects for the Data Grants Lab                ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

if ! command -v oci >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI is not installed or not on PATH.${NC}"
  echo -e "${YELLOW}Install OCI CLI and run: oci setup config${NC}"
  exit 1
fi

mkdir -p "$WORK_DIR"

oci_global_args=()
[ -n "${OCI_CONFIG_FILE:-}" ] && oci_global_args+=(--config-file "$OCI_CONFIG_FILE")
[ -n "${OCI_PROFILE:-}" ] && oci_global_args+=(--profile "$OCI_PROFILE")

config_value() {
  local key="$1"
  local profile="${OCI_PROFILE:-DEFAULT}"
  local config="${OCI_CONFIG_FILE:-$HOME/.oci/config}"
  awk -F= -v profile="$profile" -v key="$key" '
    $0 == "[" profile "]" { in_profile=1; next }
    /^\[/ { in_profile=0 }
    in_profile && $1 == key {
      gsub(/^[ \t]+|[ \t]+$/, "", $2)
      print $2
      exit
    }
  ' "$config" 2>/dev/null
}

discover_domain_url() {
  if [ -n "${OCI_DOMAIN_URL:-}" ]; then
    printf '%s' "$OCI_DOMAIN_URL"
    return
  fi

  local tenancy
  tenancy=$(config_value tenancy)
  if [ -z "$tenancy" ]; then
    echo -e "${RED}ERROR: Could not find tenancy in OCI CLI config.${NC}" >&2
    echo -e "${YELLOW}Run oci setup config, or export OCI_DOMAIN_URL manually.${NC}" >&2
    exit 1
  fi

  local url
  url=$(oci iam domain list \
    --compartment-id "$tenancy" \
    --all \
    "${oci_global_args[@]}" \
    --query "data[?lifecycleState==\`ACTIVE\` && displayName==\`${OCI_DOMAIN_NAME}\`].url | [0]" \
    --raw-output)

  if [ -z "$url" ] || [ "$url" = "null" ] || [ "$url" = "None" ]; then
    url=$(oci iam domain list \
      --compartment-id "$tenancy" \
      --all \
      "${oci_global_args[@]}" \
      --query 'data[?lifecycleState==`ACTIVE`].url | [0]' \
      --raw-output)
  fi

  if [ -z "$url" ] || [ "$url" = "null" ] || [ "$url" = "None" ]; then
    echo -e "${RED}ERROR: Could not discover an active OCI IAM domain URL.${NC}" >&2
    echo -e "${YELLOW}Export OCI_DOMAIN_URL from Console -> Identity & Security -> Domains -> Overview.${NC}" >&2
    exit 1
  fi

  printf '%s' "$url"
}

export OCI_DOMAIN_URL
OCI_DOMAIN_URL=$(discover_domain_url)

domain_cmd() {
  oci identity-domains "$@" --endpoint "$OCI_DOMAIN_URL" "${oci_global_args[@]}"
}

raw_request() {
  oci raw-request "$@" "${oci_global_args[@]}"
}

generate_secret() {
  local secret
  secret=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48 || true)
  printf '%s' "$secret"
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

find_app_id() {
  local name="$1"
  first_query \
    "domain_cmd apps list --all --attribute-sets all --filter 'displayName eq \"${name}\"'" \
    'data.Resources[0].id' \
    'data.resources[0].id'
}

find_group_id() {
  local name="$1"
  first_query \
    "domain_cmd groups list --all --filter 'displayName eq \"${name}\"'" \
    'data.Resources[0].id' \
    'data.resources[0].id'
}

find_user_id() {
  local name="$1"
  first_query \
    "domain_cmd users list --all --filter 'userName eq \"${name}\"'" \
    'data.Resources[0].id' \
    'data.resources[0].id'
}

get_app_field() {
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

set_app_client_secret() {
  local app_id="$1"
  local secret="$2"

  domain_cmd app patch \
    --app-id "$app_id" \
    --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
    --operations "[{\"op\":\"replace\",\"path\":\"clientSecret\",\"value\":\"${secret}\"}]" \
    >/dev/null
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

configure_oauth_client_app() {
  local app_id="$1"
  local db_scope="$2"
  local redirect_json
  redirect_json=$(REDIRECT_URIS="$OCI_REDIRECT_URIS" python3 - <<'PY'
import json
import os

uris = [uri.strip() for uri in os.environ["REDIRECT_URIS"].split(",") if uri.strip()]
print(json.dumps(uris))
PY
)

  domain_cmd app patch \
    --app-id "$app_id" \
    --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
    --operations "[{\"op\":\"replace\",\"path\":\"allowedGrants\",\"value\":[\"authorization_code\",\"client_credentials\",\"urn:ietf:params:oauth:grant-type:device_code\"]},{\"op\":\"replace\",\"path\":\"redirectUris\",\"value\":${redirect_json}},{\"op\":\"replace\",\"path\":\"allowedScopes\",\"value\":[{\"fqs\":\"${db_scope}\"}]}]" \
    >/dev/null
}

create_or_reuse_db_app() {
  local app_id
  local generated_secret
  app_id=$(find_app_id "$OCI_DB_APP_NAME")
  if [ -n "$app_id" ]; then
    echo -e "${CYAN}  Reusing DB app: ${app_id}${NC}" >&2
  else
    generated_secret=$(generate_secret)
    app_id=$(domain_cmd app create \
      --schemas '["urn:ietf:params:scim:schemas:oracle:idcs:App"]' \
      --based-on-template '{"value":"CustomWebAppTemplateId","wellKnownId":"CustomWebAppTemplateId"}' \
      --display-name "$OCI_DB_APP_NAME" \
      --description "Database resource app for Oracle Deep Data Security lab" \
      --active true \
      --is-o-auth-client true \
      --is-o-auth-resource true \
      --client-type confidential \
      --client-secret "$generated_secret" \
      --audience "$OCI_DB_AUDIENCE" \
      --scopes "[{\"value\":\"${OCI_DB_SCOPE_VALUE}\",\"displayName\":\"DB Access\",\"description\":\"Access the DB\",\"requiresConsent\":false}]" \
      --allowed-grants '["client_credentials"]' \
      --bypass-consent true \
      --attribute-sets all \
      --query 'data.id' \
      --raw-output)
    DB_APP_CLIENT_SECRET_OVERRIDE="$generated_secret"
    echo -e "${CYAN}  Created DB app: ${app_id}${NC}" >&2
  fi
  printf '%s' "$app_id"
}

create_or_reuse_client_app() {
  local app_id="$1"
  local db_scope="$2"
  local generated_secret
  local client_id
  client_id=$(find_app_id "$OCI_CLIENT_APP_NAME")
  if [ -n "$client_id" ]; then
    echo -e "${CYAN}  Reusing client app: ${client_id}${NC}" >&2
  else
    generated_secret=$(generate_secret)
    client_id=$(domain_cmd app create \
      --schemas '["urn:ietf:params:scim:schemas:oracle:idcs:App"]' \
      --based-on-template '{"value":"CustomWebAppTemplateId","wellKnownId":"CustomWebAppTemplateId"}' \
      --display-name "$OCI_CLIENT_APP_NAME" \
      --description "Interactive client app for Oracle Deep Data Security lab" \
      --active true \
      --is-o-auth-client true \
      --client-type confidential \
      --client-secret "$generated_secret" \
      --allowed-grants '["authorization_code","client_credentials","urn:ietf:params:oauth:grant-type:device_code"]' \
      --allowed-scopes "[{\"fqs\":\"${db_scope}\"}]" \
      --redirect-uris "$(REDIRECT_URIS="$OCI_REDIRECT_URIS" python3 - <<'PY'
import json
import os

uris = [uri.strip() for uri in os.environ["REDIRECT_URIS"].split(",") if uri.strip()]
print(json.dumps(uris))
PY
)" \
      --all-url-schemes-allowed true \
      --attribute-sets all \
      --query 'data.id' \
      --raw-output)
    CLIENT_APP_SECRET_OVERRIDE="$generated_secret"
    echo -e "${CYAN}  Created client app: ${client_id}${NC}" >&2
  fi
  printf '%s' "$client_id"
}

create_or_reuse_group() {
  local name="$1"
  local group_id
  group_id=$(find_group_id "$name")
  if [ -n "$group_id" ]; then
    echo -e "${CYAN}  Reusing group ${name}: ${group_id}${NC}" >&2
  else
    group_id=$(domain_cmd group create \
      --schemas '["urn:ietf:params:scim:schemas:core:2.0:Group"]' \
      --display-name "$name" \
      --query 'data.id' \
      --raw-output)
    echo -e "${CYAN}  Created group ${name}: ${group_id}${NC}" >&2
  fi
  printf '%s' "$group_id"
}

create_or_reuse_user() {
  local username="$1"
  local given="$2"
  local family="$3"
  local email="${username}"
  local user_id

  if [[ "$email" != *@* ]]; then
    if [ -n "$OCI_USERNAME_DOMAIN" ]; then
      email="${username}@${OCI_USERNAME_DOMAIN}"
    else
      email="${username}@example.com"
    fi
  fi

  user_id=$(find_user_id "$username")
  if [ -n "$user_id" ]; then
    echo -e "${CYAN}  Reusing user ${username}: ${user_id}${NC}" >&2
  else
    if ! user_id=$(domain_cmd user create \
      --schemas '["urn:ietf:params:scim:schemas:core:2.0:User"]' \
      --user-name "$username" \
      --name "{\"givenName\":\"${given}\",\"familyName\":\"${family}\"}" \
      --emails "[{\"value\":\"${email}\",\"primary\":true,\"type\":\"work\"}]" \
      --active true \
      --query 'data.id' \
      --raw-output 2>/dev/null); then
      echo -e "${RED}ERROR: Could not create user ${username}.${NC}" >&2
      echo -e "${YELLOW}  Check that the username and generated email are valid: ${email}${NC}" >&2
      exit 1
    fi

    if [ -z "$user_id" ] || [ "$user_id" = "null" ] || [ "$user_id" = "None" ]; then
      echo -e "${RED}ERROR: OCI IAM did not return an id for created user ${username}.${NC}" >&2
      exit 1
    fi

    echo -e "${CYAN}  Created user ${username}: ${user_id}${NC}" >&2
    echo -e "${YELLOW}  Set or reset this user's password/federated login before verification.${NC}" >&2
  fi
  printf '%s' "$user_id"
}

add_user_to_group() {
  local user_id="$1"
  local group_id="$2"
  local username="$3"
  local group="$4"
  if domain_cmd group patch \
    --group-id "$group_id" \
    --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
    --operations "[{\"op\":\"add\",\"path\":\"members\",\"value\":[{\"value\":\"${user_id}\",\"type\":\"User\"}]}]" \
    >/dev/null 2>&1; then
    echo -e "${CYAN}  Ensured ${username} is in ${group}${NC}"
  else
    echo -e "${RED}ERROR: Could not add ${username} to ${group}.${NC}"
    echo -e "${YELLOW}  User id: ${user_id}${NC}"
    echo -e "${YELLOW}  Group id: ${group_id}${NC}"
    exit 1
  fi
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

echo -e "${PURPLE}Using OCI IAM domain:${NC}"
echo -e "${CYAN}  OCI_DOMAIN_URL = ${OCI_DOMAIN_URL}${NC}"
echo -e "${CYAN}  OCI_DOMAIN_NAME = ${OCI_DOMAIN_NAME}${NC}"
echo -e "${CYAN}  OCI_PROFILE    = ${OCI_PROFILE:-DEFAULT}${NC}"
echo -e "${CYAN}  LAB_INSTANCE_ID = ${OCI_IAM_LAB_INSTANCE_ID}${NC}"
echo -e "${CYAN}  DB app          = ${OCI_DB_APP_NAME}${NC}"
echo -e "${CYAN}  Client app      = ${OCI_CLIENT_APP_NAME}${NC}"
echo -e "${CYAN}  Audience        = ${OCI_DB_AUDIENCE}${NC}"
echo -e "${CYAN}  Scope           = ${OCI_SCOPE}${NC}"
echo

echo -e "${YELLOW}Step 1: Creating or reusing DB resource app...${NC}"
DB_APP_CLIENT_SECRET_OVERRIDE=""
DB_APP_ID=$(create_or_reuse_db_app)
DB_APP_CLIENT_ID=$(get_app_field "$DB_APP_ID" client_id)
DB_APP_CLIENT_SECRET="${DB_APP_CLIENT_SECRET_OVERRIDE}"
if [ -z "$DB_APP_CLIENT_SECRET" ]; then
  DB_APP_CLIENT_SECRET=$(get_app_field "$DB_APP_ID" client_secret)
fi
if [ -z "$DB_APP_CLIENT_SECRET" ]; then
  echo -e "${YELLOW}  Existing DB app did not return a readable client secret. Resetting it automatically...${NC}"
  DB_APP_CLIENT_SECRET=$(regenerate_app_client_secret "$DB_APP_ID")
  if [ -z "$DB_APP_CLIENT_SECRET" ]; then
    echo -e "${RED}ERROR: Could not set a client secret on existing DB app ${DB_APP_ID}.${NC}"
    echo -e "${YELLOW}Delete the existing '${OCI_DB_APP_NAME}' app in OCI IAM, or regenerate its client secret manually.${NC}"
    exit 1
  fi
fi

echo
echo -e "${YELLOW}Step 2: Creating or reusing interactive client app...${NC}"
CLIENT_APP_SECRET_OVERRIDE=""
CLIENT_APP_ID=$(create_or_reuse_client_app "$DB_APP_ID" "$OCI_SCOPE")
configure_oauth_client_app "$CLIENT_APP_ID" "$OCI_SCOPE"
OCI_CLIENT_ID=$(get_app_field "$CLIENT_APP_ID" client_id)
echo -e "${CYAN}  Resetting client app secret for OAuth token exchange...${NC}"
OCI_CLIENT_SECRET=$(regenerate_app_client_secret "$CLIENT_APP_ID")
if [ -z "$OCI_CLIENT_SECRET" ]; then
  echo -e "${RED}ERROR: Could not regenerate client secret for existing client app ${CLIENT_APP_ID}.${NC}"
  echo -e "${YELLOW}Delete the existing '${OCI_CLIENT_APP_NAME}' app in OCI IAM, or regenerate its client secret manually.${NC}"
  exit 1
fi

if [ -z "$DB_APP_CLIENT_ID" ]; then
  echo -e "${RED}ERROR: Could not determine DB app OAuth Client ID for app ${DB_APP_ID}.${NC}"
  echo -e "${YELLOW}Run this to inspect returned fields:${NC}"
  echo -e "${CYAN}  oci identity-domains app get --endpoint '${OCI_DOMAIN_URL}' --app-id '${DB_APP_ID}' --attribute-sets all${NC}"
  exit 1
fi

if [ -z "$OCI_CLIENT_ID" ]; then
  echo -e "${RED}ERROR: Could not determine interactive client app OAuth Client ID for app ${CLIENT_APP_ID}.${NC}"
  echo -e "${YELLOW}Run this to inspect returned fields:${NC}"
  echo -e "${CYAN}  oci identity-domains app get --endpoint '${OCI_DOMAIN_URL}' --app-id '${CLIENT_APP_ID}' --attribute-sets all${NC}"
  exit 1
fi

echo
echo -e "${YELLOW}Step 3: Creating or reusing IAM groups...${NC}"
EMPLOYEES_GROUP_ID=$(create_or_reuse_group "EMPLOYEES")
MANAGERS_GROUP_ID=$(create_or_reuse_group "MANAGERS")

if [ "$CREATE_DEMO_USERS" = "1" ]; then
  echo
  echo -e "${YELLOW}Step 4: Creating or reusing demo users and group membership...${NC}"
  MARVIN_ID=$(create_or_reuse_user "$MARVIN_USERNAME" "Marvin" "Morgan")
  EMMA_ID=$(create_or_reuse_user "$EMMA_USERNAME" "Emma" "Baker")
  add_user_to_group "$MARVIN_ID" "$EMPLOYEES_GROUP_ID" "$MARVIN_USERNAME" "EMPLOYEES"
  add_user_to_group "$MARVIN_ID" "$MANAGERS_GROUP_ID" "$MARVIN_USERNAME" "MANAGERS"
  add_user_to_group "$EMMA_ID" "$EMPLOYEES_GROUP_ID" "$EMMA_USERNAME" "EMPLOYEES"
fi

echo
echo -e "${YELLOW}Step 5: Creating group custom claim for access tokens...${NC}"
create_group_claim

cat > "$ENV_FILE" <<EOF
export OCI_DB_APP_ID='${DB_APP_ID}'
export OCI_DB_CLIENT_ID='${DB_APP_CLIENT_ID}'
export OCI_DB_CLIENT_SECRET='${DB_APP_CLIENT_SECRET}'
export OCI_DOMAIN_URL='${OCI_DOMAIN_URL}'
export OCI_CLIENT_ID='${OCI_CLIENT_ID}'
export OCI_CLIENT_SECRET='${OCI_CLIENT_SECRET}'
export OCI_AUDIENCE='${OCI_DB_AUDIENCE}'
export OCI_SCOPE='${OCI_SCOPE}'
export OCI_REDIRECT_URI='${OCI_REDIRECT_URI}'
export OCI_REDIRECT_URIS='${OCI_REDIRECT_URIS}'
export OCI_USERNAME_DOMAIN='${OCI_USERNAME_DOMAIN}'
export OCI_IAM_LAB_INSTANCE_ID='${OCI_IAM_LAB_INSTANCE_ID}'
export OCI_DB_APP_NAME='${OCI_DB_APP_NAME}'
export OCI_CLIENT_APP_NAME='${OCI_CLIENT_APP_NAME}'
export DB_SID='${DB_SID}'
export PDB_NAME='${PDB_NAME}'
EOF
chmod 600 "$ENV_FILE"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 0 Completed: OCI IAM Objects Ready                               ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}Environment file:${NC} ${ENV_FILE}"
echo -e "${YELLOW}Load it before continuing:${NC}"
echo -e "${CYAN}  source ./.oci-iam-data-grants.env${NC}"
echo
