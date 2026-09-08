#!/usr/bin/env bash
# Query authorized HR rows first, then submit only those rows to OCI GenAI.

set -Eeuo pipefail

red_error() { printf '\n\n\033[0;31mERROR: %s\033[0m\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: ./04_llm_with_authorized_hr_data.sh --prompt TEXT [options]

First runs the fixed reviewed HR.EMPLOYEES query as the current OCI IAM OAuth
user. It then sends only the JSON rows returned by ADB, plus --prompt, to OCI
Generative AI. The LLM has no database credentials and cannot execute SQL.

Options:
  --prompt TEXT       Required question about the authorized rows.
  --model-id ID       Default: meta.llama-3.3-70b-instruct.
  --region REGION     Default: us-chicago-1.
  --max-tokens N      Default: 512.
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
[[ -n "$prompt" ]] || { red_error '--prompt is required.'; exit 2; }
[[ "$max_tokens" =~ ^[1-9][0-9]*$ ]] || { red_error '--max-tokens must be a positive integer.'; exit 2; }

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${script_dir}/lab_common.sh"
load_adb_lab_environment
load_oci_profile
compartment_id=$(genai_compartment_id)
connection_timeout=${OCI_CONNECTION_TIMEOUT:-10}
read_timeout=${OCI_READ_TIMEOUT:-60}
rows_file=$(mktemp)
trap 'rm -f "$rows_file"' EXIT

printf 'Step 1: Query ADB as the current OCI IAM user.\n'
show_cmd "${script_dir}/03_query_hr_employees_as_current_user.sh" --json
"${script_dir}/03_query_hr_employees_as_current_user.sh" --json >"$rows_file"
row_count=$(python3 - "$rows_file" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    print(len(json.load(source) or []))
PY
)
printf 'ADB returned %s authorized row(s).\n\n' "$row_count"

request=$(python3 - "$prompt" "$max_tokens" "$rows_file" <<'PY'
import json
import sys

question, max_tokens, rows_file = sys.argv[1:]
with open(rows_file, encoding="utf-8") as source:
    rows = json.load(source)
instruction = (
    "Answer only from the authorized HR rows below. Do not claim access to other "
    "database data. If the rows do not answer the question, say so.\n\n"
    "AUTHORIZED_ROWS_JSON:\n" + json.dumps(rows, separators=(",", ":")) +
    "\n\nQUESTION:\n" + question
)
print(json.dumps({
    "apiFormat": "GENERIC",
    "messages": [{"role": "USER", "content": [{"type": "TEXT", "text": instruction}]}],
    "maxTokens": int(max_tokens),
    "temperature": 0
}))
PY
)
serving_mode=$(printf '{"servingType":"ON_DEMAND","modelId":"%s"}' "$model_id")

printf 'Step 2: Send only the ADB-authorized rows and your question to OCI Generative AI.\n'
printf '  model       : %s\n  compartment: %s\n  question    : %s\n' "$model_id" "$compartment_id" "$prompt"
show_cmd oci generative-ai-inference chat-result chat --region "$region" --connection-timeout "$connection_timeout" --read-timeout "$read_timeout" --compartment-id "$compartment_id" --serving-mode '<on-demand model>' --chat-request '<authorized ADB rows plus prompt>'
oci_with_profile generative-ai-inference chat-result chat \
  --region "$region" \
  --connection-timeout "$connection_timeout" \
  --read-timeout "$read_timeout" \
  --compartment-id "$compartment_id" \
  --serving-mode "$serving_mode" \
  --chat-request "$request" \
  --output json
