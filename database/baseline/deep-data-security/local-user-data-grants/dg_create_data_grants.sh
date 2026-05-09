#!/bin/bash
# =========================================================================================
# Script Name : dg_create_data_grants.sh
#
# Parameter   : None
#
# Notes       : Task 4 - Create data grants.
#               Creates the employee data grant, end user context and initialization
#               package, grants context privileges, and creates the manager data grant.
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
echo -e "${GREEN}      Task 4: Create Data Grants                                            ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"
export DBUSR_SYSTEM="${DBUSR_SYSTEM:-system}"
export DBUSR_SYS="${DBUSR_SYS:-sys}"
export DBUSR_PWD="${DBUSR_PWD:-Oracle123}"

CONN_DISPLAY="${DBUSR_SYSTEM}/******@${PDB_NAME}"

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Steps 1-3: Create data grants and context as SYSTEM
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Steps 1-3: Creating data grants and end user context...${NC}"
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
prompt Step 1: Create the Employee Data Grant (HRAPP_EMPLOYEES_ACCESS)
prompt  - Employees see only their own row.
prompt  - SELECT on specific columns, UPDATE on phone_number only.
prompt  - Predicate uses ora_end_user_context.username for identity.
prompt ========================================================================

prompt CREATE OR REPLACE DATA GRANT hr.HRAPP_EMPLOYEES_ACCESS AS SELECT (employee_id, first_name, last_name, user_name, department_id, manager_id, ssn, salary, phone_number), UPDATE(phone_number) ON hr.employees WHERE upper(user_name) = upper(ora_end_user_context.username) TO HRAPP_EMPLOYEES;
CREATE OR REPLACE DATA GRANT hr.HRAPP_EMPLOYEES_ACCESS
  AS SELECT (employee_id, first_name, last_name, user_name, department_id, manager_id, ssn, salary, phone_number), UPDATE(phone_number)
  ON hr.employees
  WHERE upper(user_name) = upper(ora_end_user_context.username)
  TO HRAPP_EMPLOYEES;

prompt
prompt ========================================================================
prompt Step 2: Create the End User Context and Initialization Package
prompt  - EMP_CTX stores the current user's employee_id.
prompt  - Resolved via o:onFirstRead trigger at session start.
prompt  - Used by the manager data grant predicate.
prompt ========================================================================

prompt CREATE OR REPLACE END USER CONTEXT HR.EMP_CTX USING JSON SCHEMA '{"type":"object","properties":{"ID":{"type":"integer","o:onFirstRead":"HR.ctx_pkg.init_user_context"}}}';
CREATE OR REPLACE END USER CONTEXT HR.EMP_CTX USING JSON SCHEMA '{
  "type": "object",
  "properties": {
    "ID": {
      "type": "integer",
      "o:onFirstRead": "HR.ctx_pkg.init_user_context"
    }
  }
}';

prompt CREATE OR REPLACE PACKAGE hr.ctx_pkg AS PROCEDURE init_user_context; END;
CREATE OR REPLACE PACKAGE hr.ctx_pkg AS
  PROCEDURE init_user_context;
END;
/

prompt CREATE OR REPLACE PACKAGE BODY hr.ctx_pkg AS PROCEDURE init_user_context IS sql_stmt VARCHAR2(4000); BEGIN EXECUTE IMMEDIATE sql_stmt; END; END;
CREATE OR REPLACE PACKAGE BODY hr.ctx_pkg AS
  PROCEDURE init_user_context IS
    sql_stmt VARCHAR2(4000);
  BEGIN
    sql_stmt := '
      UPDATE END_USER_CONTEXT t
      SET t.CONTEXT.ID = (
         SELECT e.employee_id
         FROM hr.employees e
         WHERE upper(e.user_name) = upper(ora_end_user_context.USERNAME)
       )
      WHERE owner = ''HR''
      AND name = ''EMP_CTX'';
    ';
    EXECUTE IMMEDIATE sql_stmt;
  END;
