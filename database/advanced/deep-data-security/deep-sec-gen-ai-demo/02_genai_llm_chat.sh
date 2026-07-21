#!/usr/bin/env bash
# Send an explicit prompt directly to OCI Generative AI; no ADB or Select AI.

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: ./02_genai_llm_chat.sh --prompt TEXT [options]

Calls OCI Generative AI directly with the current OCI CLI profile. It does not
connect to ADB, execute SQL, read HR data, or use Select AI. Only the prompt
you provide is sent to the model.

Options:
  --prompt TEXT       Required prompt to send to the LLM.
  --model-id ID       Default: meta.llama-3.3-70b-instruct.
  --region REGION     Default: us-chicago-1.
  --max-tokens N      Default: 512.
  --help              Show this help.

OCI_CONNECTION_TIMEOUT defaults to 10 seconds and OCI_READ_TIMEOUT to 60.
EOF
}

prompt=''
region=${GENAI_REGION:-us-chicago-1}
model_id=${GENAI_MODEL_ID:-meta.llama-3.3-70b-instruct}
max_tokens=512
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; prompt=$2; shift 2 ;;
    --model-id) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; model_id=$2; shift 2 ;;
    --region) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; region=$2; shift 2 ;;
    --max-tokens) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; max_tokens=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ -n "$prompt" ]] || { echo 'ERROR: --prompt is required.' >&2; usage >&2; exit 2; }
[[ "$max_tokens" =~ ^[1-9][0-9]*$ ]] || { echo 'ERROR: --max-tokens must be a positive integer.' >&2; exit 2; }

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${script_dir}/lab_common.sh"
load_adb_lab_environment
load_oci_profile

compartment_id=$(genai_compartment_id)
connection_timeout=${OCI_CONNECTION_TIMEOUT:-10}
read_timeout=${OCI_READ_TIMEOUT:-60}
request=$(printf '%s' "$prompt" | python3 -c '
import json
import sys
prompt = sys.stdin.read()
print(json.dumps({
  "apiFormat": "GENERIC",
  "messages": [{"role": "USER", "content": [{"type": "TEXT", "text": prompt}]}],
  "maxTokens": int(sys.argv[1]),
  "temperature": 0
}))
' "$max_tokens")
serving_mode=$(printf '{"servingType":"ON_DEMAND","modelId":"%s"}' "$model_id")

printf 'Direct OCI Generative AI / LLM chat\n'
printf '  region      : %s\n  model       : %s\n  compartment: %s\n' "$region" "$model_id" "$compartment_id"
printf '  prompt      : %s\n\n' "$prompt"
show_cmd oci generative-ai-inference chat-result chat --region "$region" --connection-timeout "$connection_timeout" --read-timeout "$read_timeout" --compartment-id "$compartment_id" --serving-mode '<on-demand model>' --chat-request '<request from --prompt>'

oci_with_profile generative-ai-inference chat-result chat \
  --region "$region" \
  --connection-timeout "$connection_timeout" \
  --read-timeout "$read_timeout" \
  --compartment-id "$compartment_id" \
  --serving-mode "$serving_mode" \
  --chat-request "$request" \
  --output json
