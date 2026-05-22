#!/bin/bash
# Oracle Deep Data Security - End User Data Grants Lab

# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------
BOLD=$(tput bold 2>/dev/null || printf '')
CYAN=$(tput setaf 6 2>/dev/null || printf '')
GREEN=$(tput setaf 2 2>/dev/null || printf '')
YELLOW=$(tput setaf 3 2>/dev/null || printf '')
BLUE=$(tput setaf 4 2>/dev/null || printf '')
RESET=$(tput sgr0 2>/dev/null || printf '')

banner() {
    echo ""
    echo "${BOLD}${CYAN}================================================================${RESET}"
    printf "${BOLD}${CYAN}  %s${RESET}\n" "$*"
    echo "${BOLD}${CYAN}================================================================${RESET}"
    echo ""
}

step() {
    echo "  ${BOLD}${BLUE}$*${RESET}"
    echo ""
}

show_and_run() {
    local connect_display="$1"
    local sql="$2"
    local connect_actual="${3:-$1}"

    echo "  ${YELLOW}Connect:${RESET} ${GREEN}${connect_display}${RESET}"
    echo "  ${YELLOW}SQL:${RESET}"
    printf '%s\n' "$sql" | sed 's/^/    /'
    echo ""
    printf 'SET LINESIZE 110\nSET PAGESIZE 999\n%s\nEXIT\n' "$sql" | sqlplus -s "$connect_actual"
    echo ""
}

pause() {
    echo "  ${YELLOW}Press Enter to continue...${RESET}"
    read -r
}

# ---------------------------------------------------------------------------
# Environment setup
# ---------------------------------------------------------------------------
banner "Environment Setup"

#step "Sourcing Oracle DB environment"
#echo "  ${YELLOW}Command:${RESET} ${GREEN}source \$DBSEC_ADMIN/setEnv-db23free.sh FREE FREEPDB1${RESET}"
#echo ""
# shellcheck disable=SC1090
#source "$DBSEC_ADMIN/setEnv-db23free.sh" FREE FREEPDB1
#unset WALLET_DIR TNS_ADMIN
echo "  ORACLE_HOME = $ORACLE_HOME"
echo "  ORACLE_SID  = $ORACLE_SID"
echo "  PDB_NAME    = $PDB_NAME"

pause

# ---------------------------------------------------------------------------
# Task 0: Create deepsec_admin
# ---------------------------------------------------------------------------
banner "Task 0: Create a Deep Data Security Administrator"

step "Creating deepsec_admin user and granting privileges (connect as SYS)"
show_and_run \
    "sys/Oracle123@${PDB_NAME} as sysdba" \
    "
CREATE USER deepsec_admin IDENTIFIED BY Oracle123;

GRANT CREATE SESSION         TO deepsec_admin WITH ADMIN OPTION;
GRANT CREATE USER            TO deepsec_admin;
GRANT ALTER USER             TO deepsec_admin;
GRANT DROP USER              TO deepsec_admin;
GRANT CREATE ANY TABLE       TO deepsec_admin;
GRANT ALTER ANY TABLE        TO deepsec_admin;
GRANT DROP ANY TABLE         TO deepsec_admin;
GRANT INSERT ANY TABLE       TO deepsec_admin;
GRANT SELECT ANY TABLE       TO deepsec_admin;
GRANT CREATE ANY INDEX       TO deepsec_admin;
GRANT CREATE ROLE            TO deepsec_admin;
GRANT DROP ANY ROLE          TO deepsec_admin;
GRANT GRANT ANY ROLE         TO deepsec_admin;
GRANT SELECT_CATALOG_ROLE    TO deepsec_admin;

GRANT CREATE END USER        TO deepsec_admin;
GRANT DROP END USER          TO deepsec_admin;
GRANT CREATE DATA ROLE       TO deepsec_admin;
GRANT DROP DATA ROLE         TO deepsec_admin;
GRANT GRANT ANY DATA ROLE    TO deepsec_admin;
GRANT CREATE ANY DATA GRANT  TO deepsec_admin;
GRANT DROP ANY DATA GRANT    TO deepsec_admin;
GRANT ADMINISTER ANY DATA GRANT TO deepsec_admin;
" \
    "sys/Oracle123@${PDB_NAME} as sysdba"

