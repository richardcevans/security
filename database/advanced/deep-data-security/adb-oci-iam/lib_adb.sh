#!/bin/bash
# Shared helpers for the ADB OCI IAM lab.

require_adb_env() {
  for var in DB_NAME ADB_OCID ADB_SERVICE ADMIN_PWD WALLET_DIR TNS_ADMIN; do
    if [ -z "${!var:-}" ]; then
      echo "ERROR: ${var} is not set. Run ./00_setup_adb.sh and source ./.adb-oci-iam.env first." >&2
      exit 1
    fi
  done
}

admin_sqlplus() {
  sqlplus -L -s "admin/${ADMIN_PWD}@${ADB_SERVICE}"
}
