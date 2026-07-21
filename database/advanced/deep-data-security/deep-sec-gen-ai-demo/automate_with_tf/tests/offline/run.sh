#!/usr/bin/env bash
set -Eeuo pipefail

test_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
lab_root=$(cd "${test_dir}/../.." && pwd)

while IFS= read -r -d '' script; do
  bash -n "$script"
done < <(find "$lab_root/bin" "$lab_root/lib" "$test_dir" -type f -name '*.sh' -print0)

terraform -chdir="${lab_root}/terraform" fmt -check -recursive

bash "${test_dir}/check_setup_cleanup_symmetry.sh"

output=$(bash "${lab_root}/bin/labctl" status)
printf '%s\n' "$output" | grep -Fq 'Provisioned OCI resources: none managed by this lab yet'

if bash "${lab_root}/bin/labctl" mcp >/dev/null 2>&1; then
  printf 'Expected unimplemented MCP command to fail.\n' >&2
  exit 1
fi

dry_run_output=$(bash "${lab_root}/bin/labctl" --dry-run database configure)
printf '%s\n' "$dry_run_output" | grep -Fq '01_enable_oci_iam.sh'
printf '%s\n' "$dry_run_output" | grep -Fq '03_create_data_roles_and_grants.sh'

all_dry_run_output=$(bash "${lab_root}/bin/labctl" --dry-run all)
printf '%s\n' "$all_dry_run_output" | grep -Fq '00_setup_adb.sh'
printf '%s\n' "$all_dry_run_output" | grep -Fq 'verify_db_setup.sh'

state_dir=$(mktemp -d)
trap 'rm -rf "$state_dir"' EXIT
LAB_STATE_DIR="$state_dir/.lab" bash "${lab_root}/bin/labctl" manifest init
LAB_STATE_DIR="$state_dir/.lab" bash "${lab_root}/bin/labctl" manifest validate

if command -v bats >/dev/null 2>&1; then
  bats "${lab_root}/tests/bats"
else
  printf 'Bats checks: SKIPPED (bats is not installed)\n'
fi

printf 'Offline scaffold checks: PASS\n'
