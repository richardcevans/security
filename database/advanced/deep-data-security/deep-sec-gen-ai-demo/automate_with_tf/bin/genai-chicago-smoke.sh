#!/usr/bin/env bash
# Send one harmless prompt to OCI Generative AI in Chicago.

set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${script_dir}/../lib/common.sh"
# shellcheck disable=SC1091 # Shared OCI CLI profile selector from the attached lab.
source "${LEGACY_LAB_ROOT}/lib_oci_profile.sh"

usage() {
  cat <<'EOF'
Usage: ./bin/genai-chicago-smoke.sh [--compartment-id OCID] [options]

Runs one harmless OCI Generative AI chat request. It does not connect to ADB
and does not send HR or other lab data.

Options:
  --compartment-id OCID  Override the attached ADB lab compartment.
  --model-id ID          On-demand model ID (default: meta.llama-3.3-70b-instruct).
  --region REGION        OCI region (default: us-chicago-1).
  --help                 Show this help.

OCI_PROFILE, OCI_PROFILE_NAME, OCI_CLI_PROFILE, and OCI_CONFIG_FILE are
honored through the shared OCI CLI profile selector. Set at most one profile
variable (unless the values are identical).
EOF
}

compartment_id=''
region='us-chicago-1'
model_id='meta.llama-3.3-70b-instruct'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compartment-id)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      compartment_id=$2
      shift 2
      ;;
    --model-id)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      model_id=$2
      shift 2
      ;;
    --region)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      region=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

load_legacy_environment
compartment_id=${compartment_id:-${ROOT_COMP_ID:-${COMPARTMENT_OCID:-}}}
[[ -n "$compartment_id" ]] || die 'No compartment is configured. Set OCI_COMPARTMENT/ROOT_COMP_ID in adb-oci-iam or provide --compartment-id.'
require_command oci

# GENERIC is the OCI CLI chat format for this text-only, on-demand smoke test.
# Keep this fixed prompt free of customer, HR, ADB, or Identity Domain data.
chat_request='{"apiFormat":"GENERIC","messages":[{"role":"USER","content":[{"type":"TEXT","text":"Reply with exactly: OCI Generative AI smoke test passed."}]}],"maxTokens":20,"temperature":0}'
serving_mode=$(printf '{"servingType":"ON_DEMAND","modelId":"%s"}' "$model_id")

mkdir -p "${LAB_STATE_DIR}/genai-smoke"
response_file="${LAB_STATE_DIR}/genai-smoke/response-$(date -u +%Y%m%dT%H%M%SZ).json"

printf '\nOCI Generative AI Chicago smoke test\n'
printf '  region      : %s\n' "$region"
printf '  model       : %s\n' "$model_id"
printf '  compartment: %s\n' "$compartment_id"
printf '  OCI profile : %s\n\n' "${OCI_PROFILE_SELECTED:-DEFAULT}"
printf 'Running: oci generative-ai-inference chat-result chat --region %q --compartment-id %q --serving-mode <on-demand model> --chat-request <harmless fixed prompt>\n\n' "$region" "$compartment_id"

oci_with_profile generative-ai-inference chat-result chat \
  --region "$region" \
  --compartment-id "$compartment_id" \
  --serving-mode "$serving_mode" \
  --chat-request "$chat_request" \
  --output json >"$response_file"
chmod 600 "$response_file"

printf 'SUCCESS: OCI Generative AI returned a response.\n'
printf 'Response: %s\n\n' "$response_file"
cat "$response_file"
printf '\n'