END;
/

prompt
prompt ========================================================================
prompt Step 3: Grant Context Privileges
prompt  - Grant HR the ability to create and update end user contexts.
prompt  - Create a database role for EXECUTE on the context package.
prompt  - Grant the role to both data roles so o:onFirstRead can fire.
prompt ========================================================================

prompt GRANT UPDATE ANY END USER CONTEXT TO HR;
GRANT UPDATE ANY END USER CONTEXT TO HR;
prompt GRANT CREATE ANY END USER CONTEXT TO HR;
GRANT CREATE ANY END USER CONTEXT TO HR;

prompt CREATE ROLE IF NOT EXISTS employee_context_admin;
CREATE ROLE IF NOT EXISTS employee_context_admin;
prompt GRANT EXECUTE ON hr.ctx_pkg TO employee_context_admin;
GRANT EXECUTE ON hr.ctx_pkg TO employee_context_admin;
prompt GRANT employee_context_admin TO HRAPP_EMPLOYEES;
GRANT employee_context_admin TO HRAPP_EMPLOYEES;
prompt GRANT employee_context_admin TO HRAPP_MANAGERS;
GRANT employee_context_admin TO HRAPP_MANAGERS;

exit;
EOF

echo
echo -e "${YELLOW}Creating the data grant on SYS.END_USER_CONTEXT...${NC}"
echo -e "${PURPLE}NOTE: This must run as SYS because it grants access to a SYS-owned table.${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${DBUSR_SYS}/******@${PDB_NAME} as sysdba${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Data grant on SYS.END_USER_CONTEXT (requires SYS)
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
sqlplus -s ${DBUSR_SYS}/${DBUSR_PWD}@${PDB_NAME} as sysdba <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999

prompt
prompt ========================================================================
prompt Creating Data Grant on SYS.END_USER_CONTEXT
prompt  - Allows end user sessions to read their context attributes.
prompt ========================================================================

show user;
show con_name;

prompt CREATE OR REPLACE DATA GRANT hr.EMPLOYEE_CONTEXT_GRANT AS SELECT ON SYS.END_USER_CONTEXT WHERE OWNER = 'HR' AND NAME = 'EMP_CTX' TO HRAPP_EMPLOYEES, HRAPP_MANAGERS;
CREATE OR REPLACE DATA GRANT hr.EMPLOYEE_CONTEXT_GRANT
  AS SELECT ON SYS.END_USER_CONTEXT
   WHERE OWNER = 'HR' AND NAME = 'EMP_CTX'
    TO HRAPP_EMPLOYEES, HRAPP_MANAGERS;

exit;
EOF

echo
echo -e "${YELLOW}Continuing setup as DBA user...${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${CONN_DISPLAY}${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Step 4: Manager data grant as SYSTEM
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
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
prompt Step 4: Create the Manager Data Grant (HRAPP_MANAGER_ACCESS)
prompt  - Managers see their own row + direct reports.
prompt  - SELECT on ALL COLUMNS EXCEPT ssn.
prompt  - UPDATE on salary and department_id for direct reports.
prompt  - Predicate matches manager_id to the authenticated user's employee_id.
prompt ========================================================================

prompt CREATE OR REPLACE DATA GRANT hr.HRAPP_MANAGER_ACCESS AS SELECT (ALL COLUMNS EXCEPT ssn), UPDATE (salary, department_id) ON hr.employees WHERE manager_id = ORA_END_USER_CONTEXT.HR.EMP_CTX.ID TO HRAPP_MANAGERS;
CREATE OR REPLACE DATA GRANT hr.HRAPP_MANAGER_ACCESS
  AS SELECT (ALL COLUMNS EXCEPT ssn), UPDATE (salary, department_id)
  ON hr.employees
  WHERE manager_id = ORA_END_USER_CONTEXT.HR.EMP_CTX.ID
  TO HRAPP_MANAGERS;

exit;
EOF

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 4 Completed: Data Grants Created!                                ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
