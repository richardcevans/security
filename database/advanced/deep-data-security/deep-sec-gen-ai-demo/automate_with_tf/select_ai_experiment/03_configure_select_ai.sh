#!/usr/bin/env bash
# Enable ADMIN resource-principal auth and create the DEEPSEC_HR_CHAT profile.

set -Eeuo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${script_dir}/lab_common.sh"
load_adb_lab_environment

[[ -n "${ADMIN_PWD:-}" ]] || die 'ADMIN_PWD is missing from the ADB OCI IAM environment.'
compartment_id=$(genai_compartment_id)
region=${GENAI_REGION:-us-chicago-1}
model_id=${GENAI_MODEL_ID:-meta.llama-3.3-70b-instruct}
printf 'Configuring DEEPSEC_HR_CHAT on %s for compartment %s.\n' "$ADB_SERVICE" "$compartment_id"
sqlplus -L "admin/${ADMIN_PWD}@${ADB_SERVICE}" @"${script_dir}/03_configure_select_ai.sql" "$compartment_id" "$region" "$model_id"
