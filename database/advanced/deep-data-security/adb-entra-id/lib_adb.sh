#!/bin/bash
# Shared helpers for the ADB Microsoft Entra ID lab.

require_adb_entra_env() {
  for var in DB_NAME ADB_OCID ADB_SERVICE ADMIN_PWD WALLET_DIR TNS_ADMIN TENANT_ID APP_ID APP_ID_URI CLIENT_ID MARVIN_UPN; do
    if [ -z "${!var:-}" ]; then
      echo "ERROR: ${var} is not set. Run ./00_setup_adb_entra_id.sh and source ./.adb-entra-id.env first." >&2
      exit 1
    fi
  done
}

admin_sqlplus() {
  sqlplus -L -s "admin/${ADMIN_PWD}@${ADB_SERVICE}"
}
