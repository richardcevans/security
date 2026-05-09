#!/bin/bash
# =========================================================================================
# Script Name : 03_create_hr_schema.sh
#
# Parameter   : None
#
# Notes       : Task 9 - Create the HR schema and employee data.
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
NC='\033[0m'

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 9: Create the HR Schema and Employee Data                        ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}HR is created with NO AUTHENTICATION — it is a schema-only account.${NC}"
echo -e "${PURPLE}It owns the data but cannot log in. End users connect via Entra ID.${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"
export DBUSR_SYSTEM="${DBUSR_SYSTEM:-system}"
export DBUSR_PWD="${DBUSR_PWD:-Oracle123}"

if [ -z "${DOMAIN_NAME:-}" ]; then
  echo -e "\033[0;31mERROR: DOMAIN_NAME is not set.\033[0m"
  echo -e "  Set it before running this script:"
  echo -e "  export DOMAIN_NAME=yourtenant.onmicrosoft.com"
  exit 1
fi

echo -e "${YELLOW}Creating HR schema and employees...${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${DBUSR_SYSTEM}/******@${PDB_NAME}${NC}"
echo

sqlplus -s ${DBUSR_SYSTEM}/${DBUSR_PWD}@${PDB_NAME} <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999

prompt
prompt ========================================================================
prompt Creating HR Schema (NO AUTHENTICATION)
prompt ========================================================================

show user;
show con_name;

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
prompt Updating user_name to Entra ID email addresses
prompt ========================================================================

UPDATE hr.employees
   SET user_name = user_name || '@${DOMAIN_NAME}'
 WHERE user_name NOT LIKE '%@%';

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

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 9 Completed: HR Schema Created!                                  ${NC}"
echo -e "${GREEN}      7 employees with full Entra ID email addresses as user_name.           ${NC}"
echo -e "${GREEN}      Next: run 04_create_data_roles_and_grants.sh                           ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
