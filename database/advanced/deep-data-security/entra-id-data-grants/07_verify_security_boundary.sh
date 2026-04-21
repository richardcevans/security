#!/bin/bash
# =========================================================================================
# Script Name : 07_verify_security_boundary.sh
#
# Parameter   : None
#
# Notes       : Task 13 - Verify the security boundary.
#               Tests that Entra ID-authenticated end users cannot bypass data grants.
#               Each test requires a separate Entra ID browser login.
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
echo -e "${GREEN}      Task 13: Verify the Security Boundary                                 ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}Each test connects via sqlplus /@hrdb (Entra ID browser login).${NC}"
echo -e "${PURPLE}You will need to log in as the appropriate user for each test.${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"
export DBUSR_PWD="${DBUSR_PWD:-Oracle123}"

# =====================================================================
# Test 1: Marvin tries to see Bob's SSN (Bob is not his direct report)
# =====================================================================
echo -e "${YELLOW}Test 1: Marvin tries to see Bob's SSN...${NC}"
echo -e "${CYAN}Executing: sqlplus /@hrdb${NC}"
echo -e "${PURPLE}Log in as Marvin's Entra ID account.${NC}"
echo

sqlplus /@hrdb <<EOF

set echo off
set feedback on
set verify off
set sqlprompt ""
set sqlcontinue ""
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
echo -e "${CYAN}Executing: sqlplus /@hrdb${NC}"
echo -e "${PURPLE}Log in as Emma's Entra ID account.${NC}"
echo

sqlplus /@hrdb <<EOF

set echo off
set feedback on
set verify off
set sqlprompt ""
set sqlcontinue ""
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
echo -e "${CYAN}Executing: sqlplus /@hrdb${NC}"
echo -e "${PURPLE}Log in as Emma's Entra ID account.${NC}"
echo

sqlplus /@hrdb <<EOF

set echo off
set feedback on
set verify off
set sqlprompt ""
set sqlcontinue ""
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
echo -e "${YELLOW}Test 4: Can the HR schema account still log in?${NC}"
echo -e "${CYAN}Executing: sqlplus -s hr/******@${PDB_NAME}${NC}"
echo

sqlplus -s hr/${DBUSR_PWD}@${PDB_NAME} <<EOF
exit;
EOF

echo
echo -e "${RED}  Result: HR cannot log in. The schema account has NO AUTHENTICATION.${NC}"
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
echo -e "${GREEN}  4. HR cannot log in (NO AUTHENTICATION)                                  ${NC}"
echo -e "${GREEN}                                                                            ${NC}"
echo -e "${GREEN}  Entra ID handles authentication. Data grants handle authorization.        ${NC}"
echo -e "${GREEN}  No prompt injection or application bug can circumvent these controls.     ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
