#!/bin/bash
# Remove local OAuth2 token material created by this lab.
# This does not delete OCI IAM objects or database configuration.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TOKEN_DIR="${OCI_TOKEN_DIR:-$HOME/.oci/oci-iam-data-grants}"
TOKEN_FILE="${TOKEN_DIR}/token"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Clear Local OCI IAM OAuth2 Tokens                                     ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}Token directory:${NC} ${TOKEN_DIR}"
echo

removed=0

if [ -f "$TOKEN_FILE" ]; then
  rm -f "$TOKEN_FILE"
  echo -e "${CYAN}Removed token file:${NC} ${TOKEN_FILE}"
  removed=1
else
  echo -e "${YELLOW}Token file not found:${NC} ${TOKEN_FILE}"
fi

if [ -d "$TOKEN_DIR" ]; then
  if rmdir "$TOKEN_DIR" 2>/dev/null; then
    echo -e "${CYAN}Removed empty token directory:${NC} ${TOKEN_DIR}"
    removed=1
  else
    echo -e "${YELLOW}Token directory still exists because it is not empty:${NC} ${TOKEN_DIR}"
  fi
else
  echo -e "${YELLOW}Token directory not found:${NC} ${TOKEN_DIR}"
fi

echo
echo -e "${YELLOW}This script cannot unset variables in your parent shell.${NC}"
echo "To clear sensitive exported values from this terminal, run:"
echo
echo "  unset OCI_CLIENT_SECRET OCI_DB_CLIENT_SECRET OCI_REDIRECT_URI OCI_REDIRECT_URIS"
echo

if [ "$removed" -eq 1 ]; then
  echo -e "${GREEN}Local token cleanup completed.${NC}"
else
  echo -e "${YELLOW}No local token files were found.${NC}"
fi

