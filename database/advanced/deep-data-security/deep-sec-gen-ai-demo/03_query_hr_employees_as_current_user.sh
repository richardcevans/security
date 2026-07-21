#!/usr/bin/env bash
# Run one fixed HR.EMPLOYEES query under the current OCI IAM OAuth session.

set -Eeuo pipefail

json_only=false
case "${1:-}" in
  --json) json_only=true ;;
  -h|--help)
    cat <<'EOF'
Usage: ./03_query_hr_employees_as_current_user.sh [--json]

Runs one fixed, reviewed SELECT against HR.EMPLOYEES using the current OCI IAM
OAuth token. The database data roles and data grants decide which rows are
returned. The query never selects SSN, salary, phone number, or photo.
EOF
    exit 0
    ;;
  '') ;;
  *) echo "Usage: $0 [--json]" >&2; exit 2 ;;
esac

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${script_dir}/lab_common.sh"
load_adb_lab_environment
# shellcheck disable=SC1091
source "${ADB_LAB_DIR}/lib_token_check.sh"
command -v sqlplus >/dev/null 2>&1 || die 'sqlplus is required.'
check_current_oauth_token >&2

if [[ "$json_only" != true ]]; then
  printf 'Fixed reviewed query (executed as the current OCI IAM token user):\n'
  sed 's/^/  /' "${script_dir}/03_query_hr_employees_as_current_user.sql"
fi

rows=$(sqlplus -L -s "/@${ADB_SERVICE}" @"${script_dir}/03_query_hr_employees_as_current_user.sql")
rows=$(printf '%s' "$rows" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), separators=(",", ":")))')

if [[ "$json_only" == true ]]; then
  printf '%s\n' "$rows"
else
  printf '\nAuthorized HR.EMPLOYEES rows returned by ADB:\n'
  printf '%s\n' "$rows" | python3 -m json.tool
fi
