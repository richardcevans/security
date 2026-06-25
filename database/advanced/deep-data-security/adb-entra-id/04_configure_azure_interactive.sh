#!/bin/bash
# Backward-compatible wrapper. The lab now uses the same headless OAuth pattern
# as adb-oci-iam, printing a localhost URL and storing a token for SQL*Plus.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ "$#" -eq 0 ]; then
  exec "${SCRIPT_DIR}/04_get_entra_oauth_token.sh" --headless
fi
exec "${SCRIPT_DIR}/04_get_entra_oauth_token.sh" "$@"
