#!/bin/bash
# Clean up OCI IAM objects created by 00_setup_oci_iam.sh.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.oci-iam-data-grants.env"

export OCI_DB_APP_NAME="${OCI_DB_APP_NAME:-Oracle DB}"
export OCI_CLIENT_APP_NAME="${OCI_CLIENT_APP_NAME:-Oracle Confidential Client}"
export OCI_DOMAIN_NAME="${OCI_DOMAIN_NAME:-Default}"
export MARVIN_USERNAME="${MARVIN_USERNAME:-marvin}"
export EMMA_USERNAME="${EMMA_USERNAME:-emma}"
export DELETE_DEMO_USERS="${DELETE_DEMO_USERS:-1}"
export FORCE="${FORCE:-0}"

usage() {
  cat <<EOF
Usage: ./09_cleanup_oci_iam.sh [options]

Options:
  -f, --force, --DELETE   Skip the DELETE confirmation prompt
  -h, --help              Show this help

Environment:
  OCI_DOMAIN_URL          Optional identity domain URL
  OCI_DOMAIN_NAME         Domain display name, default: Default
  DELETE_DEMO_USERS       Delete marvin/emma users, default: 1
  FORCE                   Set to 1 to skip confirmation
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -f|--force|--DELETE)
      FORCE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo -e "${RED}ERROR: Unknown option: $1${NC}"
      usage
      exit 1
      ;;
  esac
  shift
done

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 9: Clean Up OCI IAM Lab Objects                                  ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

if ! command -v oci >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI is not installed or not on PATH.${NC}"
  exit 1
fi

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
    echo -e "${YELLOW}Set OCI_DOMAIN_URL or run from the directory containing .oci-iam-data-grants.env.${NC}" >&2
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

find_group_claim_id() {
  local response
  response=$(raw_request \
    --http-method GET \
    --target-uri "${OCI_DOMAIN_URL}/admin/v1/CustomClaims?filter=name%20eq%20%22group%22" \
    2>/dev/null || true)

  if [ -z "$response" ]; then
    return
  fi

  printf '%s' "$response" | python3 -c '
import json
import sys

try:
    raw = json.load(sys.stdin)
except Exception:
    sys.exit(0)

data = raw.get("data") or {}
resources = data.get("Resources") or data.get("resources") or []
if resources:
    print(resources[0].get("id", ""))
'
}

delete_app() {
  local name="$1"
  local app_id
  app_id=$(find_app_id "$name")
  if [ -z "$app_id" ]; then
    echo -e "${CYAN}  App not found: ${name}${NC}"
    return
  fi

  echo -e "${YELLOW}  Deactivating app ${name}: ${app_id}${NC}"
  domain_cmd app patch \
    --app-id "$app_id" \
    --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
    --operations '[{"op":"replace","path":"active","value":false}]' \
    >/dev/null 2>&1 || true

  echo -e "${YELLOW}  Deleting app ${name}: ${app_id}${NC}"
  if ! domain_cmd app delete --app-id "$app_id" --force >/dev/null 2>&1; then
    echo -e "${RED}  Could not delete app: ${name}${NC}"
  fi
}

delete_group() {
  local name="$1"
  local group_id
  group_id=$(find_group_id "$name")
  if [ -z "$group_id" ]; then
    echo -e "${CYAN}  Group not found: ${name}${NC}"
    return
  fi

  echo -e "${YELLOW}  Deleting group ${name}: ${group_id}${NC}"
  if ! domain_cmd group delete --group-id "$group_id" --force >/dev/null 2>&1; then
    echo -e "${RED}  Could not delete group: ${name}${NC}"
  fi
}

delete_user() {
  local name="$1"
  local user_id
  user_id=$(find_user_id "$name")
  if [ -z "$user_id" ]; then
    echo -e "${CYAN}  User not found: ${name}${NC}"
    return
  fi

  echo -e "${YELLOW}  Deleting user ${name}: ${user_id}${NC}"
  if ! domain_cmd user delete --user-id "$user_id" --force >/dev/null 2>&1; then
    echo -e "${RED}  Could not delete user: ${name}${NC}"
  fi
}

delete_group_claim() {
  local claim_id
  claim_id=$(find_group_claim_id)
  if [ -z "$claim_id" ]; then
    echo -e "${CYAN}  Custom claim not found: group${NC}"
    return
  fi

  echo -e "${YELLOW}  Deleting custom claim group: ${claim_id}${NC}"
  if ! raw_request \
    --http-method DELETE \
    --target-uri "${OCI_DOMAIN_URL}/admin/v1/CustomClaims/${claim_id}" \
    >/dev/null 2>&1; then
    echo -e "${RED}  Could not delete custom claim: group${NC}"
  fi
}

echo -e "${PURPLE}This will delete OCI IAM lab objects in:${NC}"
echo -e "${CYAN}  OCI_DOMAIN_URL      = ${OCI_DOMAIN_URL}${NC}"
echo -e "${CYAN}  OCI_DOMAIN_NAME     = ${OCI_DOMAIN_NAME}${NC}"
echo -e "${CYAN}  DB app              = ${OCI_DB_APP_NAME}${NC}"
echo -e "${CYAN}  Client app          = ${OCI_CLIENT_APP_NAME}${NC}"
echo -e "${CYAN}  Groups              = EMPLOYEES, MANAGERS${NC}"
echo -e "${CYAN}  Demo users          = ${MARVIN_USERNAME}, ${EMMA_USERNAME} (DELETE_DEMO_USERS=${DELETE_DEMO_USERS})${NC}"
echo -e "${CYAN}  Custom token claim  = group${NC}"
echo

if [ "$FORCE" != "1" ]; then
  read -r -p "Type DELETE to continue: " answer
  if [ "$answer" != "DELETE" ]; then
    echo -e "${YELLOW}Canceled.${NC}"
    exit 0
  fi
fi

delete_app "$OCI_CLIENT_APP_NAME"
delete_app "$OCI_DB_APP_NAME"
delete_group "MANAGERS"
delete_group "EMPLOYEES"

if [ "$DELETE_DEMO_USERS" = "1" ]; then
  delete_user "$MARVIN_USERNAME"
  delete_user "$EMMA_USERNAME"
fi

delete_group_claim

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 9 Completed: OCI IAM Lab Objects Removed                         ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
