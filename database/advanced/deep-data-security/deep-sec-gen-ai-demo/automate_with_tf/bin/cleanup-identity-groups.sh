#!/usr/bin/env bash
# Remove only Identity Domain resources recorded by configure-identity-groups.sh.
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${script_dir}/../lib/common.sh"

[[ "${1:-}" == '--yes' && $# -eq 1 ]] || die 'Usage: ./bin/cleanup-identity-groups.sh --yes'
require_command oci
state_file="${LAB_STATE_DIR}/identity-groups.env"
[[ -f "$state_file" ]] || die "No identity-group state file exists at ${state_file}; refusing cleanup."
# shellcheck disable=SC1090
source "$state_file"

remove_membership_if_added() {
  local group_id=$1 membership_added=$2
  [[ "$membership_added" == 1 ]] || return 0
  oci identity-domains group patch --endpoint "$IDENTITY_ENDPOINT" --group-id "$group_id" --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' --operations "[{\"op\":\"remove\",\"path\":\"members[value eq \\\"${USER_ID}\\\"]\"}]" >/dev/null
}

delete_group_if_created() {
  local group_id=$1 group_created=$2
  [[ "$group_created" == 1 ]] || return 0
  oci identity-domains group delete --endpoint "$IDENTITY_ENDPOINT" --group-id "$group_id" --force
}

delete_group_if_created "$EMPLOYEES_GROUP_ID" "$EMPLOYEES_GROUP_CREATED"
delete_group_if_created "$MANAGERS_GROUP_ID" "$MANAGERS_GROUP_CREATED"
[[ "$EMPLOYEES_GROUP_CREATED" == 1 ]] || remove_membership_if_added "$EMPLOYEES_GROUP_ID" "$EMPLOYEES_MEMBERSHIP_ADDED"
[[ "$MANAGERS_GROUP_CREATED" == 1 ]] || remove_membership_if_added "$MANAGERS_GROUP_ID" "$MANAGERS_MEMBERSHIP_ADDED"
rm -f "$state_file"
printf 'Identity-group cleanup completed.\n'
