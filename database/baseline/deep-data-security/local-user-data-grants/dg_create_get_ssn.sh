#!/bin/bash
# =========================================================================================
# Script Name : dg_create_get_ssn.sh
#
# Parameter   : None
#
# Notes       : Creates the HR.GET_SSN function that returns an employee's SSN
#               given their employee_id.
#
# Modified by         Date         Change
# Oracle DB Security  19/03/2026   Creation
# =========================================================================================

# Define colors for readability (only used in Bash, not inside SQL*Plus)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Create HR.GET_SSN Function                                            ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"
export DBUSR_SYSTEM="${DBUSR_SYSTEM:-system}"
export DBUSR_PWD="${DBUSR_PWD:-Oracle123}"

CONN_DISPLAY="${DBUSR_SYSTEM}/******@${PDB_NAME}"

echo -e "${YELLOW}Creating HR.GET_SSN function...${NC}"
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
prompt Creating HR.GET_SSN Function
prompt  - Returns the SSN for a given employee_id.
prompt  - Returns NULL if the employee is not found.
prompt ========================================================================

prompt CREATE OR REPLACE FUNCTION hr.get_ssn (p_employee_id IN NUMBER) RETURN VARCHAR2 IS v_ssn VARCHAR2(20); BEGIN SELECT ssn INTO v_ssn FROM hr.employees WHERE employee_id = p_employee_id; RETURN v_ssn; EXCEPTION WHEN NO_DATA_FOUND THEN RETURN NULL; END;
CREATE OR REPLACE FUNCTION hr.get_ssn (
  p_employee_id IN NUMBER
) RETURN VARCHAR2
IS
  v_ssn VARCHAR2(20);
BEGIN
  SELECT ssn
    INTO v_ssn
    FROM hr.employees
   WHERE employee_id = p_employee_id;
  RETURN v_ssn;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RETURN NULL;
END;
/

prompt
prompt ========================================================================
prompt Verifying HR.GET_SSN Function
prompt ========================================================================

prompt SELECT hr.get_ssn(1) AS grace_ssn, hr.get_ssn(2) AS marvin_ssn, hr.get_ssn(3) AS emma_ssn FROM DUAL;
SELECT hr.get_ssn(1) AS grace_ssn, hr.get_ssn(2) AS marvin_ssn, hr.get_ssn(3) AS emma_ssn FROM DUAL;

prompt SELECT hr.get_ssn(999) AS not_found FROM DUAL;
SELECT hr.get_ssn(999) AS not_found FROM DUAL;

exit;
EOF

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      HR.GET_SSN Function Created Successfully!                             ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
