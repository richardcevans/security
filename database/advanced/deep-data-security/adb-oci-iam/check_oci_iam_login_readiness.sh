#!/bin/bash
# Read-only OCI IAM login-readiness diagnostic for the ADB OCI IAM lab.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat <<'EOF'
Usage: ./check_oci_iam_login_readiness.sh

Read-only diagnostic that uses the administrator OCI CLI profile to check:
  * whether Marvin and Emma exist and are active;
  * their expected EMPLOYEES / MANAGERS group memberships;
  * the identity domain's sign-on policies and MFA settings.

It does not change users, passwords, groups, applications, or policies.

Environment:
  OCI_DOMAIN_URL      Required; normally loaded from .adb-oci-iam.env.
  OCI_PROFILE         Optional OCI CLI profile used for the administrator.
  OCI_CONFIG_FILE     Optional OCI CLI config file.
  MARVIN_USERNAME     Default: marvin
  EMMA_USERNAME       Default: emma
  OCI_IAM_EMPLOYEE_GROUP  Default: EMPLOYEES
  OCI_IAM_MANAGER_GROUP   Default: MANAGERS

An OCI CLI profile authenticates the administrator running this check; it does
not authenticate as Marvin or Emma. To prove an end-user login works, run
./04_get_iam_oauth_token.sh afterwards and sign in as each user in a private
browser window.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') ;;
  *) echo -e "${RED}ERROR: Unknown option: $1${NC}" >&2; usage >&2; exit 1 ;;
esac

