#!/usr/bin/env bash
# Static regression guard for the existing numbered direct-login lab flow.
set -Eeuo pipefail

lab_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

while IFS= read -r -d '' script; do
  bash -n "$script"
done < <(find "$lab_dir" -type f -name '*.sh' -print0)

require_text() {
  local file=$1
  local expected=$2
  if ! grep -Fq -- "$expected" "$file"; then
    printf 'Missing legacy contract marker in %s: %s\n' "$file" "$expected" >&2
    exit 1
  fi
}

require_text "${lab_dir}/00_setup_adb.sh" 'oci db autonomous-database create'
require_text "${lab_dir}/00_setup_adb.sh" 'oci db autonomous-database generate-wallet'
require_text "${lab_dir}/01_enable_oci_iam.sh" 'ENABLE_EXTERNAL_AUTHENTICATION'
require_text "${lab_dir}/02_create_hr_schema.sh" 'CREATE TABLE hr.employees'
require_text "${lab_dir}/03_create_data_roles_and_grants.sh" 'CREATE OR REPLACE DATA ROLE hrapp_employees'
require_text "${lab_dir}/04_get_iam_oauth_token.sh" 'code_challenge_method'
require_text "${lab_dir}/05_verify_as_marvin.sh" "HRAPP_MANAGERS"
require_text "${lab_dir}/06_verify_as_emma.sh" "HRAPP_EMPLOYEES"
require_text "${lab_dir}/07_cleanup_adb_lab.sh" '--delete-db-objects'

printf 'Legacy command contract: PASS\n'
