#!/usr/bin/env bash
# Prepare or run a deliberately minimal OCI Generative AI inference smoke test.

set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${script_dir}/../lib/common.sh"

usage() {
  cat <<'EOF'
Usage:
  ./bin/genai-readiness.sh --region REGION --compartment-id OCID --generate-inputs
  ./bin/genai-readiness.sh --region REGION --compartment-id OCID \
    --smoke-test --chat-request FILE --serving-mode FILE

Creates request templates using the locally installed OCI CLI, or runs one
explicit GenAI chat request supplied by the user. The smoke test does not query
the database and must contain no HR or other sensitive data. It may incur OCI
Generative AI inference charges.
EOF
}

region=''
compartment_id=''
generate_inputs=false
smoke_test=false
chat_request=''
serving_mode=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      region=$2
      shift 2
      ;;
    --compartment-id)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      compartment_id=$2
      shift 2
      ;;
    --generate-inputs)
      generate_inputs=true
      shift
      ;;
    --smoke-test)
      smoke_test=true
      shift
      ;;
    --chat-request)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      chat_request=$2
      shift 2
      ;;
    --serving-mode)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      serving_mode=$2
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

[[ "$generate_inputs" == true || "$smoke_test" == true ]] || die 'Choose --generate-inputs or --smoke-test.'
[[ -n "$region" && -n "$compartment_id" ]] || die 'Both --region and --compartment-id are required; no region is inferred.'
[[ ! ( "$generate_inputs" == true && "$smoke_test" == true ) ]] || die 'Run --generate-inputs and --smoke-test as separate commands.'

attachment_file="${LAB_STATE_DIR}/attached-adb.env"
baseline_file="${LAB_STATE_DIR}/baseline-passed.env"
[[ -f "$attachment_file" ]] || die 'No ADB attachment exists. Run ./bin/labctl attach first.'
[[ -f "$baseline_file" ]] || die 'The attached OCI IAM baseline has not passed. Run ./bin/labctl baseline first.'

load_legacy_environment
# shellcheck disable=SC1091 # Resolved from the attached legacy lab.
source "${LEGACY_LAB_ROOT}/lib_oci_profile.sh"
require_command oci

input_dir="${LAB_STATE_DIR}/genai-readiness"
mkdir -p "$input_dir"

if "$generate_inputs"; then
  chat_template="${input_dir}/chat-request.template.json"
  serving_template="${input_dir}/serving-mode.template.json"
  oci_with_profile generative-ai-inference chat-result chat \
    --generate-param-json-input chat-request >"$chat_template"
  oci_with_profile generative-ai-inference chat-result chat \
    --generate-param-json-input serving-mode >"$serving_template"
  chmod 600 "$chat_template" "$serving_template"
  info 'Generated request templates from the installed OCI CLI.'
  info "Chat request template: ${chat_template}"
  info "Serving mode template: ${serving_template}"
  info 'Edit copies of these files to select an on-demand model and use a harmless prompt, then run --smoke-test.'
  exit 0
fi

[[ -n "$chat_request" && -n "$serving_mode" ]] || die '--smoke-test requires --chat-request FILE and --serving-mode FILE.'
[[ -f "$chat_request" ]] || die "Chat request file not found: ${chat_request}"
[[ -f "$serving_mode" ]] || die "Serving mode file not found: ${serving_mode}"

response_file="${input_dir}/chat-response-$(date -u +%Y%m%dT%H%M%SZ).json"
info 'Running an explicit OCI Generative AI smoke test. Do not include HR or sensitive data in the request.'
oci_with_profile generative-ai-inference chat-result chat \
  --region "$region" \
  --compartment-id "$compartment_id" \
  --chat-request "file://${chat_request}" \
  --serving-mode "file://${serving_mode}" \
  --output json >"$response_file"
chmod 600 "$response_file"
info "GenAI smoke test succeeded. Response: ${response_file}"
