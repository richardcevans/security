#!/usr/bin/env bash
# Show the ten newest Unified Audit Trail entries for HR.EMPLOYEES.

set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${script_dir}/lab_common.sh"
load_adb_lab_environment

command -v sqlplus >/dev/null 2>&1 || die 'sqlplus is required.'
[[ -n "${ADMIN_PWD:-}" ]] || die 'ADMIN_PWD is not set. Source the ADB OCI IAM environment first.'

printf '%s\n' '============================================================================'
printf '%s\n' 'Last 10 Unified Audit Trail rows for HR.EMPLOYEES'
printf '%s\n' '============================================================================'
printf '%s\n' 'Read-only report: timestamp (UTC), command, database user, client program,'
printf '%s\n' 'and Deep Data Security end user. A dash means no end-user context was recorded.'
printf '\nSQL*Plus command:\n'
show_cmd sqlplus -L -s "admin/<hidden>@${ADB_SERVICE}"
printf '\n'

sqlplus -L -s "admin/${ADMIN_PWD}@${ADB_SERVICE}" @"${script_dir}/07_show_hr_employees_audit_trail.sql"
