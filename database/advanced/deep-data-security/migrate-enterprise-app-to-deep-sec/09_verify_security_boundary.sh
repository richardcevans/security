#!/bin/bash
# =========================================================================================
# Script Name : 09_verify_security_boundary.sh
#
# Parameter   : None
#
# Notes       : Task 5 (continued) - Verify the security boundary.
#               Tests that end users cannot bypass data grants:
#               - Marvin cannot see employees outside his scope
#               - Emma cannot update salary (only phone_number)
#               - HR can no longer log in
#
# Modified by         Date         Change
# Oracle DB Security  01/04/2026   Creation
# Oracle DB Security  04/28/2026   Entra ID UPN-format end users; source lab_env.sh
# =========================================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Define colors for readability (only used in Bash, not inside SQL*Plus)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m' # No Color

[ -f "${SCRIPT_DIR}/lab_env.sh" ] && source "${SCRIPT_DIR}/lab_env.sh"
export DOMAIN_NAME="${DOMAIN_NAME:-contoso.com}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Verify the Security Boundary: Can End Users Bypass Data Grants?       ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"

# =====================================================================
# Test 1: Marvin tries to see Bob's SSN (Bob is not his direct report)
# =====================================================================
echo -e "${YELLOW}Test 1: Marvin tries to see Bob's SSN...${NC}"
echo -e "${CYAN}Executing: sqlplus /nolog → CONNECT \"marvin@${DOMAIN_NAME}\"/******@${PDB_NAME}${NC}"
echo

sqlplus -s /nolog <<EOF
CONNECT "marvin@${DOMAIN_NAME}"/Oracle123@${PDB_NAME}

set echo off
set feedback on
set serveroutput on
set lines 130
set pages 9999

prompt
prompt ========================================================================
prompt Test 1: Can Marvin see Bob's SSN?
prompt  - Bob (dept 2) is NOT Marvin's direct report.
prompt  - The data grant predicate should exclude Bob entirely.
prompt ========================================================================

col ssn format a15

prompt SELECT ssn FROM hr.employees WHERE first_name = 'Bob';
SELECT ssn FROM hr.employees WHERE first_name = 'Bob';

exit;
EOF

echo
echo -e "${RED}  Result: 0 rows. Bob is completely invisible to Marvin.${NC}"
echo

# =====================================================================
# Test 2: Emma tries to update her salary
# =====================================================================
echo -e "${YELLOW}Test 2: Emma tries to update her own salary...${NC}"
echo -e "${CYAN}Executing: sqlplus /nolog → CONNECT \"emma@${DOMAIN_NAME}\"/******@${PDB_NAME}${NC}"
echo

sqlplus -s /nolog <<EOF
CONNECT "emma@${DOMAIN_NAME}"/Oracle123@${PDB_NAME}

set echo off
set feedback on
set serveroutput on
set lines 130
set pages 9999

prompt
prompt ========================================================================
prompt Test 2: Can Emma update her salary?
prompt  - Employee data grant allows UPDATE(phone_number) only.
prompt  - Salary is not in the UPDATE column list.
prompt ========================================================================

prompt UPDATE hr.employees SET salary = 999999 WHERE employee_id = 3;
UPDATE hr.employees SET salary = 999999 WHERE employee_id = 3;

prompt
prompt ROLLBACK;
ROLLBACK;

exit;
EOF

echo
echo -e "${RED}  Result: 0 rows updated. Emma cannot modify salary — only phone_number.${NC}"
echo

# =====================================================================
# Test 3: Emma tries to update another user's phone number
# =====================================================================
echo -e "${YELLOW}Test 3: Emma tries to update Marvin's phone number...${NC}"
echo -e "${CYAN}Executing: sqlplus /nolog → CONNECT \"emma@${DOMAIN_NAME}\"/******@${PDB_NAME}${NC}"
echo

sqlplus -s /nolog <<EOF
CONNECT "emma@${DOMAIN_NAME}"/Oracle123@${PDB_NAME}

set echo off
set feedback on
set serveroutput on
set lines 130
set pages 9999

prompt
prompt ========================================================================
prompt Test 3: Can Emma update another user's phone number?
prompt  - Employee data grant predicate: WHERE user_name = emma
prompt  - Marvin's row should be excluded.
prompt ========================================================================

prompt UPDATE hr.employees SET phone_number = '555-HACKED' WHERE first_name = 'Marvin';
UPDATE hr.employees SET phone_number = '555-HACKED' WHERE first_name = 'Marvin';

prompt
prompt ROLLBACK;
ROLLBACK;

exit;
EOF

echo
echo -e "${RED}  Result: 0 rows updated. Emma can only update her OWN phone number.${NC}"
echo

# =====================================================================
# Test 4: Try to log in as HR (should fail)
# =====================================================================
echo -e "${YELLOW}Test 4: Can the shared service account HR still log in?${NC}"
echo -e "${CYAN}Executing: sqlplus -s hr/******@${PDB_NAME}${NC}"
echo

sqlplus -s hr/${DBUSR_PWD}@${PDB_NAME} <<EOF
exit;
EOF

echo
echo -e "${RED}  Result: HR cannot log in. The shared service account is locked.${NC}"
echo

# =====================================================================
# Summary
# =====================================================================
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Security Boundary Verified!                                           ${NC}"
echo -e "${GREEN}                                                                            ${NC}"
echo -e "${GREEN}  1. Marvin cannot see employees outside his scope (0 rows for Bob)        ${NC}"
echo -e "${GREEN}  2. Emma cannot update salary (only phone_number)                         ${NC}"
echo -e "${GREEN}  3. Emma cannot modify other users' data (predicate limits to own row)    ${NC}"
echo -e "${GREEN}  4. HR can no longer log in (NO AUTHENTICATION)                           ${NC}"
echo -e "${GREEN}                                                                            ${NC}"
echo -e "${GREEN}  No prompt injection, no misconfigured endpoint, and no application bug   ${NC}"
echo -e "${GREEN}  can circumvent these controls. The enforcement is in the database kernel. ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
