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

echo "Configuring DBA policy toggle procedures for AI evidence in PDB ${PDB_NAME}"

sqlplus -s / as sysdba <<EOF
set echo off
set serveroutput on
set lines 180
set pages 9999
whenever sqlerror exit sql.sqlcode

ALTER SESSION SET CONTAINER = ${PDB_NAME};

CREATE OR REPLACE PROCEDURE sys.find_money_disable_ai_evidence
AUTHID DEFINER
AS
BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE OR REPLACE DATA GRANT fin.FINAPP_AI_NOTES
      AS SELECT (note_id, case_id, title, risk_tags, note_embedding)
      ON fin.case_note_embeddings
      WHERE 1 = 1
      TO FINAPP_AI_INVESTIGATOR
  ]';
END;
/

CREATE OR REPLACE PROCEDURE sys.find_money_enable_ai_evidence
AUTHID DEFINER
AS
BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE OR REPLACE DATA GRANT fin.FINAPP_AI_NOTES
      AS SELECT (note_id, case_id, title, source_text, risk_tags, note_embedding)
      ON fin.case_note_embeddings
      WHERE 1 = 1
      TO FINAPP_AI_INVESTIGATOR
  ]';
END;
/

GRANT EXECUTE ON sys.find_money_disable_ai_evidence TO ${FIND_MONEY_APP_DB_USER};
GRANT EXECUTE ON sys.find_money_enable_ai_evidence TO ${FIND_MONEY_APP_DB_USER};

col table_name format a36
col grantee format a28
col privilege format a12
SELECT table_name, grantee, privilege
  FROM dba_tab_privs
 WHERE owner = 'SYS'
   AND table_name IN ('FIND_MONEY_DISABLE_AI_EVIDENCE', 'FIND_MONEY_ENABLE_AI_EVIDENCE')
 ORDER BY table_name, grantee;

exit;
EOF

echo
echo "DBA policy toggle demo procedures configured."
