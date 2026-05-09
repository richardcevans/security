#!/bin/bash
# =========================================================================================
# Script Name : 02_show_traditional_app.sh
#
# Parameter   : None
#
# Notes       : Task 1 (continued) - Show the traditional app pattern.
#               Demonstrates that a shared service account (HR) sees all
#               data regardless of who is actually using the application.
#               This is the security problem you are about to fix.
#
# Modified by         Date         Change
# Oracle DB Security  01/04/2026   Creation
# =========================================================================================

# Define colors for readability (only used in Bash, not inside SQL*Plus)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      The Traditional App: What Your AI Agent Sees Today                    ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"
export DBUSR_PWD="${DBUSR_PWD:-Oracle123}"

echo -e "${PURPLE}Your AI agent connects as the shared service account HR.${NC}"
echo -e "${PURPLE}It runs: SELECT * FROM employees${NC}"
echo -e "${PURPLE}It does not matter who asked — Marvin, Emma, or a stranger.${NC}"
echo -e "${PURPLE}The result is always the same: EVERYTHING.${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Connect as HR and run the query
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Connecting as HR (shared service account)...${NC}"
echo -e "${CYAN}Executing: sqlplus -s hr/******@${PDB_NAME}${NC}"
echo

sqlplus -s hr/${DBUSR_PWD}@${PDB_NAME} <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999
col first_name  format a12
col last_name   format a12
col ssn         format a15
col salary      format 999,999.99

prompt
prompt ========================================================================
prompt Connected as HR — the shared service account
prompt ========================================================================

show user;

prompt
prompt ========================================================================
prompt Running: SELECT * FROM employees (as HR)
prompt  - This is what your AI agent sends to the database.
prompt  - HR sees ALL 7 rows, ALL columns, ALL SSNs, ALL salaries.
prompt ========================================================================

SELECT employee_id, first_name, last_name, ssn, salary, department_id, manager_id
  FROM hr.employees
 ORDER BY employee_id;

exit;
EOF

echo
echo -e "${RED}============================================================================${NC}"
echo -e "${RED}  The shared service account sees EVERYTHING.                               ${NC}"
echo -e "${RED}  Every SSN. Every salary. Every employee across every department.          ${NC}"
echo -e "${RED}                                                                            ${NC}"
echo -e "${RED}  If your AI agent is compromised, ALL data is exposed.                     ${NC}"
echo -e "${RED}  If a new endpoint skips filtering, ALL data leaks.                        ${NC}"
echo -e "${RED}  The database trusts the app to filter. That trust is fragile.             ${NC}"
echo -e "${RED}============================================================================${NC}"
echo
echo -e "${GREEN}      Next: Run 03_migrate_db_objects.sh to migrate to Deep Data Security.  ${NC}"
echo
