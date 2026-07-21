#!/usr/bin/env bash
# Shared helpers for the direct, flat GenAI extension scripts.

set -Eeuo pipefail

LAB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ADB_LAB_DIR="${LAB_DIR}/../adb-oci-iam"
ADB_IAM_ENV_FILE="${ADB_IAM_ENV_FILE:-${ADB_LAB_DIR}/.adb-oci-iam.env}"
GREEN='\033[0;32m'
NC='\033[0m'

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

show_cmd() {
  printf '  $'
  printf ' %q' "$@"
  printf '\n'
}

green_banner() {
  printf '%b\n' "${GREEN}============================================================================${NC}"
  printf '%b\n' "${GREEN}$1${NC}"
  printf '%b\n' "${GREEN}============================================================================${NC}"
}

load_adb_lab_environment() {
  [[ -f "$ADB_IAM_ENV_FILE" ]] || die "ADB OCI IAM environment file not found: ${ADB_IAM_ENV_FILE}"
  # shellcheck disable=SC1090
  source "$ADB_IAM_ENV_FILE"
  [[ -n "${ADB_SERVICE:-}" && -n "${TNS_ADMIN:-}" ]] || die 'The ADB OCI IAM environment lacks ADB_SERVICE or TNS_ADMIN.'
}

load_oci_profile() {
  # shellcheck disable=SC1091
  source "${ADB_LAB_DIR}/lib_oci_profile.sh"
  command -v oci >/dev/null 2>&1 || die 'OCI CLI is required.'
}

genai_compartment_id() {
  [[ -n "${ROOT_COMP_ID:-}" ]] || die 'ROOT_COMP_ID is not set in the ADB OCI IAM environment.'
  printf '%s' "$ROOT_COMP_ID"
}
