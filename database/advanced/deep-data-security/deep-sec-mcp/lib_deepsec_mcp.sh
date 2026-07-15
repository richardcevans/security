#!/bin/bash
# Shared helpers for the DeepSec MCP OCI IAM lab.

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  echo "ERROR: This lab requires Bash 4.x or later." >&2
  exit 1
fi

require_adb_env() {
  for var in DB_NAME ADB_SERVICE ADMIN_PWD WALLET_DIR TNS_ADMIN; do
    if [ -z "${!var:-}" ]; then
      echo "ERROR: ${var} is not set." >&2
      echo "For the automated ADB-S path, run ./setup_adbs_oci_iam.sh <compartment-name-or-ocid> and source ./.deep-sec-mcp.env." >&2
      echo "For a manually configured database, edit .deep-sec-mcp.env and set DB_NAME, ADB_SERVICE, ADMIN_PWD, WALLET_DIR, and TNS_ADMIN." >&2
      exit 1
    fi
  done
}

show_cmd() {
  printf '  $'
  printf ' %q' "$@"
  printf '\n'
}

require_sqlplus() {
  if ! command -v sqlplus >/dev/null 2>&1; then
    echo "ERROR: sqlplus is not available in PATH. This lab requires SQL*Plus." >&2
    exit 1
  fi
}

require_wallet_files() {
  local missing=false

  echo "Wallet preflight:"
  echo "  TNS_ADMIN  = ${TNS_ADMIN}"
  echo "  WALLET_DIR = ${WALLET_DIR}"

  for file in tnsnames.ora sqlnet.ora cwallet.sso ewallet.p12; do
    if [ -f "${TNS_ADMIN}/${file}" ]; then
      echo "  found ${TNS_ADMIN}/${file}"
    else
      echo "  missing ${TNS_ADMIN}/${file}" >&2
      missing=true
    fi
  done

  if grep -q 'DIRECTORY="?/network/admin"' "${TNS_ADMIN}/sqlnet.ora" 2>/dev/null; then
    echo "ERROR: ${TNS_ADMIN}/sqlnet.ora still points to ?/network/admin." >&2
    echo "Run DOWNLOAD_WALLET=1 ./00_configure_lab_env.sh again so the wallet directory is rewritten to TNS_ADMIN." >&2
    exit 1
  fi

  if [ "$missing" = true ]; then
    echo "ERROR: The ADB wallet is incomplete." >&2
    echo "For the automated ADB-S path, rerun ./setup_adbs_oci_iam.sh <compartment-name-or-ocid> and source ./.deep-sec-mcp.env." >&2
    echo "For a manually configured database, rerun DOWNLOAD_WALLET=1 ./00_configure_lab_env.sh or install the wallet manually." >&2
    exit 1
  fi

  if ! grep -qi "^[[:space:]]*${ADB_SERVICE}[[:space:]]*=" "${TNS_ADMIN}/tnsnames.ora" 2>/dev/null; then
    echo "ERROR: ${TNS_ADMIN}/tnsnames.ora does not contain the service alias ${ADB_SERVICE}." >&2
    echo "This usually means .deep-sec-mcp.env contains placeholder or stale values." >&2
    echo "For the automated ADB-S path, rerun ./setup_adbs_oci_iam.sh <compartment-name-or-ocid> and source ./.deep-sec-mcp.env." >&2
    exit 1
  fi
}

admin_sqlplus() {
  require_sqlplus
  require_wallet_files
  sqlplus -L -s "admin/${ADMIN_PWD}@${ADB_SERVICE}"
}
