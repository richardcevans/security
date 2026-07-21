#!/usr/bin/env bash
# Compatibility wrapper for legacy identity setup and its coupled ADB creation.
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${script_dir}/../lib/common.sh"

from_terraform=false
if [[ "${1:-}" == "--from-terraform" ]]; then
  from_terraform=true
  shift
fi

if "$from_terraform"; then
  handoff_file="${LAB_STATE_DIR}/terraform.env"
  test -f "$handoff_file" || die 'Terraform handoff is missing. Run capture-terraform-outputs.sh after Terraform apply.'
  # shellcheck disable=SC1090
  source "$handoff_file"
  require_command oci
  if [[ -z "${OCI_CLI_REGION:-}" ]]; then
    terraform_vars="${LAB_ROOT}/terraform/terraform.tfvars"
    [[ -f "$terraform_vars" ]] || die "Terraform variables file is missing: ${terraform_vars}"
    oci_region=$(awk -F'"' '/^[[:space:]]*region[[:space:]]*=/ {print $2; exit}' "$terraform_vars")
    [[ -n "$oci_region" ]] || die "Could not determine region from ${terraform_vars}; set OCI_CLI_REGION explicitly."
    export OCI_CLI_REGION="$oci_region"
  fi
  if [[ "${LAB_DRY_RUN:-0}" != 1 ]]; then
    actual_db_name=$(oci db autonomous-database get --autonomous-database-id "$ADB_OCID" --query 'data."db-name"' --raw-output)
    [[ "$actual_db_name" == "$DB_NAME" ]] || die 'Terraform output DB_NAME does not match ADB_OCID.'
  fi
  export DB_NAME DB_NAME_REUSE_PREFIX="$DB_NAME"
  info "Terraform handoff verified in ${OCI_CLI_REGION}; legacy setup will reuse this exact ADB-S."
fi

info 'Identity configuration delegates to legacy setup.'
info 'Legacy setup also creates or reuses Autonomous AI Database and downloads a wallet.'
info 'This coupling remains until Terraform and independent identity scripts are tested.'
run_legacy_script 00_setup_adb.sh "$@"
