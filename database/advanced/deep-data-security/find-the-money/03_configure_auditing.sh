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
DB_SID="${DB_SID:-FREE}"
ORACLE_HOME="${ORACLE_HOME:-/opt/oracle/product/26ai/dbhome_1}"
if [ -x "$ORACLE_HOME/bin/sqlplus" ]; then
  export ORACLE_HOME
  export PATH="$ORACLE_HOME/bin:$PATH"
  export LD_LIBRARY_PATH="$ORACLE_HOME/lib:${LD_LIBRARY_PATH:-}"
fi
export ORACLE_SID="$DB_SID"

echo "Configuring Unified Audit policy for FIN investigation objects in PDB ${PDB_NAME}"

sqlplus -s / as sysdba <<EOF
set echo off
set serveroutput on
set lines 180
set pages 9999
whenever sqlerror exit sql.sqlcode

ALTER SESSION SET CONTAINER = ${PDB_NAME};

BEGIN
  BEGIN
    EXECUTE IMMEDIATE 'NOAUDIT POLICY find_money_app_fin_audit';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    EXECUTE IMMEDIATE 'DROP AUDIT POLICY find_money_app_fin_audit';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END;
/

CREATE AUDIT POLICY find_money_app_fin_audit
  ACTIONS SELECT ON fin.customers,
          SELECT ON fin.accounts,
          SELECT ON fin.transactions,
          SELECT ON fin.vendors,
          SELECT ON fin.beneficial_owners,
          SELECT ON fin.cases,
          SELECT ON fin.risk_alerts,
          SELECT ON fin.case_note_embeddings,
          INSERT ON fin.case_note_embeddings,
          UPDATE ON fin.case_note_embeddings,
          DELETE ON fin.case_note_embeddings;

AUDIT POLICY find_money_app_fin_audit;

GRANT AUDIT_VIEWER TO ${FIND_MONEY_APP_DB_USER};

col policy_name format a34
col audit_option format a16
col object_schema format a12
col object_name format a30
SELECT policy_name, audit_option, object_schema, object_name
  FROM audit_unified_policies
 WHERE policy_name = 'FIND_MONEY_APP_FIN_AUDIT'
 ORDER BY object_name, audit_option;

exit;
EOF

echo
echo "Unified Audit policy configured."
