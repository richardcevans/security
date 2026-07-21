#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${script_dir}/../lib/common.sh"

info 'Lab: deep-sec-gen-ai-demo'
info 'Phase: 1 — shell foundations and regression checks'
info "Legacy source: ${LEGACY_LAB_ROOT}"

if [[ -d "${LAB_STATE_DIR}" ]]; then
  info "Generated state: present at ${LAB_STATE_DIR}"
else
  info 'Generated state: not created'
fi

attachment_file="${LAB_STATE_DIR}/attached-adb.env"
if [[ -f "$attachment_file" ]]; then
  # shellcheck disable=SC1090 # Written only by attach-adb-oci-iam.sh.
  source "$attachment_file"
  info "Attached ADB: ${ATTACHED_DB_NAME} (${ATTACHED_ADB_SERVICE})"
  info "Attachment time: ${ATTACHED_AT_UTC}"
  info 'Provisioned OCI resources: none managed by this lab yet'
else
  info 'Attached ADB: none'
  info 'Provisioned OCI resources: none managed by this lab yet'
fi