pause

# ---------------------------------------------------------------------------
# Task 1: Create the HR schema and employee data
# ---------------------------------------------------------------------------
banner "Task 1: Create the HR Schema and Employee Data"

step "Step 1 of 3 — Check whether HR schema and tables already exist"
show_and_run \
    "deepsec_admin/Oracle123@${PDB_NAME}" \
    "
COLUMN username    FORMAT A10 HEADING 'USERNAME'
SELECT username
  FROM dba_users
 WHERE username = 'HR';

COLUMN table_name FORMAT A10 HEADING 'TABLE_NAME'
SELECT table_name
  FROM dba_tables
 WHERE owner = 'HR'
   AND table_name IN ('EMPLOYEES', 'MANAGERS');
"

step "Step 2 of 3 — Create (or convert) the HR schema-only account"
show_and_run \
    "deepsec_admin/Oracle123@${PDB_NAME}" \
    "
-- If HR already exists, convert it to schema-only; otherwise create it.
DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM dba_users WHERE username = 'HR';
  IF v_count > 0 THEN
    EXECUTE IMMEDIATE 'ALTER USER hr NO AUTHENTICATION';
    EXECUTE IMMEDIATE 'ALTER USER hr QUOTA UNLIMITED ON users';
  ELSE
    EXECUTE IMMEDIATE 'CREATE USER hr NO AUTHENTICATION DEFAULT TABLESPACE users';
    EXECUTE IMMEDIATE 'ALTER USER hr QUOTA UNLIMITED ON users';
  END IF;
END;
/
"

step "Step 3 of 3 — Create EMPLOYEES and MANAGERS tables and insert sample data"
show_and_run \
    "deepsec_admin/Oracle123@${PDB_NAME}" \
    "
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
  manager_id    NUMBER);

INSERT INTO hr.employees (employee_id, first_name, last_name, job_code, department_id, ssn, photo, phone_number, salary, user_name, manager_id)
VALUES (1, 'Grace',   'Young',  'CEO',      NULL, '111-11-1111', NULL, '555-100-0001', 235000, 'grace',   NULL);

INSERT INTO hr.employees (employee_id, first_name, last_name, job_code, department_id, ssn, photo, phone_number, salary, user_name, manager_id)
VALUES (2, 'Marvin',  'Morgan', 'SWE_MGR',  1,    '222-22-2222', NULL, '555-100-0002', 175000, 'marvin',  1);

INSERT INTO hr.employees (employee_id, first_name, last_name, job_code, department_id, ssn, photo, phone_number, salary, user_name, manager_id)
VALUES (3, 'Emma',    'Baker',  'SWE2',     1,    '333-33-3333', NULL, '555-100-0003', 120000, 'emma',    2);

INSERT INTO hr.employees (employee_id, first_name, last_name, job_code, department_id, ssn, photo, phone_number, salary, user_name, manager_id)
VALUES (4, 'Charlie', 'Davis',  'SWE1',     1,    '444-44-4444', NULL, '555-100-0004',  95000, 'charlie', 2);

INSERT INTO hr.employees (employee_id, first_name, last_name, job_code, department_id, ssn, photo, phone_number, salary, user_name, manager_id)
VALUES (5, 'Dana',    'Lee',    'SWE3',     1,    '555-55-5555', NULL, '555-100-0005', 130000, 'dana',    2);

INSERT INTO hr.employees (employee_id, first_name, last_name, job_code, department_id, ssn, photo, phone_number, salary, user_name, manager_id)
VALUES (6, 'Bob',     'Smith',  'SALES_REP',2,    '666-66-6666', NULL, '555-100-0006', 145000, 'bob',     1);

INSERT INTO hr.employees (employee_id, first_name, last_name, job_code, department_id, ssn, photo, phone_number, salary, user_name, manager_id)
VALUES (7, 'Fiona',   'Chen',   'HR_REP',   3,    '777-77-7777', NULL, '555-100-0007',  92000, 'fiona',   1);

CREATE TABLE hr.managers (
  manager_id    NUMBER,
  employee_id   NUMBER,
  mgr_user_name VARCHAR2(128),
  mgr_first_name VARCHAR2(50),
  mgr_last_name  VARCHAR2(50));

