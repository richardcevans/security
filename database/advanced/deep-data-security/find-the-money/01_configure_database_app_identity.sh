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
else
  echo "ERROR: Missing .find-the-money.env. Run ./00_setup_entra_web_app.sh first."
  exit 1
fi

: "${PDB_NAME:?PDB_NAME is required}"
: "${FIND_MONEY_APP_CLIENT_ID:?FIND_MONEY_APP_CLIENT_ID is required}"
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

echo "Configuring FIN schema, Deep Data Security roles, and application identity in PDB ${PDB_NAME}"
echo "  FIND_MONEY_APP_CLIENT_ID = ${FIND_MONEY_APP_CLIENT_ID}"
echo "  FIND_MONEY_APP_DB_USER   = ${FIND_MONEY_APP_DB_USER}"
echo "  APPLICATION IDENTITY     = ${FIND_MONEY_APPLICATION_IDENTITY}"
echo

sqlplus -s / as sysdba <<EOF
set echo off
set serveroutput on
set lines 180
set pages 9999
whenever sqlerror exit sql.sqlcode

ALTER SESSION SET CONTAINER = ${PDB_NAME};

prompt
prompt ========================================================================
prompt Create FIN schema and sample financial investigation data
prompt ========================================================================

DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_users WHERE username = 'FIN';
  IF n = 0 THEN
    EXECUTE IMMEDIATE q'[CREATE USER fin IDENTIFIED BY "FindMoney#2026" ACCOUNT LOCK]';
  END IF;
END;
/

GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE PROCEDURE TO fin;
ALTER USER fin QUOTA UNLIMITED ON users;

BEGIN
  FOR t IN (
    SELECT table_name
      FROM dba_tables
     WHERE owner = 'FIN'
       AND table_name IN (
         'RISK_ALERTS', 'CASES', 'TRANSACTIONS', 'ACCOUNTS',
         'CUSTOMERS', 'VENDORS', 'BENEFICIAL_OWNERS', 'CASE_NOTE_EMBEDDINGS'
       )
  ) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE fin.' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('Table cleanup warning: ' || SQLERRM);
END;
/

CREATE TABLE fin.customers (
  customer_id           VARCHAR2(30) PRIMARY KEY,
  full_name             VARCHAR2(120),
  tax_id                VARCHAR2(30),
  home_branch           VARCHAR2(60),
  assigned_investigator VARCHAR2(180),
  risk_rating           VARCHAR2(20)
);

CREATE TABLE fin.accounts (
  account_id      VARCHAR2(30) PRIMARY KEY,
  customer_id     VARCHAR2(30) REFERENCES fin.customers(customer_id),
  display_name    VARCHAR2(120),
  account_number  VARCHAR2(40),
  balance         NUMBER(14,2),
  branch          VARCHAR2(60)
);

CREATE TABLE fin.vendors (
  vendor_id    VARCHAR2(30) PRIMARY KEY,
  vendor_name  VARCHAR2(120),
  tax_id       VARCHAR2(30),
  risk_rating  VARCHAR2(20)
);

CREATE TABLE fin.transactions (
  transaction_id VARCHAR2(30) PRIMARY KEY,
  from_account_id VARCHAR2(30) REFERENCES fin.accounts(account_id),
  to_account_id   VARCHAR2(30),
  vendor_id       VARCHAR2(30) REFERENCES fin.vendors(vendor_id),
  amount          NUMBER(14,2),
  currency_code   VARCHAR2(3),
  memo            VARCHAR2(300),
  risk_score      NUMBER,
  transaction_ts  TIMESTAMP
);

CREATE TABLE fin.cases (
  case_id     VARCHAR2(30) PRIMARY KEY,
  title       VARCHAR2(180),
  assigned_to VARCHAR2(180),
  risk_score  NUMBER,
  status      VARCHAR2(30),
  summary     VARCHAR2(1000)
);

CREATE TABLE fin.risk_alerts (
  alert_id       VARCHAR2(30) PRIMARY KEY,
  case_id        VARCHAR2(30) REFERENCES fin.cases(case_id),
  transaction_id VARCHAR2(30) REFERENCES fin.transactions(transaction_id),
  severity       VARCHAR2(20),
  reason         VARCHAR2(500),
  amount         NUMBER(14,2),
  risk_score     NUMBER,
  status         VARCHAR2(30)
);

