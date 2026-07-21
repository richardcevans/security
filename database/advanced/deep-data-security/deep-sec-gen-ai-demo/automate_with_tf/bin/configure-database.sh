#!/usr/bin/env bash
# Compatibility wrapper around the proven direct-login database configuration.
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${script_dir}/../lib/common.sh"

if [[ $# -ne 0 ]]; then
  die 'Usage: ./bin/configure-database.sh'
fi

info 'Database configuration delegates to the existing direct-login lab.'
load_legacy_environment
run_legacy_script 01_enable_oci_iam.sh
run_legacy_script 02_create_hr_schema.sh
run_legacy_script 03_create_data_roles_and_grants.sh
