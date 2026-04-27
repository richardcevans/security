#!/bin/bash
# =========================================================================================
# Script Name : 01_create_hr_schema.sh
#
# Parameter   : None
#
# Notes       : Task 1 - Create the traditional HR schema.
#               Creates the HR schema WITH authentication (the "before" state),
#               the EMPLOYEES table, inserts sample data, and grants SELECT
#               to HR — simulating a traditional shared service account.
#
# Modified by         Date         Change
# Oracle DB Security  01/04/2026   Creation
# =========================================================================================

# Define colors for readability (only used in Bash, not inside SQL*Plus)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 1: Create the Traditional HR Schema (Before Migration)           ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}This creates the 'before' state: HR is a traditional schema user that${NC}"
echo -e "${PURPLE}owns and can log into the database. Any application connecting as HR${NC}"
echo -e "${PURPLE}sees ALL data — SSNs, salaries, everything.${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"
export DBUSR_SYSTEM="${DBUSR_SYSTEM:-system}"
export DBUSR_PWD="${DBUSR_PWD:-Oracle123}"

CONN_DISPLAY="${DBUSR_SYSTEM}/******@${PDB_NAME}"

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Step 1: Create the traditional HR schema
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Step 1: Creating the traditional HR schema with password authentication...${NC}"
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
prompt Creating the Traditional HR Schema
prompt  - HR has a PASSWORD — it can log in directly.
prompt  - This is the typical shared service account pattern.
prompt ========================================================================

DECLARE
  v_exists      NUMBER;
  v_backup_name VARCHAR2(30);
BEGIN
  SELECT COUNT(*) INTO v_exists FROM dba_users WHERE username = 'HR';
  IF v_exists > 0 THEN
    DBMS_OUTPUT.PUT_LINE('WARNING: User HR already exists - skipping CREATE USER.');
  ELSE
    EXECUTE IMMEDIATE 'CREATE USER hr IDENTIFIED BY Oracle123';
    DBMS_OUTPUT.PUT_LINE('Created user HR.');
  END IF;
  EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO hr';
  EXECUTE IMMEDIATE 'GRANT UNLIMITED TABLESPACE TO hr';

  SELECT COUNT(*) INTO v_exists FROM dba_tables
   WHERE owner = 'HR' AND table_name = 'EMPLOYEES';
  IF v_exists > 0 THEN
    v_backup_name := 'EMP_' || TO_CHAR(SYSDATE,'YYYYMMDDHH24MISS');
    EXECUTE IMMEDIATE 'ALTER TABLE hr.employees RENAME TO ' || v_backup_name;
    DBMS_OUTPUT.PUT_LINE('Table hr.employees existed and was backed up to hr.' || v_backup_name);
  END IF;
END;
/

prompt
prompt ========================================================================
prompt Creating the HR.EMPLOYEES Table
prompt  - Contains sensitive data: SSN, salary, management hierarchy.
prompt ========================================================================

prompt CREATE TABLE hr.employees (...);
CREATE TABLE hr.employees (
  employee_id   NUMBER PRIMARY KEY,
  first_name    VARCHAR2(50),
  last_name     VARCHAR2(50),
  job_code      VARCHAR2(10),
  department_id NUMBER,
  ssn           VARCHAR2(20),
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
prompt INSERT INTO hr.employees VALUES (1, 'Grace', 'Young', ...);
INSERT INTO hr.employees VALUES (1, 'Grace', 'Young', 'CEO', NULL, '111-11-1111', '555-100-0001', 235000, 'grace', NULL);

-- Manager
prompt INSERT INTO hr.employees VALUES (2, 'Marvin', 'Morgan', ...);
INSERT INTO hr.employees VALUES (2, 'Marvin', 'Morgan', 'SWE_MGR', 1, '222-22-2222', '555-100-0002', 175000, 'marvin', 1);

-- Marvin's team
prompt INSERT INTO hr.employees VALUES (3, 'Emma', 'Baker', ...);
INSERT INTO hr.employees VALUES (3, 'Emma', 'Baker', 'SWE2', 1, '333-33-3333', '555-100-0003', 120000, 'emma', 2);
prompt INSERT INTO hr.employees VALUES (4, 'Charlie', 'Davis', ...);
INSERT INTO hr.employees VALUES (4, 'Charlie', 'Davis', 'SWE1', 1, '444-44-4444', '555-100-0004', 95000, 'charlie', 2);
prompt INSERT INTO hr.employees VALUES (5, 'Dana', 'Lee', ...);
INSERT INTO hr.employees VALUES (5, 'Dana', 'Lee', 'SWE3', 1, '555-55-5555', '555-100-0005', 130000, 'dana', 2);

-- Other departments
prompt INSERT INTO hr.employees VALUES (6, 'Bob', 'Smith', ...);
INSERT INTO hr.employees VALUES (6, 'Bob', 'Smith', 'SALES_REP', 2, '666-66-6666', '555-100-0006', 145000, 'bob', 1);
prompt INSERT INTO hr.employees VALUES (7, 'Fiona', 'Chen', ...);
INSERT INTO hr.employees VALUES (7, 'Fiona', 'Chen', 'HR_REP', 3, '777-77-7777', '555-100-0007', 92000, 'fiona', 1);

prompt COMMIT;
COMMIT;

prompt
prompt ========================================================================
prompt Verifying: Connecting as HR and running SELECT * FROM employees
prompt  - HR sees ALL 7 rows, ALL columns, ALL SSNs, ALL salaries.
prompt  - This is the problem: any app connecting as HR sees everything.
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
echo -e "${GREEN}      Task 1 Completed: Traditional HR Schema Created!                      ${NC}"
echo -e "${GREEN}      HR can log in and sees ALL data. This is the 'before' state.          ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