CREATE TABLE fin.beneficial_owners (
  owner_id            VARCHAR2(30) PRIMARY KEY,
  owner_name          VARCHAR2(120),
  tax_id              VARCHAR2(30),
  related_customer_id VARCHAR2(30),
  vendor_id           VARCHAR2(30),
  risk_rating         VARCHAR2(20)
);

CREATE TABLE fin.case_note_embeddings (
  note_id     VARCHAR2(30) PRIMARY KEY,
  case_id     VARCHAR2(30) REFERENCES fin.cases(case_id),
  title       VARCHAR2(180),
  source_text VARCHAR2(2000),
  risk_tags   VARCHAR2(500)
);

INSERT INTO fin.customers VALUES ('C-1007', 'Sophia Chen', '111-22-3333', 'Chicago', 'priya@example.com', 'High');
INSERT INTO fin.customers VALUES ('C-2041', 'Keystone Holdings', '44-5555555', 'Chicago', 'marcus@example.com', 'High');
INSERT INTO fin.customers VALUES ('C-3010', 'Lakeside Imports', '88-7777777', 'Dallas', 'marcus@example.com', 'Medium');

INSERT INTO fin.accounts VALUES ('A-8821', 'C-1007', 'Sophia operating account', '99100088210001', 1254300.45, 'Chicago');
INSERT INTO fin.accounts VALUES ('A-7732', 'C-2041', 'Keystone receiving account', '99100077320001', 812944.10, 'Chicago');
INSERT INTO fin.accounts VALUES ('A-5519', 'C-3010', 'Lakeside disbursement account', '99100055190001', 455901.00, 'Dallas');

INSERT INTO fin.vendors VALUES ('V-440', 'Northstar Supply', '55-1231231', 'High');
INSERT INTO fin.vendors VALUES ('V-881', 'Harbor Logistics', '55-7777777', 'Medium');

INSERT INTO fin.transactions VALUES ('TXN-90017', 'A-8821', 'A-7732', 'V-440', 248500, 'USD', 'Vendor services final settlement', 96, SYSTIMESTAMP - INTERVAL '3' HOUR);
INSERT INTO fin.transactions VALUES ('TXN-90112', 'A-5519', 'V-881', 'V-881', 24500, 'USD', 'Invoice 773-A', 78, SYSTIMESTAMP - INTERVAL '22' HOUR);
INSERT INTO fin.transactions VALUES ('TXN-90113', 'A-5519', 'V-881', 'V-881', 24500, 'USD', 'Invoice 773-B', 76, SYSTIMESTAMP - INTERVAL '21' HOUR);
INSERT INTO fin.transactions VALUES ('TXN-90114', 'A-5519', 'V-881', 'V-881', 24500, 'USD', 'Invoice 773-C', 74, SYSTIMESTAMP - INTERVAL '20' HOUR);

INSERT INTO fin.cases VALUES ('CASE-1042', 'Northstar vendor passthrough', 'priya@example.com', 92, 'Open', 'Customer funds moved through a vendor and returned to a related party account.');
INSERT INTO fin.cases VALUES ('CASE-1088', 'Invoice splitting through shell vendor', 'marcus@example.com', 77, 'Review', 'Three payments below approval threshold share memo text and vendor ownership.');

INSERT INTO fin.risk_alerts VALUES ('ALT-1042', 'CASE-1042', 'TXN-90017', 'High', 'Round-dollar wire through a new vendor with shared beneficial ownership.', 248500, 96, 'Open');
INSERT INTO fin.risk_alerts VALUES ('ALT-1088', 'CASE-1088', 'TXN-90112', 'Medium', 'Invoice splitting pattern across three payments in 24 hours.', 73500, 78, 'Review');

INSERT INTO fin.beneficial_owners VALUES ('OWN-77', 'Evelyn Park', '222-33-4444', 'C-2041', 'V-440', 'High');
INSERT INTO fin.beneficial_owners VALUES ('OWN-88', 'Harbor Trust', '55-8888888', 'C-3010', 'V-881', 'Medium');

INSERT INTO fin.case_note_embeddings VALUES ('NOTE-22', 'CASE-1042', 'Shared owner', 'Vendor shares beneficial owner with the final receiving account.', 'related-party passthrough shell-vendor');
INSERT INTO fin.case_note_embeddings VALUES ('NOTE-31', 'CASE-1088', 'Invoice split pattern', 'Three payments landed below approval threshold within one day.', 'invoice-splitting threshold-avoidance');

