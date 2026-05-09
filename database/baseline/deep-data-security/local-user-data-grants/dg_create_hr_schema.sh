#!/bin/bash
# =========================================================================================
# Script Name : dg_create_hr_schema.sh
#
# Parameter   : None
#
# Notes       : Task 1 - Create the HR schema and sensitive employee data.
#               Creates the HR schema-only account, the EMPLOYEES table, and
#               inserts sample rows, then verifies all data is visible.
#
# Modified by         Date         Change
# Oracle DB Security  18/03/2026   Creation
# =========================================================================================

# Define colors for readability (only used in Bash, not inside SQL*Plus)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 1: Create the HR Schema and Sensitive Employee Data              ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"
export DBUSR_SYSTEM="${DBUSR_SYSTEM:-system}"
export DBUSR_PWD="${DBUSR_PWD:-Oracle123}"

CONN_DISPLAY="${DBUSR_SYSTEM}/******@${PDB_NAME}"

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Step 1: Create the HR schema, EMPLOYEES table, and insert sample data
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Step 1: Creating the HR schema and EMPLOYEES table with sample data...${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${CONN_DISPLAY}${NC}"
echo

sqlplus -s ${DBUSR_SYSTEM}/${DBUSR_PWD}@${PDB_NAME} <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999

prompt
prompt ========================================================================
prompt Verify Current Database User and Container
prompt ========================================================================

show user;
show con_name;

prompt
prompt ========================================================================
prompt Creating the HR Schema (no-authentication account)
prompt  - HR is a schema-only account that owns the employee data.
prompt  - It does not log in directly.
prompt ========================================================================

prompt CREATE USER hr NO AUTHENTICATION;
CREATE USER hr NO AUTHENTICATION;
prompt GRANT UNLIMITED TABLESPACE TO hr;
GRANT UNLIMITED TABLESPACE TO hr;

prompt
prompt ========================================================================
prompt Creating the HR.EMPLOYEES Table
prompt  - Contains sensitive data: SSN, salary, management hierarchy.
prompt  - This is the table your AI copilot will query.
prompt ========================================================================

prompt CREATE TABLE hr.employees (employee_id NUMBER PRIMARY KEY, first_name VARCHAR2(50), last_name VARCHAR2(50), job_code VARCHAR2(10), department_id NUMBER, ssn VARCHAR2(20), photo BLOB, phone_number VARCHAR2(30), salary NUMBER(10,2), user_name VARCHAR2(128), manager_id NUMBER);
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

prompt
prompt ========================================================================
prompt Inserting Sample Employee Data
prompt  - 7 employees across CEO, management, engineering, sales, and HR.
prompt  - Marvin (employee 2) manages Emma, Charlie, and Dana.
prompt ========================================================================

-- CEO
prompt INSERT INTO hr.employees VALUES (1, 'Grace', 'Young', 'CEO', NULL, '111-11-1111', NULL, '555-100-0001', 235000, 'grace', NULL);
INSERT INTO hr.employees VALUES (1, 'Grace', 'Young', 'CEO', NULL, '111-11-1111', NULL, '555-100-0001', 235000, 'grace', NULL);

-- Manager
prompt INSERT INTO hr.employees VALUES (2, 'Marvin', 'Morgan', 'SWE_MGR', 1, '222-22-2222', NULL, '555-100-0002', 175000, 'marvin', 1);
INSERT INTO hr.employees VALUES (2, 'Marvin', 'Morgan', 'SWE_MGR', 1, '222-22-2222', NULL, '555-100-0002', 175000, 'marvin', 1);

-- Marvin's team
prompt INSERT INTO hr.employees VALUES (3, 'Emma', 'Baker', 'SWE2', 1, '333-33-3333', NULL, '555-100-0003', 120000, 'emma', 2);
INSERT INTO hr.employees VALUES (3, 'Emma', 'Baker', 'SWE2', 1, '333-33-3333', NULL, '555-100-0003', 120000, 'emma', 2);
prompt INSERT INTO hr.employees VALUES (4, 'Charlie', 'Davis', 'SWE1', 1, '444-44-4444', NULL, '555-100-0004', 95000, 'charlie', 2);
INSERT INTO hr.employees VALUES (4, 'Charlie', 'Davis', 'SWE1', 1, '444-44-4444', NULL, '555-100-0004', 95000, 'charlie', 2);
prompt INSERT INTO hr.employees VALUES (5, 'Dana', 'Lee', 'SWE3', 1, '555-55-5555', NULL, '555-100-0005', 130000, 'dana', 2);
INSERT INTO hr.employees VALUES (5, 'Dana', 'Lee', 'SWE3', 1, '555-55-5555', NULL, '555-100-0005', 130000, 'dana', 2);

-- Other departments
prompt INSERT INTO hr.employees VALUES (6, 'Bob', 'Smith', 'SALES_REP', 2, '666-66-6666', NULL, '555-100-0006', 145000, 'bob', 1);
INSERT INTO hr.employees VALUES (6, 'Bob', 'Smith', 'SALES_REP', 2, '666-66-6666', NULL, '555-100-0006', 145000, 'bob', 1);
prompt INSERT INTO hr.employees VALUES (7, 'Fiona', 'Chen', 'HR_REP', 3, '777-77-7777', NULL, '555-100-0007', 92000, 'fiona', 1);
INSERT INTO hr.employees VALUES (7, 'Fiona', 'Chen', 'HR_REP', 3, '777-77-7777', NULL, '555-100-0007', 92000, 'fiona', 1);

prompt COMMIT;
COMMIT;

prompt
prompt ========================================================================
prompt Step 2: Verifying All Data Is Visible
prompt  - You should see all 7 rows with full SSN values.
prompt  - Right now, anyone with access sees everything.
prompt  - That is the problem you are about to fix.
prompt ========================================================================

col first_name  format a12
col last_name   format a12
col ssn         format a15
col salary      format 999,999.99

SELECT employee_id, first_name, last_name, ssn, salary, department_id, manager_id
  FROM hr.employees
 ORDER BY employee_id;

exit;
EOF

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 1 Completed: HR Schema and Employee Data Created!                ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
