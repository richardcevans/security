#!/usr/bin/env bash
# Configure and smoke-test one OCI Generative AI Select AI profile on the attached ADB.

set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${script_dir}/../lib/common.sh"

usage() {
  cat <<'EOF'
Usage: ./bin/configure-select-ai.sh [options]

Enables the OCI resource principal for ADMIN, then replaces only the
DEEPSEC_HR_CHAT ADMIN-owned Select AI profile. The profile uses the Chicago
meta.llama-3.3-70b-instruct model and the GenAI lab compartment. Its smoke test
uses DBMS_CLOUD_AI.GENERATE with a fixed harmless chat prompt; it does not query
HR data.

Options:
  --compartment-id OCID  GenAI compartment (default: .lab/genai.env).
  --region REGION        Default: us-chicago-1.
  --model-id MODEL       Default: meta.llama-3.3-70b-instruct.
  --help                 Show this help.
EOF
}

compartment_id=''
region='us-chicago-1'
model_id='meta.llama-3.3-70b-instruct'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --compartment-id) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; compartment_id=$2; shift 2 ;;
    --region) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; region=$2; shift 2 ;;
    --model-id) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; model_id=$2; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

load_legacy_environment
[[ -n "${ADMIN_PWD:-}" && -n "${ADB_SERVICE:-}" ]] || die 'The attached adb-oci-iam environment lacks ADMIN_PWD or ADB_SERVICE.'
if [[ -z "$compartment_id" ]]; then
  compartment_id=${ROOT_COMP_ID:-${COMPARTMENT_OCID:-}}
fi
if [[ -z "$compartment_id" && -f "${LAB_STATE_DIR}/genai.env" ]]; then
  # shellcheck disable=SC1091 # Written only by create-genai-compartment.sh.
  source "${LAB_STATE_DIR}/genai.env"
  compartment_id=${COMPARTMENT_OCID:-}
fi
[[ -n "$compartment_id" ]] || die 'No compartment is configured. Set OCI_COMPARTMENT/ROOT_COMP_ID in adb-oci-iam or provide --compartment-id.'
[[ -f "${LAB_STATE_DIR}/select-ai-access.env" ]] || die 'Resource-principal access is not recorded. Run ./bin/labctl select-ai access first.'
require_command sqlplus

sql_file="${LAB_ROOT}/sql/10_configure_select_ai.sql"
[[ -f "$sql_file" ]] || die "Missing SQL file: ${sql_file}"

printf 'Configuring Select AI profile DEEPSEC_HR_CHAT on %s.\n' "$ADB_SERVICE"
printf '  GenAI region : %s\n  GenAI model  : %s\n  compartment  : %s\n' "$region" "$model_id" "$compartment_id"
printf '%s\n' 'SQL*Plus section prompts identify each action; duplicate command echo is disabled.'

sqlplus -L "admin/${ADMIN_PWD}@${ADB_SERVICE}" \
  @"$sql_file" "$compartment_id" "$region" "$model_id"
