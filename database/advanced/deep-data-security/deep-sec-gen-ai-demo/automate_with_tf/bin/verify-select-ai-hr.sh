#!/usr/bin/env bash
# Validate the ADMIN-owned Select AI profile against HR.EMPLOYEES.

set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${script_dir}/../lib/common.sh"

usage() {
  cat <<'EOF'
Usage: ./bin/verify-select-ai-hr.sh [--run]

Default: calls DBMS_CLOUD_AI.GENERATE with action=showsql. It sends the
HR.EMPLOYEES metadata permitted by the profile to the model and prints generated
SQL, but does not execute that SQL.

--run: calls action=runsql as ADMIN. This executes the generated query as ADMIN
and is only a profile/function test; it is not a Deep Data Security end-user
authorization test.

Profiles are schema-owned. The ADMIN-owned DEEPSEC_HR_CHAT profile cannot be
granted to an OCI IAM data-role session, so this script intentionally does not
claim to validate end-user data grants.
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
[[ -n "${ADMIN_PWD:-}" && -n "${ADB_SERVICE:-}" ]] || die 'The attached adb-oci-iam environment lacks ADMIN_PWD or ADB_SERVICE.'
[[ -f "${LAB_STATE_DIR}/select-ai-access.env" ]] || die 'Select AI access is not recorded. Run ./bin/labctl select-ai access first.'
require_command sqlplus

sql_file="${LAB_ROOT}/sql/11_verify_select_ai_hr.sql"
[[ -f "$sql_file" ]] || die "Missing SQL file: ${sql_file}"

if [[ "$action" == 'showsql' ]]; then
  printf '%s\n' 'Select AI HR verification: generated SQL only; no SQL will execute.'
else
  printf '%s\n' 'Select AI HR verification: generated SQL WILL execute as ADMIN.'
fi

sqlplus -L "admin/${ADMIN_PWD}@${ADB_SERVICE}" @"$sql_file" "$action"
