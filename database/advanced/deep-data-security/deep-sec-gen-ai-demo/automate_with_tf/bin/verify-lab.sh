#!/usr/bin/env bash
# Compatibility verification wrapper; it does not acquire OAuth tokens.
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${script_dir}/../lib/common.sh"

persona='admin'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --persona)
      [[ $# -ge 2 ]] || die 'Missing value for --persona.'
      persona=$2
      shift 2
      ;;
    *) die "Unknown verify option: $1" ;;
  esac
done

load_legacy_environment

case "$persona" in
  admin) run_legacy_script verify_db_setup.sh ;;
  marvin) run_legacy_script 05_verify_as_marvin.sh ;;
  emma) run_legacy_script 06_verify_as_emma.sh ;;
  richard) exec "${script_dir}/verify-as-richard.sh" ;;
  *) die 'Persona must be admin, richard, marvin, or emma.' ;;
esac