INSERT INTO hr.managers (manager_id, employee_id, mgr_user_name, mgr_first_name, mgr_last_name)
SELECT e.manager_id, e.employee_id, m.user_name, m.first_name, m.last_name
  FROM hr.employees e
  JOIN hr.employees m ON e.manager_id = m.employee_id
 WHERE e.manager_id IS NOT NULL;

COMMIT;

-- Verify: all 7 employees visible to admin
COLUMN employee_id FORMAT 99          HEADING 'ID'
COLUMN first_name  FORMAT A7          HEADING 'FIRST'
COLUMN last_name   FORMAT A6          HEADING 'LAST'
COLUMN user_name   FORMAT A8          HEADING 'USERNAME'
COLUMN ssn         FORMAT A11         HEADING 'SSN'
COLUMN salary      FORMAT 999,999.99  HEADING 'SALARY'
SELECT employee_id, first_name, last_name, user_name, ssn, salary
  FROM hr.employees
 ORDER BY employee_id;
"

pause

# ---------------------------------------------------------------------------
# Task 2: Create Emma and Marvin as end users
# ---------------------------------------------------------------------------
banner "Task 2: Create Emma and Marvin as End Users"

step "Creating end users emma and marvin"
show_and_run \
    "deepsec_admin/Oracle123@${PDB_NAME}" \
    "
CREATE END USER emma   IDENTIFIED BY Oracle123;
CREATE END USER marvin IDENTIFIED BY Oracle123;
"

pause

# ---------------------------------------------------------------------------
# Task 3: Create database roles and data roles
# ---------------------------------------------------------------------------
banner "Task 3: Create Database Roles and Data Roles"

step "Step 1 of 4 — Create the DIRECT_LOGON_ROLE database role with CREATE SESSION"
show_and_run \
    "deepsec_admin/Oracle123@${PDB_NAME}" \
    "
CREATE ROLE direct_logon_role;
GRANT CREATE SESSION TO direct_logon_role;
"

step "Step 2 of 4 — Create HRAPP_EMPLOYEES and HRAPP_MANAGERS data roles"
show_and_run \
    "deepsec_admin/Oracle123@${PDB_NAME}" \
    "
CREATE DATA ROLE HRAPP_EMPLOYEES;
CREATE DATA ROLE HRAPP_MANAGERS;
"

step "Step 3 of 4 — Grant data roles to emma and marvin"
show_and_run \
    "deepsec_admin/Oracle123@${PDB_NAME}" \
    "
GRANT DATA ROLE HRAPP_EMPLOYEES TO emma;
GRANT DATA ROLE HRAPP_EMPLOYEES TO marvin;
GRANT DATA ROLE HRAPP_MANAGERS  TO marvin;
"

step "Step 4 of 4 — Grant DIRECT_LOGON_ROLE to both data roles, then verify"
show_and_run \
    "deepsec_admin/Oracle123@${PDB_NAME}" \
    "
GRANT direct_logon_role TO hrapp_employees;
GRANT direct_logon_role TO hrapp_managers;

-- Verify data role grants
COLUMN data_role    FORMAT A18 HEADING 'DATA_ROLE'
COLUMN role_type    FORMAT A15 HEADING 'ROLE_TYPE'
COLUMN grantee      FORMAT A15 HEADING 'GRANTEE'
COLUMN grantee_type FORMAT A10 HEADING 'GRNT_TYPE'
SELECT data_role, role_type, grantee, grantee_type
  FROM dba_data_role_grants;

-- Verify CREATE SESSION privilege
COLUMN grantee   FORMAT A17 HEADING 'GRANTEE'
COLUMN privilege FORMAT A14 HEADING 'PRIVILEGE'
SELECT grantee, privilege
  FROM dba_sys_privs
 WHERE grantee = 'DIRECT_LOGON_ROLE'
   AND privilege = 'CREATE SESSION';
"

pause

# ---------------------------------------------------------------------------
# Task 4: Create data grants
# ---------------------------------------------------------------------------
banner "Task 4: Create Data Grants for Employees and Managers"