if [ -z "${OCI_DOMAIN_URL:-}" ] && [ -f "${SCRIPT_DIR}/.adb-oci-iam.env" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.adb-oci-iam.env"
fi

if [ -z "${OCI_DOMAIN_URL:-}" ]; then
  echo -e "${RED}ERROR: OCI_DOMAIN_URL is not set.${NC}" >&2
  echo -e "${YELLOW}Run ./00_setup_adb.sh and source ./.adb-oci-iam.env first.${NC}" >&2
  exit 1
fi

if ! command -v oci >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI is not installed or not on PATH.${NC}" >&2
  exit 1
fi

oci_global_args=()
[ -n "${OCI_CONFIG_FILE:-}" ] && oci_global_args+=(--config-file "$OCI_CONFIG_FILE")
[ -n "${OCI_PROFILE:-}" ] && oci_global_args+=(--profile "$OCI_PROFILE")

domain_cmd() {
  oci identity-domains "$@" --endpoint "$OCI_DOMAIN_URL" "${oci_global_args[@]}"
}

MARVIN_USERNAME="${MARVIN_USERNAME:-marvin}"
EMMA_USERNAME="${EMMA_USERNAME:-emma}"
OCI_IAM_EMPLOYEE_GROUP="${OCI_IAM_EMPLOYEE_GROUP:-EMPLOYEES}"
OCI_IAM_MANAGER_GROUP="${OCI_IAM_MANAGER_GROUP:-MANAGERS}"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

get_user() {
  local username="$1"
  domain_cmd users list --all --attribute-sets all \
    --filter "userName eq \"${username}\"" >"${TMP_DIR}/user-${username}.json"
}

get_user_groups() {
  local username="$1"
  local user_id
  user_id=$(python3 - "${TMP_DIR}/user-${username}.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    value = json.load(f)
data = value.get("data", value)
items = data.get("Resources") or data.get("resources") or [] if isinstance(data, dict) else []
if items and items[0].get("id"):
    print(items[0]["id"])
PY
)
  [ -n "$user_id" ] || return 0
  # Filtering the Groups collection is reliable even when a group-list response
  # omits its members attribute.
  domain_cmd groups list --all --attribute-sets all \
    --filter "members[value eq \"${user_id}\"]" >"${TMP_DIR}/groups-${username}.json"
}

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      OCI IAM Demo User Login Readiness (read-only)                       ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo -e "${CYAN}OCI IAM domain: ${OCI_DOMAIN_URL}${NC}"
echo -e "${CYAN}OCI CLI profile: ${OCI_PROFILE:-DEFAULT}${NC}"
echo

echo -e "${YELLOW}Reading Marvin and Emma from the identity domain...${NC}"
get_user "$MARVIN_USERNAME"
get_user "$EMMA_USERNAME"

echo -e "${YELLOW}Reading demo-user memberships, sign-on policies, and MFA settings...${NC}"
get_user_groups "$MARVIN_USERNAME"
get_user_groups "$EMMA_USERNAME"
domain_cmd policy list --all --attribute-sets all >"${TMP_DIR}/policies.json"
domain_cmd rule list --all --attribute-sets all >"${TMP_DIR}/rules.json"
domain_cmd authentication-factor-settings list --all --attribute-sets all >"${TMP_DIR}/mfa.json"

python3 - "$TMP_DIR" "$MARVIN_USERNAME" "$EMMA_USERNAME" \
  "$OCI_IAM_EMPLOYEE_GROUP" "$OCI_IAM_MANAGER_GROUP" <<'PY'
import json
import os
import sys

tmp, marvin, emma, employees, managers = sys.argv[1:]

def load(name):
    with open(os.path.join(tmp, name), encoding="utf-8") as f:
        return json.load(f)

def resources(value):
    data = value.get("data", value)
    if isinstance(data, dict):
        return data.get("Resources") or data.get("resources") or []
    return data if isinstance(data, list) else []

def user(name):
    items = resources(load("user-" + name + ".json"))
    return items[0] if items else None

def memberships(name):
    try:
        result = resources(load("groups-" + name + ".json"))
    except FileNotFoundError:
        return []
    return sorted(
        (
            group.get("displayName")
            or group.get("display-name")
            or group.get("display_name")
            or group.get("name")
            or group.get("id")
            for group in result
        ),
        key=str.lower,
    )

print("\nDemo-user status")
all_ready = True
for name, expected in ((marvin, {employees, managers}), (emma, {employees})):
    item = user(name)
    if not item:
        print("- {}: NOT FOUND".format(name))
        all_ready = False
        continue
    active = item.get("active")
    found = set(memberships(name))
    missing = expected - found
    print("- {}: active={}; groups={}".format(name, active, ", ".join(sorted(found)) or "(none)"))
    if active is not True or missing:
        all_ready = False
        problems = []
        if active is not True:
            problems.append("user is not active")
        if missing:
            problems.append("missing " + ", ".join(sorted(missing)))
        print("  NOT READY: " + "; ".join(problems))

print("\nSign-on policies (full matching policy JSON)")
policies = resources(load("policies.json"))
matches = []
for policy in policies:
    text = json.dumps(policy, sort_keys=True).lower()
    if "sign-on" in text or "signin" in text or "signon" in text or "mfa" in text:
        matches.append(policy)
if matches:
    print(json.dumps(matches, indent=2, sort_keys=True))
else:
    print("No sign-on policy was identified by name/type. Inspect the raw CLI response with:")
    print("  oci identity-domains policy list --all --attribute-sets all --endpoint <OCI_DOMAIN_URL>")

print("\nSign-on rule resources (full JSON)")
# OCI returns policy rules through the separate Rules collection. The field
# names are intentionally left intact so the output matches OCI CLI output.
print(json.dumps(resources(load("rules.json")), indent=2, sort_keys=True))

print("\nMFA settings (full JSON)")
print(json.dumps(resources(load("mfa.json")), indent=2, sort_keys=True))

print("\nResult")
if all_ready:
    print("PASS: both demo users are active and have the lab's expected group memberships.")
else:
    print("FAIL: correct the demo-user status or memberships before requesting an OAuth token.")
print("This check cannot submit Marvin's or Emma's password: the OCI CLI profile is the administrator, not the demo user.")
print("For the end-to-end authentication test, run ./04_get_iam_oauth_token.sh and sign in as each user in a private browser window.")
print("If the browser says 'Login policy denied access', use the sign-on policy JSON above to identify the rule that excludes the user or group. MFA only helps when that rule permits the user and requires MFA.")
PY
