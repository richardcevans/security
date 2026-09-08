#!/bin/bash
# Shared environment checks for scripts that depend on .entra-id-data-grants.env.

require_entra_lab_env() {
  if [ "${ENTRA_ID_DATA_GRANTS_ENV:-}" = "1" ]; then
    return
  fi

  echo -e "${YELLOW}WARNING: The Entra ID data grants environment is not loaded.${NC}"
  echo -e "${YELLOW}Run this command from the entra-id-data-grants directory, then retry:${NC}"
  echo
  echo "  source ./.entra-id-data-grants.env"
  echo
  exit 1
}
