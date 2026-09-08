#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/../../../../lib_oci_profile.sh"

usage() {
  cat <<'USAGE'
Usage:
  create-mcp-server.sh \
    --compartment-id <compartment_ocid> \
    --connection-id <database_tools_connection_ocid> \
    --display-name <mcp_server_name> \
    --domain-id <identity_domain_ocid>

This script is a hook for the OCI CLI path documented by OCI Database Tools.
Run it after the Database Tools connection and identity-domain values exist.
USAGE
}

COMPARTMENT_ID=""
CONNECTION_ID=""
DISPLAY_NAME=""
DOMAIN_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compartment-id)
      COMPARTMENT_ID="${2:-}"
      shift 2
      ;;
    --connection-id)
      CONNECTION_ID="${2:-}"
      shift 2
      ;;
    --display-name)
      DISPLAY_NAME="${2:-}"
      shift 2
      ;;
    --domain-id)
      DOMAIN_ID="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${COMPARTMENT_ID}" || -z "${CONNECTION_ID}" || -z "${DISPLAY_NAME}" || -z "${DOMAIN_ID}" ]]; then
  usage
  exit 1
fi

oci_with_profile dbtools mcp-server create-mcp-server-default \
  --compartment-id "${COMPARTMENT_ID}" \
  --connection-id "${CONNECTION_ID}" \
  --display-name "${DISPLAY_NAME}" \
  --domain-id "${DOMAIN_ID}"
