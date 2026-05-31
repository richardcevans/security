#!/bin/bash
# Delete the ADB-S instance created for the DEAL lab.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deal-adb.env"
CONFIRM_DELETE=0
DELETE_WALLET=0

usage() {
  cat <<'EOF'
Usage:
  ./12_delete_adb.sh --confirm-delete-adb [--delete-wallet]

Deletes the Autonomous Database identified by ./.deal-adb.env.

Options:
  --confirm-delete-adb   Required. Confirms that you want to delete the ADB-S instance.
  --delete-wallet        Also delete the local wallet directory recorded in ./.deal-adb.env.
  -h, --help             Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --confirm-delete-adb)
      CONFIRM_DELETE=1
      ;;
    --delete-wallet)
      DELETE_WALLET=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo -e "${RED}ERROR: Unknown argument: $1${NC}" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [ "$CONFIRM_DELETE" != "1" ]; then
  echo -e "${RED}ERROR: Refusing to delete ADB without --confirm-delete-adb.${NC}" >&2
  usage >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo -e "${RED}ERROR: ${ENV_FILE} not found. Run ./00_setup_adb.sh first or set ADB_OCID manually.${NC}" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

if [ -z "${ADB_OCID:-}" ]; then
  echo -e "${RED}ERROR: ADB_OCID is not set in ${ENV_FILE}.${NC}" >&2
  exit 1
fi

oci_global_args=()
[ -n "${OCI_CONFIG_FILE:-${OCI_CLI_CONFIG_FILE:-}}" ] && oci_global_args+=(--config-file "${OCI_CONFIG_FILE:-${OCI_CLI_CONFIG_FILE:-}}")
[ -n "${OCI_PROFILE:-${OCI_CLI_PROFILE:-}}" ] && oci_global_args+=(--profile "${OCI_PROFILE:-${OCI_CLI_PROFILE:-}}")

if ! command -v oci >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI is not available.${NC}" >&2
  exit 1
fi

echo
echo -e "${YELLOW}Deleting Autonomous Database:${NC}"
echo "  DB_NAME  = ${DB_NAME:-unknown}"
echo "  ADB_OCID = ${ADB_OCID}"
echo

oci db autonomous-database delete \
  --autonomous-database-id "$ADB_OCID" \
  --force \
  --wait-for-state TERMINATED \
  "${oci_global_args[@]}"

echo
echo -e "${GREEN}ADB delete request completed.${NC}"

if [ "$DELETE_WALLET" = "1" ]; then
  if [ -n "${WALLET_DIR:-}" ] && [ -d "$WALLET_DIR" ]; then
    case "$WALLET_DIR" in
      "$HOME"/adb_wallet/*)
        rm -rf "$WALLET_DIR"
        echo -e "${GREEN}Deleted wallet directory: ${WALLET_DIR}${NC}"
        ;;
      *)
        echo -e "${YELLOW}Not deleting wallet outside \$HOME/adb_wallet: ${WALLET_DIR}${NC}"
        ;;
    esac
  else
    echo -e "${YELLOW}Wallet directory not found or not set.${NC}"
  fi
else
  echo -e "${YELLOW}Wallet directory kept. Rerun with --delete-wallet to remove it.${NC}"
fi

echo
