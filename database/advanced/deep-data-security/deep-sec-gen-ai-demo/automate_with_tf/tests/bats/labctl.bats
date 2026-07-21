#!/usr/bin/env bats

setup() {
  lab_root="${BATS_TEST_DIRNAME}/../.."
}

@test "status is read-only" {
  run env LAB_STATE_DIR="${BATS_TEST_TMPDIR}/.lab" bash "${lab_root}/bin/labctl" status
  [ "$status" -eq 0 ]
  [[ "$output" == *'Generated state: not created'* ]]
}

@test "database configure dry run delegates to all legacy database scripts" {
  run bash "${lab_root}/bin/labctl" --dry-run database configure
  [ "$status" -eq 0 ]
  [[ "$output" == *'01_enable_oci_iam.sh'* ]]
  [[ "$output" == *'02_create_hr_schema.sh'* ]]
  [[ "$output" == *'03_create_data_roles_and_grants.sh'* ]]
}

@test "identity configure dry run warns about coupled ADB setup" {
  run bash "${lab_root}/bin/labctl" --dry-run identity configure
  [ "$status" -eq 0 ]
  [[ "$output" == *'creates or reuses Autonomous AI Database'* ]]
  [[ "$output" == *'00_setup_adb.sh'* ]]
}

@test "all dry run stops before persona verification" {
  run bash "${lab_root}/bin/labctl" --dry-run all
  [ "$status" -eq 0 ]
  [[ "$output" == *'verify_db_setup.sh'* ]]
  [[ "$output" == *'obtain a fresh token'* ]]
}

@test "terraform apply requires explicit confirmation" {
  run bash "${lab_root}/bin/labctl" infra apply
  [ "$status" -ne 0 ]
  [[ "$output" == *'requires:'* ]]
}

@test "destroy rejects an unspecified cleanup scope" {
  run bash "${lab_root}/bin/labctl" destroy
  [ "$status" -ne 0 ]
  [[ "$output" == *'explicit cleanup action'* ]]
}

@test "legacy setup and cleanup symmetry guard passes" {
  run bash "${lab_root}/tests/offline/check_setup_cleanup_symmetry.sh"
  [ "$status" -eq 0 ]
}
