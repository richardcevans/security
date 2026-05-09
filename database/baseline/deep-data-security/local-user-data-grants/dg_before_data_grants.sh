#!/bin/bash
# =========================================================================================
# Script Name : dg_before_data_grants.sh
#
# Parameter   : None
#
# Notes       : Task 2 - See what happens without data grants.
#               Demonstrates what happens when end users connect without
#               data grants — they see nothing. Explains why data grants
#               are fundamentally different from VPD, RAS, and other
#               application-centric security approaches.
#
# Modified by         Date         Change
# Oracle DB Security  18/03/2026   Creation
# =========================================================================================

# Define colors for readability (only used in Bash, not inside SQL*Plus)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Set defaults for environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"
export DBUSR_SYSTEM="${DBUSR_SYSTEM:-system}"
export DBUSR_PWD="${DBUSR_PWD:-Oracle123}"

CONN_DISPLAY="${DBUSR_SYSTEM}/******@${PDB_NAME}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      What Happens Without Data Grants?                                     ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}Before creating any data grants, let's see what an end user can access.${NC}"
echo -e "${PURPLE}We will create a temporary end user, give them CREATE SESSION, and try${NC}"
echo -e "${PURPLE}to query hr.employees — the same table your AI agent would query.${NC}"
echo

# =====================================================================
# Step 1: Create a temporary end user with only CREATE SESSION
# =====================================================================
echo -e "${YELLOW}Step 1: Creating a temporary end user with only CREATE SESSION...${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${CONN_DISPLAY}${NC}"
echo

sqlplus -s ${DBUSR_SYSTEM}/${DBUSR_PWD}@${PDB_NAME} <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999

prompt
prompt ========================================================================
prompt Creating Temporary End User and Logon Role
prompt  - The end user can authenticate but has no data grants.
prompt  - This is what your AI agent's users look like before you define
prompt    a security policy.
prompt ========================================================================

prompt CREATE END USER temp_user IDENTIFIED BY Oracle123;
CREATE END USER temp_user IDENTIFIED BY Oracle123;
prompt CREATE OR REPLACE DATA ROLE temp_role;
CREATE OR REPLACE DATA ROLE temp_role;
prompt CREATE ROLE temp_logon_role;
CREATE ROLE temp_logon_role;
prompt GRANT CREATE SESSION TO temp_logon_role;
GRANT CREATE SESSION TO temp_logon_role;
prompt GRANT temp_logon_role TO temp_role;
GRANT temp_logon_role TO temp_role;
prompt GRANT DATA ROLE temp_role TO temp_user;
GRANT DATA ROLE temp_role TO temp_user;

exit;
EOF

# =====================================================================
# Step 2: Connect as the end user and try the query
# =====================================================================
echo
echo -e "${YELLOW}Step 2: Connecting as temp_user and running the same SELECT...${NC}"
echo -e "${CYAN}Executing: sqlplus -s temp_user/******@${PDB_NAME}${NC}"
echo

sqlplus -s temp_user/Oracle123@${PDB_NAME} <<EOF

set echo off
set feedback on
set serveroutput on
set lines 130
set pages 9999
col first_name  format a12
col last_name   format a12
col ssn         format a15
col salary      format 999,999.99

prompt
prompt ========================================================================
prompt Running: SELECT * FROM hr.employees
prompt  - No data grants exist for this end user.
prompt  - What will happen?
prompt ========================================================================

SELECT employee_id, first_name, last_name, ssn, salary, department_id, manager_id
  FROM hr.employees
 ORDER BY employee_id;

exit;
EOF

echo
echo -e "${RED}============================================================================${NC}"
echo -e "${RED}  The end user sees NOTHING. ORA-00942: table or view does not exist.       ${NC}"
echo -e "${RED}  Without a data grant, the table is completely invisible to end users.     ${NC}"
echo -e "${RED}============================================================================${NC}"
echo

# =====================================================================
# Step 3: Explain why this matters
# =====================================================================
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Why Data Grants Are Different                                         ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${YELLOW}Traditional approaches attach security to the QUERY side:${NC}"
echo
echo -e "  ${CYAN}VPD (Virtual Private Database)${NC}"
echo -e "    A PL/SQL function appends a WHERE clause to every query at parse time."
echo -e "    The policy is on the TABLE — it rewrites your SQL behind the scenes."
echo -e "    If the function has a bug, data leaks. If a DBA grants SELECT on"
echo -e "    the table directly, the policy can be bypassed."
echo
echo -e "  ${CYAN}RAS (Real Application Security)${NC}"
echo -e "    ACLs and security classes control access through an application session."
echo -e "    The policy is on the APPLICATION — the app must create and manage"
echo -e "    the security context. Direct SQL access bypasses the controls."
echo
echo -e "  ${CYAN}Label Security (OLS)${NC}"
echo -e "    Row labels and user clearances filter data."
echo -e "    The policy is on the ROW — but privileged users with the right"
echo -e "    labels or FULL access can override it."
echo
echo -e "${GREEN}----------------------------------------------------------------------------${NC}"
echo
echo -e "${YELLOW}Data grants attach security to the GRANT itself:${NC}"
echo
echo -e "  ${CYAN}Data Grants (Deep Data Security)${NC}"
echo -e "    The grant declares WHAT data a role can see, WHICH columns,"
echo -e "    and WHICH rows — in a single statement. There is no policy function"
echo -e "    to get wrong. There is no application session to manage. There is"
echo -e "    no traditional GRANT SELECT that could bypass it."
echo
echo -e "    The security is not on the table. It is not on the query."
echo -e "    It is not on the application. ${GREEN}It is on the grant.${NC}"
echo
echo -e "    An end user without a data grant has ZERO access — as you just saw."
echo -e "    Access must be explicitly granted. There is nothing to bypass."
echo
echo -e "${GREEN}============================================================================${NC}"
echo

# =====================================================================
# Step 4: Clean up temporary objects
# =====================================================================
echo -e "${YELLOW}Cleaning up temporary objects...${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${CONN_DISPLAY}${NC}"
echo

sqlplus -s ${DBUSR_SYSTEM}/${DBUSR_PWD}@${PDB_NAME} <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999

prompt DROP END USER temp_user;
DROP END USER temp_user;
prompt DROP DATA ROLE temp_role;
DROP DATA ROLE temp_role;
prompt DROP ROLE temp_logon_role;
DROP ROLE temp_logon_role;

exit;
EOF

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Now run Task 3 to see what happens WHEN you add data grants.          ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
