#!/usr/bin/env bash
# Disable and drop only the lab Unified Auditing policy for HR.EMPLOYEES.

set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${script_dir}/lab_common.sh"
load_adb_lab_environment

command -v sqlplus >/dev/null 2>&1 || die 'sqlplus is required.'
[[ -n "${ADMIN_PWD:-}" ]] || die 'ADMIN_PWD is not set. Source the ADB OCI IAM environment first.'

green_banner 'Disable Unified Auditing for HR.EMPLOYEES'
printf '%s\n' 'This removes only the DEEPSEC_HR_EMPLOYEES_AUDIT policy.'
printf '%s\n' 'Existing Unified Audit Trail records are retained.'
printf '\nSQL*Plus command:\n'
show_cmd sqlplus -L -s "admin/<hidden>@${ADB_SERVICE}"
printf '\n'

sqlplus -L -s "admin/${ADMIN_PWD}@${ADB_SERVICE}" @"${script_dir}/99_disable_hr_employees_audit.sql"
