#!/usr/bin/env bash
# Let OCI GenAI choose a reviewed HR query tool, then run it as the current OCI IAM user.

set -Eeuo pipefail

red_error() { printf '\n\n\033[0;31mERROR: %s\033[0m\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: ./08_llm_query_hr_as_current_user.sh --prompt TEXT [options]

An LLM selects one reviewed, read-only HR query tool. This script validates the
selection, runs that fixed SQL as the current OCI IAM OAuth user, and supplies
the result to the LLM for its final answer. The model cannot supply SQL.

Available query tools:
  employee_count            Count authorized HR.EMPLOYEES rows.
  employees_by_department   Count authorized rows by department.
  employees_by_job_code     Count authorized rows by job code.
  list_authorized_employees List authorized non-sensitive employee fields.

Options:
  --prompt TEXT       Required natural-language question.
  --model-id ID       Default: meta.llama-3.3-70b-instruct.
  --region REGION     Default: us-chicago-1.
  --max-tokens N      Default: 512; applies to the final answer.
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
# shellcheck disable=SC1091
source "${ADB_LAB_DIR}/lib_token_check.sh"
command -v sqlplus >/dev/null 2>&1 || die 'sqlplus is required.'
check_current_oauth_token

compartment_id=$(genai_compartment_id)
connection_timeout=${OCI_CONNECTION_TIMEOUT:-10}
read_timeout=${OCI_READ_TIMEOUT:-60}
response_file=$(mktemp)
trap 'rm -f "$response_file"' EXIT
serving_mode=$(printf '{"servingType":"ON_DEMAND","modelId":"%s"}' "$model_id")

router_request=$(python3 - "$prompt" <<'PY'
import json
import sys

question = sys.argv[1]
instructions = '''You select one database query tool for a user's question.
Return exactly one JSON object and no markdown, with this schema:
{"tool":"TOOL_NAME"}

Allowed tool names:
- employee_count: count authorized HR.EMPLOYEES rows.
- employees_by_department: count authorized rows grouped by department.
- employees_by_job_code: count authorized rows grouped by job code.
- list_authorized_employees: list authorized employee ID, name, job code,
  department, manager, and user name. It excludes salary, SSN, phone, and photo.
- unsupported: use only when none of the tools can answer.

Never write SQL. Never invent a tool. User question:
''' + question
print(json.dumps({
    "apiFormat": "GENERIC",
    "messages": [{"role": "USER", "content": [{"type": "TEXT", "text": instructions}]}],
    "maxTokens": 64,
    "temperature": 0
}))
PY
)

green_banner 'LLM-controlled, reviewed HR query tools'
printf 'Question: %s\n' "$prompt"
printf 'Step 1: Ask OCI Generative AI to choose one reviewed query tool.\n'
show_cmd oci generative-ai-inference chat-result chat --region "$region" --connection-timeout "$connection_timeout" --read-timeout "$read_timeout" --compartment-id "$compartment_id" --serving-mode '<on-demand model>' --chat-request '<tool-selection request>'
oci_with_profile generative-ai-inference chat-result chat \
  --region "$region" \
  --connection-timeout "$connection_timeout" \
  --read-timeout "$read_timeout" \
  --compartment-id "$compartment_id" \
  --serving-mode "$serving_mode" \
  --chat-request "$router_request" \
  --output json >"$response_file"

tool=$(python3 - "$response_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    response = json.load(source)
try:
    text = response["data"]["chat-response"]["choices"][0]["message"]["content"][0]["text"].strip()
    tool = json.loads(text)["tool"]
except (KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError) as exc:
    raise SystemExit(f"\033[0;31mERROR: LLM returned an invalid tool selection: {exc}\033[0m")

allowed = {
    "employee_count",
    "employees_by_department",
    "employees_by_job_code",
    "list_authorized_employees",
    "unsupported",
}
if tool not in allowed:
    raise SystemExit(f"\033[0;31mERROR: LLM selected disallowed tool: {tool!r}\033[0m")
print(tool)
PY
)

printf 'Selected tool: %s\n' "$tool"
if [[ "$tool" == unsupported ]]; then
  printf '%s\n' 'No query was executed: the question is outside the reviewed tool set.'
  printf '%s\n' 'Supported questions cover employee count, counts by department/job code, and authorized employee listings.'
  exit 0
fi

printf '\nStep 2: Run the fixed SQL for %s as the current OCI IAM user.\n' "$tool"
show_cmd sqlplus -L -s "/@${ADB_SERVICE}" "@${script_dir}/08_llm_query_hr_as_current_user.sql" "$tool"
tool_result=$(sqlplus -L -s "/@${ADB_SERVICE}" @"${script_dir}/08_llm_query_hr_as_current_user.sql" "$tool")
tool_result=$(printf '%s' "$tool_result" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), separators=(",", ":")))')
printf 'Reviewed query result: %s\n' "$tool_result"

answer_request=$(python3 - "$prompt" "$tool" "$tool_result" "$max_tokens" <<'PY'
import json
import sys

question, tool, result, max_tokens = sys.argv[1:]
instruction = (
    "Answer the user using only the reviewed database-tool result below. "
    "Do not claim to have executed SQL yourself and do not infer unavailable data.\n\n"
    f"USER_QUESTION:\n{question}\n\n"
    f"TOOL_USED:\n{tool}\n\n"
    f"AUTHORIZED_TOOL_RESULT_JSON:\n{result}"
)
print(json.dumps({
    "apiFormat": "GENERIC",
    "messages": [{"role": "USER", "content": [{"type": "TEXT", "text": instruction}]}],
    "maxTokens": int(max_tokens),
    "temperature": 0,
}))
PY
)

printf '\nStep 3: Return the reviewed query result to OCI Generative AI for the answer.\n'
show_cmd oci generative-ai-inference chat-result chat --region "$region" --connection-timeout "$connection_timeout" --read-timeout "$read_timeout" --compartment-id "$compartment_id" --serving-mode '<on-demand model>' --chat-request '<authorized tool result plus question>'
oci_with_profile generative-ai-inference chat-result chat \
  --region "$region" \
  --connection-timeout "$connection_timeout" \
  --read-timeout "$read_timeout" \
  --compartment-id "$compartment_id" \
  --serving-mode "$serving_mode" \
  --chat-request "$answer_request" \
  --output json
