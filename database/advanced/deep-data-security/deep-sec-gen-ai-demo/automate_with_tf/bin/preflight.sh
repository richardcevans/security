#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${script_dir}/../lib/common.sh"

info 'Preflight: deep-sec-gen-ai-demo (Phase 1)'
require_command bash
require_command python3

if command -v oci >/dev/null 2>&1; then
  info 'OCI CLI: found'
else
  info 'OCI CLI: not found (required before OCI provisioning phases)'
fi

if client=$(sql_client); then
  info "Database client: ${client}"
else
  info 'Database client: not found (required before database configuration phases)'
fi

test -d "${LEGACY_LAB_ROOT}" || die "Direct-login source lab missing: ${LEGACY_LAB_ROOT}"
test -f "${LEGACY_LAB_ROOT}/00_setup_adb.sh" || die 'Legacy setup command is missing.'
info 'Legacy source lab: found'
info 'Preflight: PASS'