step "Step 1 of 3 — Create employee data grant (own row, all columns, update phone/name)"
show_and_run \
    "deepsec_admin/Oracle123@${PDB_NAME}" \
    "
CREATE OR REPLACE DATA GRANT hr.HRAPP_EMPLOYEE_ACCESS
  AS SELECT, UPDATE(phone_number, first_name)
  ON hr.employees
  WHERE upper(user_name) = upper(ORA_END_USER_CONTEXT.username)
  TO HRAPP_EMPLOYEES;
"

step "Step 2 of 3 — Create manager data grant (direct reports, SSN excluded, update salary/dept/name)"
show_and_run \
    "deepsec_admin/Oracle123@${PDB_NAME}" \
    "
CREATE OR REPLACE DATA GRANT hr.HRAPP_MANAGER_ACCESS
  AS SELECT (ALL COLUMNS EXCEPT ssn), UPDATE (salary, department_id, first_name)
  ON hr.employees
  WHERE manager_id IN (
    SELECT m.manager_id
      FROM hr.managers m
     WHERE upper(m.mgr_user_name) = upper(ORA_END_USER_CONTEXT.username))
  TO hrapp_managers;
"

step "Step 3 of 3 — Verify data grants and predicates"
show_and_run \
    "deepsec_admin/Oracle123@${PDB_NAME}" \
    "
COLUMN column_name FORMAT A13 HEADING 'COLUMN'
COLUMN grant_name  FORMAT A22 HEADING 'GRANT_NAME'
COLUMN privilege   FORMAT A6  HEADING 'PRIV'
COLUMN grantee     FORMAT A16 HEADING 'GRANTEE'
SELECT column_name, grant_name, privilege, grantee
  FROM dba_data_grants
 WHERE object_owner = 'HR'
   AND object_name  = 'EMPLOYEES'
 ORDER BY grant_name, privilege, column_name;

COLUMN grant_name FORMAT A22  HEADING 'GRANT_NAME'
COLUMN predicate  FORMAT A120 HEADING 'PREDICATE' WORD_WRAPPED
SELECT DISTINCT grant_name, predicate
  FROM dba_data_grants
 WHERE object_owner = 'HR'
   AND object_name  = 'EMPLOYEES'
 ORDER BY grant_name;
"

pause

# ---------------------------------------------------------------------------
# Task 5: Connect as Emma
# ---------------------------------------------------------------------------
banner "Task 5: Connect as Emma (Employee)"

step "Step 1 — Resolve Emma's identity via ORA_END_USER_CONTEXT"
show_and_run \
    "emma/Oracle123@${PDB_NAME}" \
    "
COLUMN end_user FORMAT A10 HEADING 'END USER'
SELECT ORA_END_USER_CONTEXT.username AS end_user FROM DUAL;
"

step "Step 2 — Query all employees (no WHERE clause) — Emma sees only herself"
show_and_run \
    "emma/Oracle123@${PDB_NAME}" \
    "
COLUMN employee_id  FORMAT 99          HEADING 'ID'
COLUMN first_name   FORMAT A5          HEADING 'FIRST'
COLUMN last_name    FORMAT A5          HEADING 'LAST'
COLUMN user_name    FORMAT A4          HEADING 'USER'
COLUMN ssn          FORMAT A11         HEADING 'SSN'
COLUMN salary       FORMAT 999,999.99  HEADING 'SALARY'
COLUMN phone_number FORMAT A12         HEADING 'PHONE'
SELECT employee_id, first_name, last_name, user_name, ssn, salary, phone_number
  FROM hr.employees;
"

step "Step 3 — Explicitly request Marvin's row — returns nothing"
show_and_run \
    "emma/Oracle123@${PDB_NAME}" \
    "
COLUMN employee_id FORMAT 99          HEADING 'ID'
COLUMN first_name  FORMAT A6          HEADING 'FIRST'
COLUMN last_name   FORMAT A6          HEADING 'LAST'
COLUMN ssn         FORMAT A11         HEADING 'SSN'
COLUMN salary      FORMAT 999,999.99  HEADING 'SALARY'
SELECT employee_id, first_name, last_name, ssn, salary
  FROM hr.employees
 WHERE user_name = 'marvin';
"

