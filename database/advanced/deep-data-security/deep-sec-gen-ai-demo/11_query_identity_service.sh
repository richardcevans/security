#!/usr/bin/env bash
# Call one reviewed query tool through the local token-preserving API.

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: ./11_query_identity_service.sh TOOL [options]

Calls the local identity-preserving service using the current OCI IAM database
access token. TOOL must be one of:
  employee_count
  employees_by_department
  employees_by_job_code
  list_employees

Options for list_employees only:
  --department-id N
  --job-code CODE
  --limit N                 Default: 25, maximum: 100.
EOF
}

tool=${1:-}
case "$tool" in
  employee_count|employees_by_department|employees_by_job_code|list_employees) shift ;;
  -h|--help|'') usage; exit 0 ;;
  *) echo "ERROR: Unknown tool: ${tool}" >&2; usage >&2; exit 2 ;;
esac

department_id=''
job_code=''
limit=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --department-id) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; department_id=$2; shift 2 ;;
    --job-code) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; job_code=$2; shift 2 ;;
    --limit) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; limit=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$tool" != list_employees && ( -n "$department_id" || -n "$job_code" || -n "$limit" ) ]]; then
  echo 'ERROR: --department-id, --job-code, and --limit are valid only with list_employees.' >&2
  exit 2
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${script_dir}/lab_common.sh"
load_adb_lab_environment
# shellcheck disable=SC1091
source "${ADB_LAB_DIR}/lib_token_check.sh"
command -v curl >/dev/null 2>&1 || die 'curl is required.'
check_current_oauth_token

host=${IDENTITY_SERVICE_HOST:-127.0.0.1}
port=${IDENTITY_SERVICE_PORT:-8030}
[[ "$host" == "127.0.0.1" || "$host" == "localhost" || "$host" == "::1" ]] || die 'This verifier only sends tokens to the loopback service.'
token_file="${OCI_TOKEN_DIR:?OCI_TOKEN_DIR is required}/token"
[[ -r "$token_file" ]] || die "Token file not found: ${token_file}"
token=$(<"$token_file")
payload=$(python3 - "$tool" "$department_id" "$job_code" "$limit" <<'PY'
import json
import sys

tool, department_id, job_code, limit = sys.argv[1:]
arguments = {}
if department_id:
    try:
        arguments["department_id"] = int(department_id)
    except ValueError:
        raise SystemExit("ERROR: --department-id must be an integer")
if job_code:
    arguments["job_code"] = job_code
if limit:
    try:
        arguments["limit"] = int(limit)
    except ValueError:
        raise SystemExit("ERROR: --limit must be an integer")
print(json.dumps({"tool": tool, "arguments": arguments}, separators=(",", ":")))
PY
)

green_banner 'Run reviewed query tool through the local OCI IAM-to-ADB service'
printf 'Tool  : %s\n' "$tool"
printf 'Target: http://%s:%s/v1/query\n' "$host" "$port"
printf '%s\n' 'The bearer token is read from OCI_TOKEN_DIR/token and is not printed.'
printf '%s\n\n' 'The service accepts tool names and validated arguments only; it never accepts SQL.'

response_file=$(mktemp)
trap 'rm -f "$response_file"' EXIT
if ! curl --fail-with-body --silent --show-error \
  --connect-timeout 10 \
  --max-time 60 \
  --request POST "http://${host}:${port}/v1/query" \
  --header "Authorization: Bearer ${token}" \
  --header 'Content-Type: application/json' \
  --data "$payload" >"$response_file"; then
  printf '\nERROR: The query service did not return a successful response.\n' >&2
  [[ -s "$response_file" ]] && { printf 'Response body:\n' >&2; cat "$response_file" >&2; printf '\n' >&2; }
  exit 1
fi

python3 -m json.tool <"$response_file"
