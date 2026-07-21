#!/usr/bin/env bash
# Enable or disable temporary Oracle Net client tracing for SQL*Plus.

set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${script_dir}/../lib/common.sh"

usage() {
  cat <<'EOF'
Usage: ./bin/sqlnet-client-trace.sh <enable|disable|status>

Uses the wallet's sqlnet.ora selected by TNS_ADMIN.  Enable saves one exact
backup under .lab/, writes client trace files under .lab/sqlnet-client-trace/,
and turns off ADR so Oracle Net uses that explicit directory.  Disable restores
the saved sqlnet.ora and removes only the saved backup.
EOF
}

load_legacy_environment

tns_admin=${TNS_ADMIN:?TNS_ADMIN is not set by the legacy lab environment}
sqlnet_file="${tns_admin}/sqlnet.ora"
backup_file="${LAB_STATE_DIR}/sqlnet.ora.before-client-trace"
trace_dir="${LAB_STATE_DIR}/sqlnet-client-trace"

test -f "$sqlnet_file" || die "Wallet sqlnet.ora not found: ${sqlnet_file}"

remove_trace_settings() {
  local input_file=$1
  local output_file=$2
  awk '
    /^[[:space:]]*(TRACE_LEVEL_CLIENT|TRACE_DIRECTORY_CLIENT|TRACE_FILE_CLIENT|TRACE_UNIQUE_CLIENT|TRACE_TIMESTAMP_CLIENT|TRACE_FILELEN_CLIENT|TRACE_FILENO_CLIENT|DIAG_ADR_ENABLED)[[:space:]]*=/ { next }
    { print }
  ' "$input_file" >"$output_file"
}

command=${1:-}
case "$command" in
  enable)
    mkdir -p "$LAB_STATE_DIR" "$trace_dir"
    if [[ ! -f "$backup_file" ]]; then
      cp -p "$sqlnet_file" "$backup_file"
    fi

    temporary_file=$(mktemp "${LAB_STATE_DIR}/sqlnet.ora.XXXXXX")
    trap 'rm -f "$temporary_file"' EXIT
    remove_trace_settings "$sqlnet_file" "$temporary_file"
    printf '%s\n' \
      '' \
      '# Temporary diagnostics managed by deep-sec-gen-ai-demo/bin/sqlnet-client-trace.sh' \
      'DIAG_ADR_ENABLED = OFF' \
      'TRACE_LEVEL_CLIENT = SUPPORT' \
      "TRACE_DIRECTORY_CLIENT = ${trace_dir}" \
      'TRACE_FILE_CLIENT = sqlplus_oci_iam.trc' \
      'TRACE_UNIQUE_CLIENT = ON' \
      'TRACE_TIMESTAMP_CLIENT = ON' \
      'TRACE_FILELEN_CLIENT = 10485760' \
      'TRACE_FILENO_CLIENT = 5' >>"$temporary_file"
    cp "$temporary_file" "$sqlnet_file"
    info "SQL*Plus Oracle Net tracing is enabled."
    info "Trace directory: ${trace_dir}"
    info "Backup:          ${backup_file}"
    info "Run the failing command once, then use: ./bin/sqlnet-client-trace.sh disable"
    ;;
  disable)
    test -f "$backup_file" || die "No lab-managed trace backup exists at ${backup_file}. Nothing was changed."
    cp -p "$backup_file" "$sqlnet_file"
    rm -f "$backup_file"
    info "Restored ${sqlnet_file}; SQL*Plus client tracing is disabled."
    info "Trace files remain in ${trace_dir} for inspection."
    ;;
  status)
    if [[ -f "$backup_file" ]]; then
      info "Client tracing is enabled by this lab."
      info "Trace directory: ${trace_dir}"
    else
      info "No lab-managed client trace is enabled."
    fi
    ;;
  help|--help|-h|'')
    usage
    ;;
  *)
    usage >&2
    die "Unknown command: ${command}"
    ;;
esac