COMMIT;

prompt
prompt ========================================================================
prompt Optional vector and graph objects
prompt ========================================================================

BEGIN
  EXECUTE IMMEDIATE 'ALTER TABLE fin.case_note_embeddings ADD (note_embedding VECTOR(3))';
  EXECUTE IMMEDIATE q'~UPDATE fin.case_note_embeddings SET note_embedding = TO_VECTOR('[0.10,0.90,0.30]') WHERE note_id = 'NOTE-22'~';
  EXECUTE IMMEDIATE q'~UPDATE fin.case_note_embeddings SET note_embedding = TO_VECTOR('[0.20,0.75,0.45]') WHERE note_id = 'NOTE-31'~';
  EXECUTE IMMEDIATE q'~
    CREATE OR REPLACE FUNCTION fin.simple_text_embedding(query_text VARCHAR2)
      RETURN VECTOR
    IS
    BEGIN
      IF LOWER(query_text) LIKE '%invoice%' THEN
        RETURN TO_VECTOR('[0.20,0.75,0.45]');
      END IF;
      RETURN TO_VECTOR('[0.10,0.90,0.30]');
    END;
  ~';
  DBMS_OUTPUT.PUT_LINE('Vector demo column and helper function created.');
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('Vector demo objects skipped: ' || SQLERRM);
  BEGIN
    EXECUTE IMMEDIATE 'ALTER TABLE fin.case_note_embeddings ADD (note_embedding VARCHAR2(200))';
    EXECUTE IMMEDIATE q'~UPDATE fin.case_note_embeddings SET note_embedding = '[0.10,0.90,0.30]' WHERE note_id = 'NOTE-22'~';
    EXECUTE IMMEDIATE q'~UPDATE fin.case_note_embeddings SET note_embedding = '[0.20,0.75,0.45]' WHERE note_id = 'NOTE-31'~';
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Fallback note_embedding column warning: ' || SQLERRM);
  END;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP PROPERTY GRAPH fin.money_graph';
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
/

BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE PROPERTY GRAPH fin.money_graph
      VERTEX TABLES (
        fin.customers KEY (customer_id) LABEL customer PROPERTIES (customer_id AS id, full_name AS name, risk_rating),
        fin.accounts KEY (account_id) LABEL account PROPERTIES (account_id AS id, display_name AS name, branch),
        fin.vendors KEY (vendor_id) LABEL vendor PROPERTIES (vendor_id AS id, vendor_name AS name, risk_rating),
        fin.transactions KEY (transaction_id) LABEL transaction PROPERTIES (transaction_id AS id, memo AS name, amount, risk_score)
      )
      EDGE TABLES (
        fin.accounts AS owns_account
          KEY (account_id)
          SOURCE KEY (customer_id) REFERENCES fin.customers(customer_id)
          DESTINATION KEY (account_id) REFERENCES fin.accounts(account_id)
          PROPERTIES (account_id AS id),
        fin.transactions AS sent_payment
          KEY (transaction_id)
          SOURCE KEY (from_account_id) REFERENCES fin.accounts(account_id)
          DESTINATION KEY (to_account_id) REFERENCES fin.accounts(account_id)
          PROPERTIES (transaction_id AS id, amount, risk_score),
        fin.transactions AS paid_vendor
          KEY (transaction_id)
          SOURCE KEY (from_account_id) REFERENCES fin.accounts(account_id)
          DESTINATION KEY (vendor_id) REFERENCES fin.vendors(vendor_id)
          PROPERTIES (transaction_id AS id, amount, risk_score)
      )
  ]';
  DBMS_OUTPUT.PUT_LINE('SQL property graph FIN.MONEY_GRAPH created.');
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('Property graph skipped: ' || SQLERRM);
END;
/

prompt
prompt ========================================================================
prompt Create application database user and application identity
prompt ========================================================================

DECLARE
  user_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO user_exists FROM dba_users WHERE username = UPPER('${FIND_MONEY_APP_DB_USER}');
  IF user_exists = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE USER ${FIND_MONEY_APP_DB_USER} IDENTIFIED GLOBALLY
      AS 'AZURE_CLIENT_ID=${FIND_MONEY_APP_CLIENT_ID}'
    ]';
  ELSE
    DBMS_OUTPUT.PUT_LINE('Reusing ${FIND_MONEY_APP_DB_USER}.');
  END IF;
