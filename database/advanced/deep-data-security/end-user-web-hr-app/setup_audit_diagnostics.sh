#!/usr/bin/env bash
set -euo pipefail

TNS_ALIAS="${WEB_HR_TNS_ALIAS:-freepdb1}"
DBA_CONNECT="${WEB_HR_DBA_CONNECT:-sys/Oracle123@${TNS_ALIAS} as sysdba}"

usage() {
  cat <<'EOF'
Usage:
  ./setup_audit_diagnostics.sh [options]

Options:
  --tns-alias <alias>
      Target database service alias. Default: WEB_HR_TNS_ALIAS or freepdb1.

  --dba-connect <connect-string>
      SQL*Plus DBA connection string. Default: sys/Oracle123@<alias> as sysdba.

  -h, --help
      Show this help.

Creates or unlocks deepsec_admin with password Oracle123 and grants the
privileges needed by the End User Web HR App audit panel.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tns-alias)
      TNS_ALIAS="${2:?--tns-alias requires a value}"
      DBA_CONNECT="sys/Oracle123@${TNS_ALIAS} as sysdba"
      shift 2
      ;;
    --dba-connect)
      DBA_CONNECT="${2:?--dba-connect requires a value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v sqlplus >/dev/null 2>&1; then
  echo "ERROR: sqlplus was not found on PATH." >&2
  exit 1
fi

echo
echo "Configuring audit diagnostics user"
echo "  TNS alias   = ${TNS_ALIAS}"
echo "  DBA connect = ${DBA_CONNECT}"
echo

sqlplus -s "$DBA_CONNECT" <<SQL
SET ECHO OFF FEEDBACK ON VERIFY OFF HEADING ON PAGESIZE 200 LINESIZE 200 SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
  l_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_count FROM dba_users WHERE username = 'DEEPSEC_ADMIN';
  IF l_count = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER deepsec_admin IDENTIFIED BY Oracle123';
    DBMS_OUTPUT.PUT_LINE('Created deepsec_admin with password Oracle123.');
  ELSE
    EXECUTE IMMEDIATE 'ALTER USER deepsec_admin IDENTIFIED BY Oracle123 ACCOUNT UNLOCK';
    DBMS_OUTPUT.PUT_LINE('Reset and unlocked deepsec_admin with password Oracle123.');
  END IF;
END;
/

GRANT CREATE SESSION TO deepsec_admin;
GRANT AUDIT_VIEWER TO deepsec_admin;

PROMPT
PROMPT Audit diagnostics user:
SELECT username, account_status
  FROM dba_users
 WHERE username = 'DEEPSEC_ADMIN';

EXIT
SQL

cat <<EOF

Audit diagnostics are ready.
The web app will use deepsec_admin/Oracle123 by default.

Verify:
  sqlplus deepsec_admin/Oracle123@${TNS_ALIAS}
EOF
