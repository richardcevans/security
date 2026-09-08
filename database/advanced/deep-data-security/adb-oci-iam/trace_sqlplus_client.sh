#!/bin/bash
# Enable or disable temporary Oracle Net client tracing for this lab's SQL*Plus.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${SCRIPT_DIR}/lib_adb.sh"
require_adb_env

usage() {
  cat <<'EOF'
Usage: ./trace_sqlplus_client.sh <enable|disable|status>

Enable saves the current wallet sqlnet.ora under .oci-iam-setup/, writes Oracle
Net trace files to .oci-iam-setup/sqlnet-client-trace/, and disables ADR so the
specified trace directory is used. Disable restores the exact saved sqlnet.ora.
EOF
}

setup_dir="${SCRIPT_DIR}/.oci-iam-setup"
sqlnet_file="${TNS_ADMIN}/sqlnet.ora"
backup_file="${setup_dir}/sqlnet.ora.before-client-trace"
trace_dir="${setup_dir}/sqlnet-client-trace"

test -f "$sqlnet_file" || {
  echo "ERROR: Wallet sqlnet.ora not found: ${sqlnet_file}" >&2
  exit 1
}

remove_trace_settings() {
  local input_file=$1
  local output_file=$2
  awk '
    /^[[:space:]]*(TRACE_LEVEL_CLIENT|TRACE_DIRECTORY_CLIENT|TRACE_FILE_CLIENT|TRACE_UNIQUE_CLIENT|TRACE_TIMESTAMP_CLIENT|TRACE_FILELEN_CLIENT|TRACE_FILENO_CLIENT|DIAG_ADR_ENABLED)[[:space:]]*=/ { next }
    { print }
  ' "$input_file" >"$output_file"
}

case "${1:-}" in
  enable)
    mkdir -p "$setup_dir" "$trace_dir"
    if [[ ! -f "$backup_file" ]]; then
      cp -p "$sqlnet_file" "$backup_file"
    fi

    temporary_file=$(mktemp "${setup_dir}/sqlnet.ora.XXXXXX")
    trap 'rm -f "$temporary_file"' EXIT
    remove_trace_settings "$sqlnet_file" "$temporary_file"
    printf '%s\n' \
      '' \
      '# Temporary diagnostics managed by trace_sqlplus_client.sh' \
      'DIAG_ADR_ENABLED = OFF' \
      'TRACE_LEVEL_CLIENT = SUPPORT' \
      "TRACE_DIRECTORY_CLIENT = ${trace_dir}" \
      'TRACE_FILE_CLIENT = sqlplus_oci_iam.trc' \
      'TRACE_UNIQUE_CLIENT = ON' \
      'TRACE_TIMESTAMP_CLIENT = ON' \
      'TRACE_FILELEN_CLIENT = 10485760' \
      'TRACE_FILENO_CLIENT = 5' >>"$temporary_file"
    cp "$temporary_file" "$sqlnet_file"

    echo "SQL*Plus Oracle Net tracing is enabled."
    echo "Trace directory: ${trace_dir}"
    echo "Backup:          ${backup_file}"
    echo "Run the failing connection once, then run: ./trace_sqlplus_client.sh disable"
    ;;
  disable)
    if [[ ! -f "$backup_file" ]]; then
      echo "ERROR: No lab-managed trace backup exists at ${backup_file}; nothing changed." >&2
      exit 1
    fi
    cp -p "$backup_file" "$sqlnet_file"
    rm -f "$backup_file"
    echo "Restored ${sqlnet_file}; SQL*Plus client tracing is disabled."
    echo "Trace files remain in ${trace_dir}."
    ;;
  status)
    if [[ -f "$backup_file" ]]; then
      echo "Client tracing is enabled by this lab."
      echo "Trace directory: ${trace_dir}"
    else
      echo "No lab-managed client trace is enabled."
    fi
    ;;
  help|--help|-h|'')
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
