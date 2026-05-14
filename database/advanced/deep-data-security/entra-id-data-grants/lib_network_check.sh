#!/bin/bash
# Shared network checks for scripts that use the hrdb TNS alias.

check_hrdb_alias() {
  if ! command -v tnsping >/dev/null 2>&1; then
    echo -e "${RED}ERROR: tnsping is not on PATH.${NC}"
    echo -e "${YELLOW}Make sure ORACLE_HOME is set and Oracle client binaries are on PATH.${NC}"
    exit 1
  fi

  if tnsping hrdb >/tmp/entra_hrdb_tnsping.out 2>&1; then
    return
  fi

  echo -e "${RED}ERROR: Cannot resolve TNS alias hrdb.${NC}"
  echo -e "${YELLOW}Run the network configuration step before connecting:${NC}"
  echo
  echo "  source ./.entra-id-data-grants.env"
  echo "  ./02_configure_network.sh"
  echo
  echo -e "${YELLOW}If TNS_ADMIN is set, SQLPlus may be reading tnsnames.ora from another directory.${NC}"
  echo "  TNS_ADMIN=${TNS_ADMIN:-not set}"
  echo
  echo -e "${YELLOW}tnsping output:${NC}"
  sed 's/^/  /' /tmp/entra_hrdb_tnsping.out
  exit 1
}