END;
/

GRANT CREATE SESSION TO ${FIND_MONEY_APP_DB_USER};
GRANT CREATE END USER SECURITY CONTEXT TO ${FIND_MONEY_APP_DB_USER};
GRANT UPDATE ANY END USER CONTEXT TO ${FIND_MONEY_APP_DB_USER};
GRANT AUDIT_VIEWER TO ${FIND_MONEY_APP_DB_USER};

BEGIN
  FOR t IN (SELECT table_name FROM dba_tables WHERE owner = 'FIN') LOOP
    EXECUTE IMMEDIATE 'GRANT SELECT ON fin.' || t.table_name || ' TO ${FIND_MONEY_APP_DB_USER}';
    BEGIN
      EXECUTE IMMEDIATE 'SET USE DATA GRANTS ONLY ON fin.' || t.table_name || ' ENABLED';
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('DDS enable warning for FIN.' || t.table_name || ': ' || SQLERRM);
    END;
  END LOOP;
END;
/

CREATE OR REPLACE APPLICATION IDENTITY ${FIND_MONEY_APPLICATION_IDENTITY}
  MAPPED TO 'AZURE_CLIENT_ID=${FIND_MONEY_APP_CLIENT_ID}';

prompt
prompt ========================================================================
prompt Reuse DDS data roles mapped by entra-id-data-grants
prompt ========================================================================

prompt Reusing HRAPP_EMPLOYEES for teller access and HRAPP_MANAGERS for investigator access.
CREATE DATA ROLE IF NOT EXISTS finapp_auditors;
CREATE DATA ROLE IF NOT EXISTS finapp_ai_investigator DISABLED;

GRANT DATA ROLE finapp_ai_investigator TO ${FIND_MONEY_APPLICATION_IDENTITY};

prompt
prompt ========================================================================
prompt Create FIN Deep Data Security grants
prompt ========================================================================

CREATE OR REPLACE DATA GRANT fin.FINAPP_TELLER_ALERTS
  AS SELECT (alert_id, case_id, transaction_id, severity, reason, status)
  ON fin.risk_alerts
  WHERE 1 = 1
  TO HRAPP_EMPLOYEES;

CREATE OR REPLACE DATA GRANT fin.FINAPP_TELLER_CASES
  AS SELECT (case_id, title, status)
  ON fin.cases
  WHERE 1 = 1
  TO HRAPP_EMPLOYEES;

CREATE OR REPLACE DATA GRANT fin.FINAPP_TELLER_CUSTOMERS
  AS SELECT (customer_id, full_name, home_branch, risk_rating)
  ON fin.customers
  WHERE home_branch = 'Chicago'
  TO HRAPP_EMPLOYEES;

CREATE OR REPLACE DATA GRANT fin.FINAPP_INVESTIGATOR_ALERTS
  AS SELECT (alert_id, case_id, transaction_id, severity, reason, amount, risk_score, status)
  ON fin.risk_alerts
  WHERE 1 = 1
  TO HRAPP_MANAGERS;

CREATE OR REPLACE DATA GRANT fin.FINAPP_INVESTIGATOR_CASES
  AS SELECT (case_id, title, assigned_to, risk_score, status, summary)
  ON fin.cases
  WHERE 1 = 1
  TO HRAPP_MANAGERS;

CREATE OR REPLACE DATA GRANT fin.FINAPP_INVESTIGATOR_TRANSACTIONS
  AS SELECT (transaction_id, from_account_id, to_account_id, vendor_id, amount, currency_code, memo, risk_score, transaction_ts)
  ON fin.transactions
  WHERE 1 = 1
  TO HRAPP_MANAGERS;

CREATE OR REPLACE DATA GRANT fin.FINAPP_INVESTIGATOR_NOTES
  AS SELECT (note_id, case_id, title, source_text, risk_tags, note_embedding)
  ON fin.case_note_embeddings
  WHERE 1 = 1
  TO HRAPP_MANAGERS;

CREATE OR REPLACE DATA GRANT fin.FINAPP_SENIOR_ALERTS
  AS SELECT (alert_id, case_id, transaction_id, severity, reason, amount, risk_score, status)
  ON fin.risk_alerts
  WHERE 1 = 1
  TO HRAPP_MANAGERS;

