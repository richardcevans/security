#!/usr/bin/env bash
# Generate Select AI SQL as ADMIN; add --run to execute it as ADMIN.

set -Eeuo pipefail
action=showsql
[[ "${1:-}" == --run ]] && action=runsql
[[ -z "${1:-}" || "${1:-}" == --run ]] || { echo "Usage: $0 [--run]" >&2; exit 2; }
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${script_dir}/lab_common.sh"
load_adb_lab_environment
[[ -n "${ADMIN_PWD:-}" ]] || die 'ADMIN_PWD is missing from the ADB OCI IAM environment.'
printf 'Select AI as ADMIN; action=%s\n' "$action"
sqlplus -L "admin/${ADMIN_PWD}@${ADB_SERVICE}" @"${script_dir}/04_verify_select_ai_as_admin.sql" "$action"
