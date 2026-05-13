#!/bin/bash
# Preflight checks for the OCI IAM data grants lab.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

export DB_SID="${DB_SID:-FREE}"
export PDB_NAME="${PDB_NAME:-FREEPDB1}"
export ORACLE_SID="$DB_SID"

status=0

ok() {
  echo -e "${CYAN}  OK: $*${NC}"
}

warn() {
  echo -e "${YELLOW}  WARN: $*${NC}"
}

fail() {
  echo -e "${RED}  FAIL: $*${NC}"
  status=1
}

check_command() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd found: $(command -v "$cmd")"
  else
    fail "$cmd not found on PATH"
  fi
}

check_port() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"; then
      warn "localhost port ${port} is already in use"
    else
      ok "localhost port ${port} appears available"
    fi
  elif command -v lsof >/dev/null 2>&1; then
    if lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      warn "localhost port ${port} is already in use"
    else
      ok "localhost port ${port} appears available"
    fi
  else
    warn "cannot check port ${port}; neither ss nor lsof is available"
  fi
}

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Preflight: OCI IAM Data Grants Lab                                    ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

echo -e "${GREEN}Environment${NC}"
echo -e "${CYAN}  DB_SID       = ${DB_SID}${NC}"
echo -e "${CYAN}  PDB_NAME     = ${PDB_NAME}${NC}"
echo -e "${CYAN}  ORACLE_SID   = ${ORACLE_SID}${NC}"
echo -e "${CYAN}  ORACLE_HOME  = ${ORACLE_HOME:-}${NC}"
echo -e "${CYAN}  ORACLE_BASE  = ${ORACLE_BASE:-}${NC}"
echo -e "${CYAN}  TNS_ADMIN    = ${TNS_ADMIN:-not set}${NC}"
echo

[ -n "${ORACLE_HOME:-}" ] || fail "ORACLE_HOME is not set"
[ -n "${ORACLE_BASE:-}" ] || warn "ORACLE_BASE is not set"
[ -d "${ORACLE_HOME:-/missing}" ] && ok "ORACLE_HOME directory exists" || fail "ORACLE_HOME directory does not exist"

echo
echo -e "${GREEN}Commands${NC}"
check_command sqlplus
check_command lsnrctl
check_command orapki
check_command oci
check_command python3

echo
echo -e "${GREEN}OCI CLI${NC}"
if [ -f "${OCI_CONFIG_FILE:-$HOME/.oci/config}" ]; then
  ok "OCI CLI config found: ${OCI_CONFIG_FILE:-$HOME/.oci/config}"
else
  fail "OCI CLI config not found. Run: oci setup config"
fi

if oci iam region list >/dev/null 2>&1; then
  ok "OCI CLI can call OCI"
else
  fail "OCI CLI could not call OCI with the current profile/config"
fi

echo
echo -e "${GREEN}Database Local SYSDBA${NC}"
if sqlplus -s / as sysdba <<EOF >/tmp/oci_iam_lab_preflight_db.out 2>&1
set pages 100
set lines 160
whenever sqlerror exit sql.sqlcode
prompt INSTANCE
SELECT sys_context('USERENV','INSTANCE_NAME') AS instance_name FROM dual;
prompt VERSION
SELECT banner_full FROM v\$version;
prompt PDBS
SELECT name, open_mode FROM v\$pdbs ORDER BY name;
exit;
EOF
then
  ok "sqlplus / as sysdba works for ORACLE_SID=${ORACLE_SID}"
  sed 's/^/    /' /tmp/oci_iam_lab_preflight_db.out
else
  fail "sqlplus / as sysdba failed for ORACLE_SID=${ORACLE_SID}"
  sed 's/^/    /' /tmp/oci_iam_lab_preflight_db.out || true
fi

echo
echo -e "${GREEN}SQL Patch Inventory${NC}"
if sqlplus -s / as sysdba <<EOF >/tmp/oci_iam_lab_preflight_patch.out 2>&1
set pages 100
set lines 180
col description format a90
SELECT patch_id, action, status, action_time, description
  FROM dba_registry_sqlpatch
 ORDER BY action_time DESC
 FETCH FIRST 10 ROWS ONLY;
exit;
EOF
then
  sed 's/^/    /' /tmp/oci_iam_lab_preflight_patch.out
else
  warn "could not query dba_registry_sqlpatch"
fi

if [ -x "${ORACLE_HOME:-}/OPatch/opatch" ]; then
  echo
  echo -e "${GREEN}OPatch Inventory${NC}"
  "${ORACLE_HOME}/OPatch/opatch" lspatches 2>/dev/null | sed 's/^/    /' || warn "opatch lspatches failed"
fi

echo
echo -e "${GREEN}Listener${NC}"
if lsnrctl status >/tmp/oci_iam_lab_preflight_listener.out 2>&1; then
  ok "listener status command completed"
  grep -E "PORT=1521|PORT=2484|Service \"${PDB_NAME,,}\"|Service \"${PDB_NAME}\"" /tmp/oci_iam_lab_preflight_listener.out | sed 's/^/    /' || warn "expected ports/services not currently visible"
else
  warn "listener status failed"
  sed 's/^/    /' /tmp/oci_iam_lab_preflight_listener.out || true
fi

echo
echo -e "${GREEN}OAuth Callback Ports${NC}"
check_port 8888
check_port 8889
check_port 8890

echo
if [ "$status" -eq 0 ]; then
  echo -e "${GREEN}Preflight completed without blocking failures.${NC}"
else
  echo -e "${RED}Preflight found blocking failures. Fix them before continuing.${NC}"
fi
echo

exit "$status"
