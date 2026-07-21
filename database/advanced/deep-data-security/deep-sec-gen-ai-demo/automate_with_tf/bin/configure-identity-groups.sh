#!/usr/bin/env bash
# Create the two Identity Domain groups used by the database data-role demo.
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${script_dir}/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: ./bin/configure-identity-groups.sh [--identity-endpoint URL] [--user-name EMAIL]

Discovers the tenancy's active Oracle-SSO Identity Domain by default, creates
(or reuses) EMPLOYEES and MANAGERS, then adds the specified user to both.
Use --identity-endpoint only to override automatic discovery. Pass only the
Identity Domain host URL; the OCI CLI adds /admin/v1 itself.
USAGE
}

identity_endpoint=''
user_name='richard.c.evans@oracle.com'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity-endpoint) identity_endpoint=${2:-}; shift 2 ;;
    --user-name) user_name=${2:-}; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

require_command oci
require_command jq
mkdir -p "$LAB_STATE_DIR"
state_file="${LAB_STATE_DIR}/identity-groups.env"
previous_employees_group_id=''
previous_managers_group_id=''
previous_employees_group_created=0
previous_managers_group_created=0
if [[ -f "$state_file" ]]; then
  # shellcheck disable=SC1090 # Written only by this paired setup script.
  source "$state_file"
  previous_employees_group_id=${EMPLOYEES_GROUP_ID:-}
  previous_managers_group_id=${MANAGERS_GROUP_ID:-}
  previous_employees_group_created=${EMPLOYEES_GROUP_CREATED:-0}
  previous_managers_group_created=${MANAGERS_GROUP_CREATED:-0}
fi

