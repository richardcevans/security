#!/usr/bin/env bash
# Show the inherited, working ADB OCI IAM environment without changing OCI.

set -Eeuo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${script_dir}/lab_common.sh"
load_adb_lab_environment

printf 'ADB service : %s\n' "$ADB_SERVICE"
printf 'ADB OCID    : %s\n' "${ADB_OCID:-not set}"
printf 'Compartment : %s\n' "$(genai_compartment_id)"
printf 'OCI profile : %s\n' "${OCI_PROFILE_NAME:-${OCI_PROFILE:-${OCI_CLI_PROFILE:-DEFAULT}}}"
printf 'Environment : %s\n' "$ADB_IAM_ENV_FILE"
