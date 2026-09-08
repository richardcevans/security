#!/usr/bin/env bash
# Ask OCI GenAI to select and use a reviewed HR query tool through the local service.

set -Eeuo pipefail

red_error() { printf '\n\n\033[0;31mERROR: %s\033[0m\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: ./12_ask_llm_service.sh --question TEXT

Sends your current OCI IAM database access token and question to the loopback
service. OCI Generative AI selects a reviewed tool, the service executes that
tool as the token user, and the LLM answers from the authorized result.
The service never accepts LLM-generated SQL.
EOF
}

question=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --question) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; question=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ -n "$question" ]] || { red_error '--question is required.'; exit 2; }

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${script_dir}/lab_common.sh"
load_adb_lab_environment
# shellcheck disable=SC1091
source "${ADB_LAB_DIR}/lib_token_check.sh"
command -v curl >/dev/null 2>&1 || die 'curl is required.'
check_current_oauth_token

host=${IDENTITY_SERVICE_HOST:-127.0.0.1}
port=${IDENTITY_SERVICE_PORT:-8030}
[[ "$host" == "127.0.0.1" || "$host" == "localhost" || "$host" == "::1" ]] || die 'This client only sends tokens to the loopback service.'
token_file="${OCI_TOKEN_DIR:?OCI_TOKEN_DIR is required}/token"
[[ -r "$token_file" ]] || die "Token file not found: ${token_file}"
token=$(<"$token_file")
payload=$(python3 - "$question" <<'PY'
import json
import sys
print(json.dumps({"question": sys.argv[1]}, separators=(",", ":")))
PY
)

green_banner 'Ask OCI Generative AI through the local OCI IAM-to-ADB service'
printf 'Question: %s\n' "$question"
printf 'Target  : http://%s:%s/v1/ask\n' "$host" "$port"
printf '%s\n\n' 'The bearer token is not printed. The service accepts no SQL from the LLM.'

response_file=$(mktemp)
trap 'rm -f "$response_file"' EXIT
if ! curl --fail-with-body --silent --show-error \
  --connect-timeout 10 \
  --max-time 150 \
  --request POST "http://${host}:${port}/v1/ask" \
  --header "Authorization: Bearer ${token}" \
  --header 'Content-Type: application/json' \
  --data "$payload" >"$response_file"; then
  error 'The LLM service did not return a successful response.'
  [[ -s "$response_file" ]] && { printf 'Response body:\n' >&2; cat "$response_file" >&2; printf '\n' >&2; }
  exit 1
fi

python3 -m json.tool <"$response_file"
