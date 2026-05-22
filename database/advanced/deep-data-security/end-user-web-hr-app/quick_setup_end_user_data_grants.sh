#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TNS_ALIAS="${WEB_HR_TNS_ALIAS:-freepdb1}"
DBA_CONNECT="${WEB_HR_DBA_CONNECT:-sys/Oracle123@${TNS_ALIAS} as sysdba}"
FORCE_RESET=0

usage() {
  cat <<'EOF'
Usage:
  ./quick_setup_end_user_data_grants.sh [options]

Options:
  --tns-alias <alias>
      Target database service alias. Default: WEB_HR_TNS_ALIAS or freepdb1.

  --dba-connect <connect-string>
      SQL*Plus DBA connection string. Default: sys/Oracle123@<alias> as sysdba.

  --force-reset
      Drop the lab-created Deep Data Security objects and HR schema first.
      Use this only for a disposable lab PDB.

  -h, --help
      Show this help.

This is a shortcut for the End User Web HR App lab. The recommended learning
path is still to complete end-user-data-grants.md manually first.

Default lab passwords:
  sys, system, deepsec_admin, emma, marvin -> Oracle123
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
    --force-reset)
      FORCE_RESET=1
      shift
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
echo "Quick setup for end-user-data-grants objects"
echo "  TNS alias   = ${TNS_ALIAS}"
echo "  DBA connect = ${DBA_CONNECT}"
echo "  force reset = ${FORCE_RESET}"
echo
echo "This creates the HR schema, Emma and Marvin end users, data roles,"
echo "data grants, audit policy, and the deepsec_admin diagnostics user"
echo "used by the End User Web HR App. All lab passwords default to Oracle123."
echo

sqlplus -s "$DBA_CONNECT" <<SQL
SET ECHO OFF FEEDBACK ON VERIFY OFF HEADING ON PAGESIZE 200 LINESIZE 200 SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
  l_count NUMBER;
BEGIN
  SELECT COUNT(*)
    INTO l_count
    FROM dba_tables
   WHERE owner = 'HR'
     AND table_name IN ('EMPLOYEES', 'MANAGERS');

  IF l_count > 0 AND ${FORCE_RESET} = 0 THEN
    RAISE_APPLICATION_ERROR(
      -20001,
      'HR.EMPLOYEES or HR.MANAGERS already exists. Complete the manual lab, or rerun this shortcut with --force-reset in a disposable lab PDB.'
    );
  END IF;
END;
/

BEGIN
  IF ${FORCE_RESET} = 1 THEN
    FOR stmt IN (
      SELECT 'DROP DATA GRANT hr.HRAPP_EMPLOYEE_ACCESS' AS sql_text FROM dual UNION ALL
      SELECT 'DROP DATA GRANT hr.HRAPP_MANAGER_ACCESS' FROM dual UNION ALL
      SELECT 'DROP ROLE direct_logon_role' FROM dual UNION ALL
      SELECT 'DROP DATA ROLE HRAPP_EMPLOYEES' FROM dual UNION ALL
      SELECT 'DROP DATA ROLE HRAPP_MANAGERS' FROM dual UNION ALL
      SELECT 'DROP END USER emma' FROM dual UNION ALL
      SELECT 'DROP END USER marvin' FROM dual UNION ALL
      SELECT 'DROP USER deepsec_admin CASCADE' FROM dual UNION ALL
      SELECT 'DROP USER hr CASCADE' FROM dual
    ) LOOP
      BEGIN
        EXECUTE IMMEDIATE stmt.sql_text;
        DBMS_OUTPUT.PUT_LINE('Ran: ' || stmt.sql_text);
      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Skipped: ' || stmt.sql_text || ' (' || SQLERRM || ')');
      END;
    END LOOP;
  END IF;
END;
/

DECLARE
  l_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_count FROM dba_users WHERE username = 'HR';
  IF l_count = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER hr NO AUTHENTICATION DEFAULT TABLESPACE users';
  ELSE
    EXECUTE IMMEDIATE 'ALTER USER hr NO AUTHENTICATION';
  END IF;
  EXECUTE IMMEDIATE 'ALTER USER hr QUOTA UNLIMITED ON users';
END;
/

CREATE TABLE hr.employees (
  employee_id   NUMBER PRIMARY KEY,
  first_name    VARCHAR2(50),
  last_name     VARCHAR2(50),
  job_code      VARCHAR2(10),
  department_id NUMBER,
  ssn           VARCHAR2(20),
  photo         BLOB,
  phone_number  VARCHAR2(30),
  salary        NUMBER(10,2),
  user_name     VARCHAR2(128),
  manager_id    NUMBER
);

INSERT INTO hr.employees VALUES (1, 'Grace', 'Young', 'CEO', NULL, '111-11-1111', NULL, '555-100-0001', 235000, 'grace', NULL);
INSERT INTO hr.employees VALUES (2, 'Marvin', 'Morgan', 'SWE_MGR', 1, '222-22-2222', NULL, '555-100-0002', 175000, 'marvin', 1);
INSERT INTO hr.employees VALUES (3, 'Emma', 'Baker', 'SWE2', 1, '333-33-3333', NULL, '555-100-0003', 120000, 'emma', 2);
INSERT INTO hr.employees VALUES (4, 'Charlie', 'Davis', 'SWE1', 1, '444-44-4444', NULL, '555-100-0004', 95000, 'charlie', 2);
INSERT INTO hr.employees VALUES (5, 'Dana', 'Lee', 'SWE3', 1, '555-55-5555', NULL, '555-100-0005', 130000, 'dana', 2);
INSERT INTO hr.employees VALUES (6, 'Bob', 'Smith', 'SALES_REP', 2, '666-66-6666', NULL, '555-100-0006', 145000, 'bob', 1);
INSERT INTO hr.employees VALUES (7, 'Fiona', 'Chen', 'HR_REP', 3, '777-77-7777', NULL, '555-100-0007', 92000, 'fiona', 1);

