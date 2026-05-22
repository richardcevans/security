#!/bin/bash
# =========================================================================================
# Script Name : 03_create_hr_schema.sh
#
# Parameter   : None
#
# Notes       : Task 3 - Create the HR schema and employee data.
#               Creates HR with NO AUTHENTICATION (schema-only) and
#               populates the EMPLOYEES table with 7 sample rows.
#
# Modified by         Date         Change
# Oracle DB Security  04/02/2026   Creation
# =========================================================================================

# Define colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 3: Create the HR Schema and Employee Data                        ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}HR is created with NO AUTHENTICATION — it is a schema-only account.${NC}"
echo -e "${PURPLE}It owns the data but cannot log in. End users connect via OCI IAM.${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-FREEPDB1}"
export DB_SID="${DB_SID:-FREE}"
export ORACLE_SID="$DB_SID"

export OCI_USERNAME_DOMAIN="${OCI_USERNAME_DOMAIN:-}"

echo -e "${YELLOW}Creating HR schema and employees...${NC}"
echo -e "${CYAN}ORACLE_SID = ${ORACLE_SID}${NC}"
echo -e "${CYAN}Executing: sqlplus -s / as sysdba${NC}"
echo

if ! sqlplus -s / as sysdba <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999
whenever sqlerror exit sql.sqlcode

BEGIN
  EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE ${PDB_NAME} OPEN';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -65019 THEN
      RAISE;
    END IF;
END;
/

ALTER SESSION SET CONTAINER = ${PDB_NAME};

prompt
prompt ========================================================================
prompt Creating HR Schema (NO AUTHENTICATION)
prompt ========================================================================

show user;
show con_name;

prompt DROP USER hr CASCADE;
BEGIN
  EXECUTE IMMEDIATE 'DROP USER hr CASCADE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1918 THEN
      RAISE;
    END IF;
END;
/

prompt CREATE USER hr NO AUTHENTICATION;
CREATE USER hr NO AUTHENTICATION;
prompt GRANT UNLIMITED TABLESPACE TO hr;
GRANT UNLIMITED TABLESPACE TO hr;

prompt
prompt ========================================================================
prompt Creating EMPLOYEES Table
prompt ========================================================================

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

prompt
prompt ========================================================================
prompt Inserting Sample Employees
prompt ========================================================================

-- CEO
INSERT INTO hr.employees VALUES (1, 'Grace', 'Young', 'CEO', NULL, '111-11-1111', NULL, '555-100-0001', 235000, 'grace', NULL);
-- Manager
INSERT INTO hr.employees VALUES (2, 'Marvin', 'Morgan', 'SWE_MGR', 1, '222-22-2222', NULL, '555-100-0002', 175000, 'marvin', 1);
-- Marvin's team
INSERT INTO hr.employees VALUES (3, 'Emma', 'Baker', 'SWE2', 1, '333-33-3333', NULL, '555-100-0003', 120000, 'emma', 2);
INSERT INTO hr.employees VALUES (4, 'Charlie', 'Davis', 'SWE1', 1, '444-44-4444', NULL, '555-100-0004', 95000, 'charlie', 2);
INSERT INTO hr.employees VALUES (5, 'Dana', 'Lee', 'SWE3', 1, '555-55-5555', NULL, '555-100-0005', 130000, 'dana', 2);
-- Other departments
INSERT INTO hr.employees VALUES (6, 'Bob', 'Smith', 'SALES_REP', 2, '666-66-6666', NULL, '555-100-0006', 145000, 'bob', 1);
INSERT INTO hr.employees VALUES (7, 'Fiona', 'Chen', 'HR_REP', 3, '777-77-7777', NULL, '555-100-0007', 92000, 'fiona', 1);

COMMIT;

prompt
prompt ========================================================================
prompt Updating user_name to OCI IAM user names
prompt ========================================================================

-- If OCI_USERNAME_DOMAIN is set, convert marvin to marvin@example.com.
-- If it is empty, keep simple OCI IAM usernames such as marvin and emma.
UPDATE hr.employees
   SET user_name =
       CASE
         WHEN '${OCI_USERNAME_DOMAIN}' IS NOT NULL
          AND LENGTH('${OCI_USERNAME_DOMAIN}') > 0
          AND user_name NOT LIKE '%@%'
         THEN user_name || '@${OCI_USERNAME_DOMAIN}'
         ELSE user_name
       END;

COMMIT;

prompt
prompt ========================================================================
prompt Verify: All 7 Employees Visible (as DBA)
prompt ========================================================================

col first_name  format a12
col last_name   format a12
col user_name   format a45
col ssn         format a15
col salary      format 999,999.99

SELECT employee_id, first_name, last_name, user_name, ssn, salary, manager_id
  FROM hr.employees
 ORDER BY employee_id;

exit;
EOF
then
    echo
    echo -e "${RED}ERROR: Could not create HR schema in ${PDB_NAME}.${NC}"
    echo -e "${YELLOW}Check ORACLE_SID, PDB_NAME, and the SQL output above.${NC}"
    exit 1
fi

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 3 Completed: HR Schema Created!                                  ${NC}"
echo -e "${GREEN}      7 employees with OCI IAM user names as user_name.                     ${NC}"
echo -e "${GREEN}      Next: run 04_create_data_roles_and_grants.sh                           ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
