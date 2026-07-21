#!/usr/bin/env bash
# Compatibility cleanup wrapper. It requires explicit legacy cleanup intent.
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${script_dir}/../lib/common.sh"

cleanup_args=()
has_cleanup_action=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      cleanup_args+=(--DELETE)
      ;;
    --delete-adb|--delete-db-objects|--delete-iam-users|--delete-iam-groups|--delete-iam-apps|--delete-all-lab-apps|--delete-local-files|--remove-all)
      has_cleanup_action=true
      cleanup_args+=("$1")
      ;;
    *) cleanup_args+=("$1") ;;
  esac
  shift
done

"$has_cleanup_action" || die 'Destroy requires an explicit cleanup action, for example --delete-db-objects.'
run_legacy_script 07_cleanup_adb_lab.sh "${cleanup_args[@]}"