CREATE TABLE hr.managers (
  manager_id      NUMBER,
  employee_id     NUMBER,
  mgr_user_name   VARCHAR2(128),
  mgr_first_name  VARCHAR2(50),
  mgr_last_name   VARCHAR2(50)
);

INSERT INTO hr.managers (manager_id, employee_id, mgr_user_name, mgr_first_name, mgr_last_name)
SELECT e.manager_id,
       e.employee_id,
       m.user_name,
       m.first_name,
       m.last_name
  FROM hr.employees e
  JOIN hr.employees m
    ON e.manager_id = m.employee_id
 WHERE e.manager_id IS NOT NULL;

COMMIT;

DECLARE
  l_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_count FROM dba_users WHERE username = 'DEEPSEC_ADMIN';
  IF l_count = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER deepsec_admin IDENTIFIED BY Oracle123';
  ELSE
    EXECUTE IMMEDIATE 'ALTER USER deepsec_admin IDENTIFIED BY Oracle123 ACCOUNT UNLOCK';
  END IF;
END;
/

GRANT CREATE SESSION TO deepsec_admin;
GRANT AUDIT_VIEWER TO deepsec_admin;

BEGIN
  BEGIN
    EXECUTE IMMEDIATE 'NOAUDIT POLICY end_user_web_hr_employee_audit';
    DBMS_OUTPUT.PUT_LINE('Disabled existing END_USER_WEB_HR_EMPLOYEE_AUDIT policy.');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('No existing enabled END_USER_WEB_HR_EMPLOYEE_AUDIT policy to disable.');
  END;

  BEGIN
    EXECUTE IMMEDIATE 'DROP AUDIT POLICY end_user_web_hr_employee_audit';
    DBMS_OUTPUT.PUT_LINE('Dropped existing END_USER_WEB_HR_EMPLOYEE_AUDIT policy.');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('No existing END_USER_WEB_HR_EMPLOYEE_AUDIT policy to drop.');
  END;
END;
/

CREATE AUDIT POLICY end_user_web_hr_employee_audit
  ACTIONS SELECT ON hr.employees,
          UPDATE ON hr.employees;

AUDIT POLICY end_user_web_hr_employee_audit;

CREATE END USER emma IDENTIFIED BY Oracle123;
CREATE END USER marvin IDENTIFIED BY Oracle123;

CREATE ROLE direct_logon_role;
GRANT CREATE SESSION TO direct_logon_role;

CREATE DATA ROLE HRAPP_EMPLOYEES;
CREATE DATA ROLE HRAPP_MANAGERS;

GRANT DATA ROLE HRAPP_EMPLOYEES TO emma;
GRANT DATA ROLE HRAPP_EMPLOYEES TO marvin;
GRANT DATA ROLE HRAPP_MANAGERS TO marvin;

GRANT direct_logon_role TO HRAPP_EMPLOYEES;
GRANT direct_logon_role TO HRAPP_MANAGERS;

CREATE OR REPLACE DATA GRANT hr.HRAPP_EMPLOYEE_ACCESS
  AS SELECT, UPDATE(phone_number, first_name)
  ON hr.employees
  WHERE upper(user_name) = upper(ORA_END_USER_CONTEXT.username)
  TO HRAPP_EMPLOYEES;

CREATE OR REPLACE DATA GRANT hr.HRAPP_MANAGER_ACCESS
  AS SELECT (ALL COLUMNS EXCEPT ssn), UPDATE (salary, department_id, first_name)
  ON hr.employees
  WHERE manager_id IN (SELECT m.manager_id
                         FROM hr.managers m
                        WHERE upper(m.mgr_user_name) = upper(ORA_END_USER_CONTEXT.username))
  TO HRAPP_MANAGERS;

PROMPT
PROMPT Setup complete. Summary:
SELECT username FROM dba_users WHERE username IN ('HR', 'DEEPSEC_ADMIN') ORDER BY username;
SELECT data_role, grantee, grantee_type
  FROM dba_data_role_grants
 WHERE data_role IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS')
    OR grantee IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS')
 ORDER BY data_role, grantee;
SELECT DISTINCT grant_name, grantee
  FROM dba_data_grants
 WHERE object_owner = 'HR'
   AND object_name = 'EMPLOYEES'
 ORDER BY grant_name, grantee;
SELECT policy_name, enabled_option, success, failure
  FROM audit_unified_enabled_policies
 WHERE policy_name = 'END_USER_WEB_HR_EMPLOYEE_AUDIT';

EXIT
SQL

cat <<EOF

Next checks:
  sqlplus emma/Oracle123@${TNS_ALIAS}
  sqlplus marvin/Oracle123@${TNS_ALIAS}
  sqlplus deepsec_admin/Oracle123@${TNS_ALIAS}

Then start the app:
  export WEB_HR_TNS_ALIAS=${TNS_ALIAS}
  export WEB_HR_DB_MODE=oracledb
  ./start.sh --verbose
EOF