step "Step 4 — COUNT(*) — returns 1 (only Emma's row)"
show_and_run \
    "emma/Oracle123@${PDB_NAME}" \
    "
SELECT COUNT(*) FROM hr.employees;
"

step "Step 5 — Update phone number (allowed) then rollback"
show_and_run \
    "emma/Oracle123@${PDB_NAME}" \
    "
UPDATE hr.employees SET phone_number = '555-555-5555' WHERE first_name = 'Emma';
ROLLBACK;
"

step "Step 6 — Attempt to update salary (not in data grant) — silently blocked"
show_and_run \
    "emma/Oracle123@${PDB_NAME}" \
    "
UPDATE hr.employees SET salary = 200000 WHERE first_name = 'Emma';
"

step "Step 7 — Attempt DELETE — ORA-41900 (no DELETE privilege)"
show_and_run \
    "emma/Oracle123@${PDB_NAME}" \
    "
DELETE FROM hr.employees;
"

pause

# ---------------------------------------------------------------------------
# Task 6: Connect as Marvin
# ---------------------------------------------------------------------------
banner "Task 6: Connect as Marvin (Manager)"

step "Step 1 — Resolve Marvin's identity via ORA_END_USER_CONTEXT"
show_and_run \
    "marvin/Oracle123@${PDB_NAME}" \
    "
COLUMN end_user FORMAT A10 HEADING 'END USER'
SELECT ORA_END_USER_CONTEXT.username AS end_user FROM DUAL;
"

step "Step 2 — Query all employees (no WHERE clause) — Marvin sees himself + 3 direct reports"
show_and_run \
    "marvin/Oracle123@${PDB_NAME}" \
    "
COLUMN employee_id  FORMAT 99          HEADING 'ID'
COLUMN first_name   FORMAT A7          HEADING 'FIRST'
COLUMN ssn          FORMAT A11         HEADING 'SSN'
COLUMN phone_number FORMAT A12         HEADING 'PHONE'
COLUMN salary       FORMAT 999,999.99  HEADING 'SALARY'
SELECT employee_id, first_name, ssn, phone_number, salary
  FROM hr.employees;
"

step "Step 3 — Explicitly request Grace's row (outside Marvin's scope) — returns nothing"
show_and_run \
    "marvin/Oracle123@${PDB_NAME}" \
    "
COLUMN employee_id FORMAT 99          HEADING 'ID'
COLUMN first_name  FORMAT A5          HEADING 'FIRST'
COLUMN last_name   FORMAT A5          HEADING 'LAST'
COLUMN ssn         FORMAT A11         HEADING 'SSN'
COLUMN salary      FORMAT 999,999.99  HEADING 'SALARY'
SELECT employee_id, first_name, last_name, ssn, salary
  FROM hr.employees
 WHERE user_name = 'grace';
"

step "Step 4 — COUNT(*) — returns 4 (Marvin + 3 direct reports)"
show_and_run \
    "marvin/Oracle123@${PDB_NAME}" \
    "
SELECT COUNT(*) FROM hr.employees;
"

step "Step 5 — Update Emma's salary (allowed by manager grant) then rollback"
show_and_run \
    "marvin/Oracle123@${PDB_NAME}" \
    "
UPDATE hr.employees SET salary = salary * 1.5 WHERE first_name = 'Emma';
ROLLBACK;
"

step "Step 6 — Attempt to update Emma's phone number (not in manager grant) — silently blocked"
show_and_run \
    "marvin/Oracle123@${PDB_NAME}" \
    "
UPDATE hr.employees SET phone_number = '555-444-4444' WHERE first_name = 'Emma';
"

step "Step 7 — Attempt DELETE — ORA-41900 (no DELETE privilege)"
show_and_run \
    "marvin/Oracle123@${PDB_NAME}" \
    "
DELETE FROM hr.employees;
"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
banner "Lab Complete"
echo "  The trust chain is in place:"
echo "    End user authentication -> DATA ROLE -> DATA GRANT enforcement"
echo ""
echo "  To clean up, run Task 7 (optional):"
echo "    Connect as deepsec_admin, drop data grants, roles, end users, and HR schema."
echo ""
echo "  See end-user-data-grants.md Task 7 for the cleanup SQL."
echo ""
