#!/bin/bash
# Verify the OCI IAM apps, groups, users, and memberships used by the lab.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ -z "${OCI_DOMAIN_URL:-}" ] && [ -f "${SCRIPT_DIR}/.oci-iam-data-grants.env" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.oci-iam-data-grants.env"
fi

export OCI_DB_APP_NAME="${OCI_DB_APP_NAME:-Oracle DB}"
export OCI_CLIENT_APP_NAME="${OCI_CLIENT_APP_NAME:-Oracle Confidential Client}"
export MARVIN_USERNAME="${MARVIN_USERNAME:-marvin}"
export EMMA_USERNAME="${EMMA_USERNAME:-emma}"

if [ -z "${OCI_DOMAIN_URL:-}" ]; then
  echo -e "${RED}ERROR: OCI_DOMAIN_URL is not set.${NC}" >&2
  echo -e "${YELLOW}Run ./00_setup_oci_iam.sh and source ./.oci-iam-data-grants.env first.${NC}" >&2
  exit 1
fi

oci_global_args=()
[ -n "${OCI_CONFIG_FILE:-}" ] && oci_global_args+=(--config-file "$OCI_CONFIG_FILE")
[ -n "${OCI_PROFILE:-}" ] && oci_global_args+=(--profile "$OCI_PROFILE")

domain_cmd() {
  oci identity-domains "$@" --endpoint "$OCI_DOMAIN_URL" "${oci_global_args[@]}"
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
  local username="$1"
  first_query \
    "domain_cmd users list --all --filter 'userName eq \"${username}\"'" \
    'data.Resources[0].id' \
    'data.resources[0].id'
}

check_member() {
  local username="$1"
  local user_id="$2"
  local group="$3"
  local group_id="$4"
  local found
  local response
  response=$(domain_cmd group get --group-id "$group_id" --attribute-sets all 2>/dev/null || true)
  found=$(GROUP_RESPONSE="$response" USER_ID="$user_id" python3 - <<'PY'
import json
import os
import sys

try:
    raw = json.loads(os.environ.get("GROUP_RESPONSE", "{}"))
except Exception:
    sys.exit(1)

data = raw.get("data") or {}
members = data.get("members") or data.get("Members") or []
user_id = os.environ["USER_ID"]
print("yes" if any(member.get("value") == user_id for member in members) else "no")
PY
)

  if [ "$found" = "yes" ]; then
    echo -e "${CYAN}  OK: ${username} is in ${group}${NC}"
  else
    echo -e "${RED}  MISSING: ${username} is not in ${group}${NC}"
    return 1
  fi
}

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Verify OCI IAM Setup for Data Grants                                  ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}Using OCI IAM domain:${NC}"
echo -e "${CYAN}  OCI_DOMAIN_URL = ${OCI_DOMAIN_URL}${NC}"
echo

status=0

for app in "$OCI_DB_APP_NAME" "$OCI_CLIENT_APP_NAME"; do
  id=$(find_app_id "$app")
  if [ -n "$id" ]; then
    echo -e "${CYAN}  OK: app ${app}: ${id}${NC}"
  else
    echo -e "${RED}  MISSING: app ${app}${NC}"
    status=1
  fi
done

EMPLOYEES_ID=$(find_group_id "EMPLOYEES")
MANAGERS_ID=$(find_group_id "MANAGERS")
MARVIN_ID=$(find_user_id "$MARVIN_USERNAME")
EMMA_ID=$(find_user_id "$EMMA_USERNAME")

[ -n "$EMPLOYEES_ID" ] && echo -e "${CYAN}  OK: group EMPLOYEES: ${EMPLOYEES_ID}${NC}" || { echo -e "${RED}  MISSING: group EMPLOYEES${NC}"; status=1; }
[ -n "$MANAGERS_ID" ] && echo -e "${CYAN}  OK: group MANAGERS: ${MANAGERS_ID}${NC}" || { echo -e "${RED}  MISSING: group MANAGERS${NC}"; status=1; }
[ -n "$MARVIN_ID" ] && echo -e "${CYAN}  OK: user ${MARVIN_USERNAME}: ${MARVIN_ID}${NC}" || { echo -e "${RED}  MISSING: user ${MARVIN_USERNAME}${NC}"; status=1; }
[ -n "$EMMA_ID" ] && echo -e "${CYAN}  OK: user ${EMMA_USERNAME}: ${EMMA_ID}${NC}" || { echo -e "${RED}  MISSING: user ${EMMA_USERNAME}${NC}"; status=1; }

if [ -n "$MARVIN_ID" ] && [ -n "$EMPLOYEES_ID" ]; then
  check_member "$MARVIN_USERNAME" "$MARVIN_ID" "EMPLOYEES" "$EMPLOYEES_ID" || status=1
fi
if [ -n "$MARVIN_ID" ] && [ -n "$MANAGERS_ID" ]; then
  check_member "$MARVIN_USERNAME" "$MARVIN_ID" "MANAGERS" "$MANAGERS_ID" || status=1
fi
if [ -n "$EMMA_ID" ] && [ -n "$EMPLOYEES_ID" ]; then
  check_member "$EMMA_USERNAME" "$EMMA_ID" "EMPLOYEES" "$EMPLOYEES_ID" || status=1
fi

echo
if [ "$status" -eq 0 ]; then
  echo -e "${GREEN}OCI IAM setup looks correct for the lab.${NC}"
else
  echo -e "${RED}OCI IAM setup has missing objects or memberships.${NC}"
fi
echo

exit "$status"
