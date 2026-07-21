#!/usr/bin/env bash
# Use the existing adb-oci-iam OAuth token as its current OCI IAM user.

set -Eeuo pipefail
action=showsql
[[ "${1:-}" == --run ]] && action=runsql
[[ -z "${1:-}" || "${1:-}" == --run ]] || { echo "Usage: $0 [--run]" >&2; exit 2; }
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${script_dir}/lab_common.sh"
load_adb_lab_environment
# shellcheck disable=SC1091
source "${ADB_LAB_DIR}/lib_token_check.sh"
command -v sqlplus >/dev/null 2>&1 || die 'sqlplus is required.'
check_current_oauth_token
printf 'Select AI as the current OCI IAM token user; action=%s\n' "$action"
sqlplus -L -s "/@${ADB_SERVICE}" @"${script_dir}/05_verify_select_ai_as_current_user.sql" "$action"
