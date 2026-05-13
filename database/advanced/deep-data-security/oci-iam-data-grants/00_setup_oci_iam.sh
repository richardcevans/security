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
WORK_DIR="${SCRIPT_DIR}/.oci-iam-setup"

export OCI_DB_APP_NAME="${OCI_DB_APP_NAME:-Oracle DB}"
export OCI_CLIENT_APP_NAME="${OCI_CLIENT_APP_NAME:-Oracle Confidential Client}"
export OCI_DOMAIN_NAME="${OCI_DOMAIN_NAME:-Default}"
export OCI_DB_AUDIENCE="${OCI_DB_AUDIENCE:-OracleDB}"
export OCI_DB_SCOPE_VALUE="${OCI_DB_SCOPE_VALUE:-DB_ACCESS_SCOPE}"
export OCI_SCOPE="${OCI_SCOPE:-${OCI_DB_AUDIENCE}${OCI_DB_SCOPE_VALUE}}"
export OCI_USERNAME_DOMAIN="${OCI_USERNAME_DOMAIN:-}"
export MARVIN_USERNAME="${MARVIN_USERNAME:-marvin}"
export EMMA_USERNAME="${EMMA_USERNAME:-emma}"
export CREATE_DEMO_USERS="${CREATE_DEMO_USERS:-1}"
export PDB_NAME="${PDB_NAME:-pdb1}"

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
  LC_ALL=C tr -dc 'A-Za-z0-9_@#%+=:,.~-' </dev/urandom | head -c 48
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
  local q1="$2"
  local q2="$3"
  first_query "domain_cmd app get --app-id '$app_id' --attribute-sets all" "$q1" "$q2"
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
  local client_id
  client_id=$(find_app_id "$OCI_CLIENT_APP_NAME")
  if [ -n "$client_id" ]; then
    echo -e "${CYAN}  Reusing client app: ${client_id}${NC}" >&2
  else
    client_id=$(domain_cmd app create \
      --schemas '["urn:ietf:params:scim:schemas:oracle:idcs:App"]' \
      --based-on-template '{"value":"CustomWebAppTemplateId","wellKnownId":"CustomWebAppTemplateId"}' \
      --display-name "$OCI_CLIENT_APP_NAME" \
      --description "Interactive client app for Oracle Deep Data Security lab" \
      --active true \
      --is-o-auth-client true \
      --client-type confidential \
      --allowed-grants '["client_credentials","password","urn:ietf:params:oauth:grant-type:device_code"]' \
      --allowed-scopes "[{\"fqs\":\"${db_scope}\"}]" \
      --all-url-schemes-allowed true \
      --attribute-sets all \
      --query 'data.id' \
      --raw-output)
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

  if [[ "$email" != *@* ]] && [ -n "$OCI_USERNAME_DOMAIN" ]; then
    email="${username}@${OCI_USERNAME_DOMAIN}"
  fi

  user_id=$(find_user_id "$username")
  if [ -n "$user_id" ]; then
    echo -e "${CYAN}  Reusing user ${username}: ${user_id}${NC}" >&2
  else
    user_id=$(domain_cmd user create \
      --schemas '["urn:ietf:params:scim:schemas:core:2.0:User"]' \
      --user-name "$username" \
      --name "{\"givenName\":\"${given}\",\"familyName\":\"${family}\"}" \
      --emails "[{\"value\":\"${email}\",\"primary\":true,\"type\":\"work\"}]" \
      --active true \
      --query 'data.id' \
      --raw-output)
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
  domain_cmd group patch \
    --group-id "$group_id" \
    --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
    --operations "[{\"op\":\"add\",\"path\":\"members\",\"value\":[{\"value\":\"${user_id}\",\"type\":\"User\"}]}]" \
    >/dev/null || true
  echo -e "${CYAN}  Ensured ${username} is in ${group}${NC}"
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
echo

echo -e "${YELLOW}Step 1: Creating or reusing DB resource app...${NC}"
DB_APP_CLIENT_SECRET_OVERRIDE=""
DB_APP_ID=$(create_or_reuse_db_app)
DB_APP_CLIENT_ID=$(get_app_field "$DB_APP_ID" 'data.clientId' 'data.client_id')
DB_APP_CLIENT_SECRET="${DB_APP_CLIENT_SECRET_OVERRIDE}"
if [ -z "$DB_APP_CLIENT_SECRET" ]; then
  DB_APP_CLIENT_SECRET=$(get_app_field "$DB_APP_ID" 'data.clientSecret' 'data.client_secret')
fi
if [ -z "$DB_APP_CLIENT_SECRET" ]; then
  echo -e "${YELLOW}  Existing DB app did not return a readable client secret. Resetting it automatically...${NC}"
  DB_APP_CLIENT_SECRET=$(generate_secret)
  if ! set_app_client_secret "$DB_APP_ID" "$DB_APP_CLIENT_SECRET"; then
    echo -e "${RED}ERROR: Could not set a client secret on existing DB app ${DB_APP_ID}.${NC}"
    echo -e "${YELLOW}Delete the existing '${OCI_DB_APP_NAME}' app in OCI IAM, or set its client secret manually and export OCI_DB_CLIENT_SECRET.${NC}"
    exit 1
  fi
fi

echo
echo -e "${YELLOW}Step 2: Creating or reusing interactive client app...${NC}"
CLIENT_APP_ID=$(create_or_reuse_client_app "$DB_APP_ID" "$OCI_SCOPE")
OCI_CLIENT_ID=$(get_app_field "$CLIENT_APP_ID" 'data.clientId' 'data.client_id')

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
export OCI_DB_APP_ID='${DB_APP_CLIENT_ID}'
export OCI_DB_CLIENT_ID='${DB_APP_CLIENT_ID}'
export OCI_DB_CLIENT_SECRET='${DB_APP_CLIENT_SECRET}'
export OCI_DOMAIN_URL='${OCI_DOMAIN_URL}'
export OCI_CLIENT_ID='${OCI_CLIENT_ID}'
export OCI_AUDIENCE='${OCI_DB_AUDIENCE}'
export OCI_SCOPE='${OCI_SCOPE}'
export OCI_USERNAME_DOMAIN='${OCI_USERNAME_DOMAIN}'
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
