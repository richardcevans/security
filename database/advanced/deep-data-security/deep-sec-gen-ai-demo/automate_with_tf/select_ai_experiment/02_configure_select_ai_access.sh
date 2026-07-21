#!/usr/bin/env bash
# Grant the attached ADB resource principal minimum OCI GenAI Chat access.

set -Eeuo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${script_dir}/lab_common.sh"

replace_existing=false
case "${1:-}" in
  --replace-existing) replace_existing=true ;;
  -h|--help)
    cat <<'EOF'
Usage: ./02_configure_select_ai_access.sh [--replace-existing]

Creates/reuses the dynamic group and OCI policy needed by the attached ADB
resource principal. --replace-existing repoints the named lab dynamic group to
the current ADB and replaces the named lab policy statement when either was
created for a previous ADB or compartment.
EOF
    exit 0
    ;;
  '') ;;
  *) echo "Usage: $0 [--replace-existing]" >&2; exit 2 ;;
esac

load_adb_lab_environment
load_oci_profile

[[ -n "${ADB_OCID:-}" && -n "${TENANCY_OCID:-}" ]] || die 'ADB_OCID or TENANCY_OCID is missing.'
compartment_id=$(genai_compartment_id)
group_name=deep-sec-gen-ai-adb-rp
policy_name=deep-sec-gen-ai-adb-chat
rule="resource.id = '${ADB_OCID}'"
statement="Allow dynamic-group ${group_name} to use generative-ai-chat in compartment id ${compartment_id}"

printf '\nSelect AI OCI access plan\n'
printf '  Attached ADB       : %s\n' "$ADB_OCID"
printf '  GenAI compartment  : %s\n' "$compartment_id"
printf '  Dynamic group      : %s\n' "$group_name"
printf '  Matching rule      : %s\n' "$rule"
printf '  IAM policy         : %s\n' "$policy_name"
printf '  Policy statement   : %s\n\n' "$statement"

group_id=$(oci_with_profile iam dynamic-group list --compartment-id "$TENANCY_OCID" --name "$group_name" --lifecycle-state ACTIVE --all --query 'data[0].id' --raw-output)
if [[ -z "$group_id" || "$group_id" == null ]]; then
  printf 'Creating dynamic group %s.\n' "$group_name"
  show_cmd oci iam dynamic-group create --compartment-id "$TENANCY_OCID" --name "$group_name" --matching-rule "$rule" --wait-for-state ACTIVE
  group_id=$(oci_with_profile iam dynamic-group create --compartment-id "$TENANCY_OCID" --name "$group_name" --description 'Resource principal for the ADB Select AI profile.' --matching-rule "$rule" --wait-for-state ACTIVE --query 'data.id' --raw-output)
  printf 'Created dynamic group: %s\n' "$group_id"
else
  existing_rule=$(oci_with_profile iam dynamic-group get --dynamic-group-id "$group_id" --query 'data."matching-rule"' --raw-output)
  if [[ "$existing_rule" != "$rule" ]]; then
    printf 'Existing dynamic group: %s\n  current rule: %s\n  required rule: %s\n' "$group_id" "$existing_rule" "$rule"
    [[ "$replace_existing" == true ]] || die "It belongs to a different ADB. Re-run with --replace-existing to repoint this lab-owned group."
    show_cmd oci iam dynamic-group update --dynamic-group-id "$group_id" --matching-rule "$rule" --force --wait-for-state ACTIVE
    oci_with_profile iam dynamic-group update --dynamic-group-id "$group_id" --matching-rule "$rule" --force --wait-for-state ACTIVE >/dev/null
    printf 'Updated dynamic group for the current ADB: %s\n' "$group_id"
  fi
  printf 'Reusing dynamic group: %s\n' "$group_id"
fi

policy_id=$(oci_with_profile iam policy list --compartment-id "$TENANCY_OCID" --name "$policy_name" --lifecycle-state ACTIVE --all --query 'data[0].id' --raw-output)
if [[ -z "$policy_id" || "$policy_id" == null ]]; then
  printf 'Creating IAM policy %s.\n' "$policy_name"
  show_cmd oci iam policy create --compartment-id "$TENANCY_OCID" --name "$policy_name" --statements "[\"${statement}\"]" --wait-for-state ACTIVE
  policy_id=$(oci_with_profile iam policy create --compartment-id "$TENANCY_OCID" --name "$policy_name" --description 'Allow the attached ADB resource principal to use OCI Generative AI Chat.' --statements "[\"${statement}\"]" --wait-for-state ACTIVE --query 'data.id' --raw-output)
  printf 'Created policy: %s\n' "$policy_id"
else
  existing_statements=$(oci_with_profile iam policy get --policy-id "$policy_id" --query 'data.statements' --output json)
  if [[ "$existing_statements" != *"$statement"* ]]; then
    printf 'Existing policy: %s\n  required statement: %s\n' "$policy_id" "$statement"
    [[ "$replace_existing" == true ]] || die "It does not contain the required statement. Re-run with --replace-existing to replace this lab-owned policy statement."
    show_cmd oci iam policy update --policy-id "$policy_id" --statements "[\"${statement}\"]" --force --wait-for-state ACTIVE
    oci_with_profile iam policy update --policy-id "$policy_id" --statements "[\"${statement}\"]" --force --wait-for-state ACTIVE >/dev/null
    printf 'Updated policy for the current compartment: %s\n' "$policy_id"
  fi
  printf 'Reusing policy: %s\n' "$policy_id"
fi

umask 077
cat > "${script_dir}/.select-ai-access.env" <<EOF
export SELECT_AI_DYNAMIC_GROUP_ID='${group_id}'
export SELECT_AI_POLICY_ID='${policy_id}'
export SELECT_AI_COMPARTMENT_ID='${compartment_id}'
EOF
printf 'Resource-principal access is ready. OCI policy propagation and ADB resource-principal token refresh can take time.\n'
