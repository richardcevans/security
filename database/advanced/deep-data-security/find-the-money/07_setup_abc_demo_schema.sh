#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ABC_SQL="${SCRIPT_DIR}/sql/abc_setup.sql"
FIND_MONEY_ENV="${FIND_MONEY_ENV:-${SCRIPT_DIR}/.find-the-money.env}"

if [ -f "$FIND_MONEY_ENV" ]; then
  # shellcheck disable=SC1090
  source "$FIND_MONEY_ENV"
fi

if [ ! -f "$ABC_SQL" ]; then
  echo "ERROR: Missing ${ABC_SQL}"
  exit 1
fi

DB_SID="${DB_SID:-FREE}"
PDB_NAME="${PDB_NAME:-FREEPDB1}"
ORACLE_HOME="${ORACLE_HOME:-/opt/oracle/product/26ai/dbhome_1}"
FIND_MONEY_APP_DB_USER="${FIND_MONEY_APP_DB_USER:-find_money_app_user}"

if [ -x "$ORACLE_HOME/bin/sqlplus" ]; then
  export ORACLE_HOME
  export PATH="$ORACLE_HOME/bin:$PATH"
  export LD_LIBRARY_PATH="$ORACLE_HOME/lib:${LD_LIBRARY_PATH:-}"
fi
export ORACLE_SID="$DB_SID"

echo "Loading ABC demo schema into ${PDB_NAME} from ${ABC_SQL}"
echo "This drops and recreates only ABC lab users listed in sql/abc_setup.sql."

sqlplus -s / as sysdba <<EOF
set echo on
set serveroutput on
set lines 180
set pages 9999
whenever sqlerror exit sql.sqlcode

ALTER SESSION SET CONTAINER = ${PDB_NAME};
@${ABC_SQL}

DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_users WHERE username = UPPER('${FIND_MONEY_APP_DB_USER}');
  IF n > 0 THEN
    FOR obj IN (
      SELECT object_name, object_type
        FROM dba_objects
       WHERE owner = 'ABC'
         AND object_type IN ('TABLE', 'VIEW')
    ) LOOP
      EXECUTE IMMEDIATE 'GRANT SELECT ON abc.' || obj.object_name || ' TO ${FIND_MONEY_APP_DB_USER}';
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Granted ABC read access to ${FIND_MONEY_APP_DB_USER}.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Find the Money app user ${FIND_MONEY_APP_DB_USER} does not exist yet; skipping app grants.');
  END IF;
END;
/

exit;
EOF

echo
echo "ABC demo schema loaded."
