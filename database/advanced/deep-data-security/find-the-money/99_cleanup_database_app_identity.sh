#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRA_LAB_ENV="${ENTRA_LAB_ENV:-${SCRIPT_DIR}/../entra-id-data-grants/.entra-id-data-grants.env}"

if [ -f "$ENTRA_LAB_ENV" ]; then
  # shellcheck disable=SC1090
  source "$ENTRA_LAB_ENV"
fi
if [ -f "${SCRIPT_DIR}/.find-the-money.env" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.find-the-money.env"
fi

: "${PDB_NAME:?PDB_NAME is required}"
FIND_MONEY_APP_DB_USER="${FIND_MONEY_APP_DB_USER:-find_money_app_user}"
FIND_MONEY_APPLICATION_IDENTITY="${FIND_MONEY_APPLICATION_IDENTITY:-find_money_app}"
DB_SID="${DB_SID:-FREE}"
ORACLE_HOME="${ORACLE_HOME:-/opt/oracle/product/26ai/dbhome_1}"
if [ -x "$ORACLE_HOME/bin/sqlplus" ]; then
  export ORACLE_HOME
  export PATH="$ORACLE_HOME/bin:$PATH"
  export LD_LIBRARY_PATH="$ORACLE_HOME/lib:${LD_LIBRARY_PATH:-}"
fi
export ORACLE_SID="$DB_SID"

echo "Cleaning up Find the Money database objects in PDB ${PDB_NAME}"

sqlplus -s / as sysdba <<EOF
set echo off
set serveroutput on
whenever sqlerror exit sql.sqlcode

ALTER SESSION SET CONTAINER = ${PDB_NAME};

BEGIN
  BEGIN EXECUTE IMMEDIATE 'NOAUDIT POLICY find_money_app_fin_audit'; DBMS_OUTPUT.PUT_LINE('Disabled FIND_MONEY_APP_FIN_AUDIT.'); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN EXECUTE IMMEDIATE 'DROP AUDIT POLICY find_money_app_fin_audit'; DBMS_OUTPUT.PUT_LINE('Dropped FIND_MONEY_APP_FIN_AUDIT.'); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN EXECUTE IMMEDIATE 'DROP PROCEDURE sys.find_money_disable_ai_evidence'; DBMS_OUTPUT.PUT_LINE('Dropped SYS.FIND_MONEY_DISABLE_AI_EVIDENCE.'); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN EXECUTE IMMEDIATE 'DROP PROCEDURE sys.find_money_enable_ai_evidence'; DBMS_OUTPUT.PUT_LINE('Dropped SYS.FIND_MONEY_ENABLE_AI_EVIDENCE.'); EXCEPTION WHEN OTHERS THEN NULL; END;
  FOR g IN (SELECT owner, grant_name FROM dba_data_grants WHERE object_owner = 'FIN') LOOP
    BEGIN EXECUTE IMMEDIATE 'DROP DATA GRANT ' || g.owner || '.' || g.grant_name; EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;
  FOR r IN (SELECT data_role FROM dba_data_roles WHERE data_role LIKE 'FINAPP%') LOOP
    BEGIN EXECUTE IMMEDIATE 'DROP DATA ROLE ' || r.data_role; EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;
  IF UPPER('${FIND_MONEY_APPLICATION_IDENTITY}') = 'FIND_MONEY_APP' THEN
    BEGIN EXECUTE IMMEDIATE 'DROP APPLICATION IDENTITY find_money_app'; DBMS_OUTPUT.PUT_LINE('Dropped FIND_MONEY_APP application identity.'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  IF UPPER('${FIND_MONEY_APP_DB_USER}') = 'FIND_MONEY_APP_USER' THEN
    BEGIN EXECUTE IMMEDIATE 'DROP USER find_money_app_user'; DBMS_OUTPUT.PUT_LINE('Dropped FIND_MONEY_APP_USER.'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  BEGIN EXECUTE IMMEDIATE 'DROP USER fin CASCADE'; DBMS_OUTPUT.PUT_LINE('Dropped FIN schema.'); EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/

exit;
EOF

echo "Find the Money database objects removed."
