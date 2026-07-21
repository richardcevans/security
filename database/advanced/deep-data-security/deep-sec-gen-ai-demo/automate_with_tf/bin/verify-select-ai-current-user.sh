#!/usr/bin/env bash
# Run the Select AI checks through the current OCI IAM OAuth token session.

set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${script_dir}/../lib/common.sh"

usage() {
  cat <<'EOF'
Usage: ./bin/verify-select-ai-current-user.sh [--run]

Uses whichever OCI IAM identity is represented by the current OAuth token.
It first runs a harmless Select AI chat call, then generates SQL for a fixed
HR.EMPLOYEES question with action=showsql.

--run: changes only the HR step to action=runsql. The generated query executes
under the OCI IAM-authenticated database session, so its existing data roles
and grants determine the result.

No database or OCI resources are created or changed.
EOF
}

action='showsql'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run) action='runsql'; shift ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

load_legacy_environment
# shellcheck disable=SC1091 # Resolved from the attached legacy lab.
source "${LEGACY_LAB_ROOT}/lib_token_check.sh"
require_command sqlplus
check_current_oauth_token

sql_file="${LAB_ROOT}/sql/12_verify_select_ai_current_user.sql"
[[ -f "$sql_file" ]] || die "Missing SQL file: ${sql_file}"

if [[ "$action" == 'showsql' ]]; then
  printf '%s\n' 'Current OCI IAM user: Select AI chat plus generated SQL only; no HR query executes.'
else
  printf '%s\n' 'Current OCI IAM user: the generated HR query WILL execute under this token session.'
fi
printf '  sqlplus -L -s /@%s\n' "$ADB_SERVICE"

sqlplus -L -s "/@${ADB_SERVICE}" @"$sql_file" "$action"
