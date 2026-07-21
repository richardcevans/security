#!/usr/bin/env bash
set -Eeuo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${script_dir}/../lib/common.sh"
env_file="${LAB_STATE_DIR}/terraform.env"
test -f "$env_file" || die 'Terraform handoff is missing. Run capture-terraform-outputs.sh after Terraform apply.'
# shellcheck disable=SC1090
source "$env_file"
require_command oci
source_file="${LAB_ROOT}/data/bonuses.csv"
oci_region="${OCI_REGION:-}"
[[ -n "$oci_region" ]] || die 'OCI_REGION is required because Object Storage buckets are regional, for example: OCI_REGION=us-chicago-1 ./bin/upload-demo-data.sh'
[[ "${LAB_DRY_RUN:-0}" == 1 ]] && { echo "DRY RUN: upload ${source_file} to ${DEMO_BUCKET_NAME}/bonus-data/bonuses.csv in ${oci_region}"; exit 0; }
oci os object put --region "$oci_region" --namespace "$OBJECT_STORAGE_NAMESPACE" --bucket-name "$DEMO_BUCKET_NAME" --name bonus-data/bonuses.csv --file "$source_file" --force