CREATE OR REPLACE DATA GRANT fin.FINAPP_SENIOR_CASES
  AS SELECT (case_id, title, assigned_to, risk_score, status, summary)
  ON fin.cases
  WHERE 1 = 1
  TO HRAPP_MANAGERS;

CREATE OR REPLACE DATA GRANT fin.FINAPP_SENIOR_TRANSACTIONS
  AS SELECT (transaction_id, from_account_id, to_account_id, vendor_id, amount, currency_code, memo, risk_score, transaction_ts)
  ON fin.transactions
  WHERE 1 = 1
  TO HRAPP_MANAGERS;

CREATE OR REPLACE DATA GRANT fin.FINAPP_SENIOR_CUSTOMERS
  AS SELECT (customer_id, full_name, tax_id, home_branch, assigned_investigator, risk_rating)
  ON fin.customers
  WHERE 1 = 1
  TO HRAPP_MANAGERS;

CREATE OR REPLACE DATA GRANT fin.FINAPP_SENIOR_ACCOUNTS
  AS SELECT (account_id, customer_id, display_name, account_number, balance, branch)
  ON fin.accounts
  WHERE 1 = 1
  TO HRAPP_MANAGERS;

CREATE OR REPLACE DATA GRANT fin.FINAPP_SENIOR_VENDORS
  AS SELECT (vendor_id, vendor_name, tax_id, risk_rating)
  ON fin.vendors
  WHERE 1 = 1
  TO HRAPP_MANAGERS;

CREATE OR REPLACE DATA GRANT fin.FINAPP_SENIOR_OWNERS
  AS SELECT (owner_id, owner_name, tax_id, related_customer_id, vendor_id, risk_rating)
  ON fin.beneficial_owners
  WHERE 1 = 1
  TO HRAPP_MANAGERS;

CREATE OR REPLACE DATA GRANT fin.FINAPP_SENIOR_NOTES
  AS SELECT (note_id, case_id, title, source_text, risk_tags, note_embedding)
  ON fin.case_note_embeddings
  WHERE 1 = 1
  TO HRAPP_MANAGERS;

CREATE OR REPLACE DATA GRANT fin.FINAPP_AI_ALERTS
  AS SELECT (alert_id, case_id, transaction_id, severity, reason, status, risk_score)
  ON fin.risk_alerts
  WHERE 1 = 1
  TO FINAPP_AI_INVESTIGATOR;

CREATE OR REPLACE DATA GRANT fin.FINAPP_AI_NOTES
  AS SELECT (note_id, case_id, title, source_text, risk_tags, note_embedding)
  ON fin.case_note_embeddings
  WHERE 1 = 1
  TO FINAPP_AI_INVESTIGATOR;

CREATE OR REPLACE DATA GRANT fin.FINAPP_AI_TRANSACTIONS
  AS SELECT (transaction_id, from_account_id, to_account_id, vendor_id, amount, currency_code, memo, risk_score, transaction_ts)
  ON fin.transactions
  WHERE 1 = 1
  TO FINAPP_AI_INVESTIGATOR;

CREATE OR REPLACE DATA GRANT fin.FINAPP_AI_ACCOUNTS
  AS SELECT (account_id, customer_id, display_name, branch)
  ON fin.accounts
  WHERE 1 = 1
  TO FINAPP_AI_INVESTIGATOR;

CREATE OR REPLACE DATA GRANT fin.FINAPP_AI_VENDORS
  AS SELECT (vendor_id, vendor_name, risk_rating)
  ON fin.vendors
  WHERE 1 = 1
  TO FINAPP_AI_INVESTIGATOR;

prompt
prompt ========================================================================
prompt Verify FIN DDS setup
prompt ========================================================================

col data_role format a32
col mapped_to format a36
SELECT data_role, mapped_to, enabled_by_default
  FROM dba_data_roles
 WHERE data_role LIKE 'FINAPP%'
    OR data_role IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS')
 ORDER BY data_role;

col grant_name format a36
col object_name format a28
col grantee format a32
SELECT grant_name, object_name, privilege, grantee
  FROM dba_data_grants
 WHERE object_owner = 'FIN'
 ORDER BY object_name, grant_name, privilege;

exit;
EOF

echo
echo "FIN schema and Find the Money application identity configured."