discover_identity_endpoint() {
  local tenancy_ocid domains endpoint
  tenancy_ocid=${TENANCY_OCID:-}
  if [[ -z "$tenancy_ocid" && -f "${LAB_ROOT}/terraform/terraform.tfvars" ]]; then
    tenancy_ocid=$(awk -F'"' '/^[[:space:]]*tenancy_ocid[[:space:]]*=/ {print $2; exit}' "${LAB_ROOT}/terraform/terraform.tfvars")
  fi
  if [[ -z "$tenancy_ocid" ]]; then
    local oci_config_file profile
    oci_config_file=${OCI_CLI_CONFIG_FILE:-"${HOME}/.oci/config"}
    profile=${OCI_CLI_PROFILE:-DEFAULT}
    if [[ -r "$oci_config_file" ]]; then
      tenancy_ocid=$(awk -v profile="$profile" '
        /^\[/ { current = substr($0, 2, length($0) - 2); next }
        current == profile && /^[[:space:]]*tenancy[[:space:]]*=/ {
          sub(/^[^=]*=[[:space:]]*/, ""); print; exit
        }
      ' "$oci_config_file")
    fi
  fi
  [[ -n "$tenancy_ocid" ]] || die 'Could not determine the tenancy OCID from TENANCY_OCID, terraform/terraform.tfvars, or the OCI CLI config.'
  domains=$(oci iam domain list --compartment-id "$tenancy_ocid" --lifecycle-state ACTIVE --all)

  # Oracle-SSO is the enabled enterprise identity domain in this tenancy.
  # If a different tenancy has one active domain, select that instead.
  endpoint=$(jq -er '
    .data
    | map(select(.["display-name"] == "Oracle-SSO" and .["lifecycle-state"] == "ACTIVE"))
    | if length == 1 then .[0]["home-region-url"] else empty end
  ' <<<"$domains" 2>/dev/null || true)
  if [[ -z "$endpoint" ]]; then
    endpoint=$(jq -er '
      .data
      | map(select(.["lifecycle-state"] == "ACTIVE"))
      | if length == 1 then .[0]["home-region-url"] else empty end
    ' <<<"$domains" 2>/dev/null || true)
  fi
  [[ -n "$endpoint" && "$endpoint" != null ]] || die 'Could not select one active Identity Domain. Re-run with --identity-endpoint URL.'
  printf '%s\n' "${endpoint%/}"
}

if [[ -z "$identity_endpoint" ]]; then
  identity_endpoint=$(discover_identity_endpoint)
fi
[[ "$identity_endpoint" =~ ^https://[^/?#]+(:[0-9]+)?$ ]] || die 'Identity Domain endpoint must be only its HTTPS host URL, without /admin/v1.'

find_user_id() {
  local result
  result=$(oci identity-domains users list --endpoint "$identity_endpoint" --filter "userName eq \"${user_name}\"" --attributes 'id,userName' --all)
  jq -er '.data.resources | if length == 1 then .[0].id else empty end' <<<"$result"
}

find_group_id() {
  local group_name=$1 result
  result=$(oci identity-domains groups list --endpoint "$identity_endpoint" --filter "displayName eq \"${group_name}\"" --attributes 'id,displayName' --all)
  jq -er '.data.resources | if length == 1 then .[0].id else empty end' <<<"$result" 2>/dev/null || true
}

create_group_if_missing() {
  local group_name=$1 existing created
  existing=$(find_group_id "$group_name")
  if [[ -n "$existing" ]]; then
    printf '%s|0\n' "$existing"
    return
  fi
  created=$(oci identity-domains group create --endpoint "$identity_endpoint" --display-name "$group_name" --schemas '["urn:ietf:params:scim:schemas:core:2.0:Group"]')
  printf '%s|1\n' "$(jq -er '.data.id' <<<"$created")"
}

user_has_group() {
  local user_id=$1 group_id=$2 result
  result=$(oci identity-domains user get --endpoint "$identity_endpoint" --user-id "$user_id" --attributes groups)
  jq -e --arg group_id "$group_id" 'any(.data.groups[]?; .value == $group_id)' >/dev/null <<<"$result"
}

add_user_to_group_if_missing() {
  local user_id=$1 group_id=$2
  if user_has_group "$user_id" "$group_id"; then
    printf '0\n'
    return
  fi
  oci identity-domains group patch --endpoint "$identity_endpoint" --group-id "$group_id" --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' --operations "[{\"op\":\"add\",\"path\":\"members\",\"value\":[{\"value\":\"${user_id}\"}]}]" >/dev/null || return 1
  printf '1\n'
}

write_state() {
  umask 077
  cat >"$state_file" <<STATE
IDENTITY_ENDPOINT='${identity_endpoint}'
USER_NAME='${user_name}'
USER_ID='${user_id}'
EMPLOYEES_GROUP_ID='${employees_group_id}'
MANAGERS_GROUP_ID='${managers_group_id}'
EMPLOYEES_GROUP_CREATED='${employees_group_created}'
MANAGERS_GROUP_CREATED='${managers_group_created}'
EMPLOYEES_MEMBERSHIP_ADDED='${employees_membership_added}'
MANAGERS_MEMBERSHIP_ADDED='${managers_membership_added}'
STATE
  chmod 600 "$state_file"
}

user_id=$(find_user_id) || die "Expected exactly one Identity Domain user named ${user_name}."
[[ -n "$user_id" ]] || die "Expected exactly one Identity Domain user named ${user_name}."
IFS='|' read -r employees_group_id employees_group_created < <(create_group_if_missing EMPLOYEES)
IFS='|' read -r managers_group_id managers_group_created < <(create_group_if_missing MANAGERS)
if [[ "$employees_group_id" == "$previous_employees_group_id" && "$previous_employees_group_created" == 1 ]]; then
  employees_group_created=1
fi
if [[ "$managers_group_id" == "$previous_managers_group_id" && "$previous_managers_group_created" == 1 ]]; then
  managers_group_created=1
fi
employees_membership_added=0
managers_membership_added=0
write_state
employees_membership_added=$(add_user_to_group_if_missing "$user_id" "$employees_group_id") || die "Could not add ${user_name} to EMPLOYEES. Cleanup state was preserved in ${state_file}."
write_state
managers_membership_added=$(add_user_to_group_if_missing "$user_id" "$managers_group_id") || die "Could not add ${user_name} to MANAGERS. Cleanup state was preserved in ${state_file}."
write_state
printf 'Identity groups ready for %s. State: %s\n' "$user_name" "$state_file"
printf '  EMPLOYEES: %s (created=%s, membership_added=%s)\n' "$employees_group_id" "$employees_group_created" "$employees_membership_added"
printf '  MANAGERS:  %s (created=%s, membership_added=%s)\n' "$managers_group_id" "$managers_group_created" "$managers_membership_added"
