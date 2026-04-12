#!/bin/bash
# =========================================================================================
# Script Name : dg_query_compare.sh
#
# Parameter   : None
#
# Notes       : Same query, three users, three different results.
#               Runs the identical SELECT on hr.employees as SYSTEM (DBA),
#               Marvin (manager), and Emma (employee) to demonstrate that
#               data grants enforce per-user access without changing SQL.
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

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Set defaults for environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"
export DBUSR_SYSTEM="${DBUSR_SYSTEM:-system}"
export DBUSR_PWD="${DBUSR_PWD:-Oracle123}"

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# The query — identical for all three users
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
SQL_QUERY="SELECT employee_id, first_name, last_name, ssn, salary, department_id, manager_id
  FROM hr.employees
 ORDER BY employee_id;"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Same Query. Three Users. Three Different Results.                     ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}The following SQL will be executed identically in each session:${NC}"
echo
echo -e "${CYAN}${SQL_QUERY}${NC}"
echo

# =====================================================================
# 1. SYSTEM (DBA) — sees everything
# =====================================================================
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}  1/3  Connecting as SYSTEM (DBA) — full, unrestricted access               ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${DBUSR_SYSTEM}/******@${PDB_NAME}${NC}"
echo

sqlplus -s ${DBUSR_SYSTEM}/${DBUSR_PWD}@${PDB_NAME} <<EOF

set echo off
set feedback on
set serveroutput on
set lines 130
set pages 9999
col first_name  format a12
col last_name   format a12
col ssn         format a15
col salary      format 999,999.99

${SQL_QUERY}

exit;
EOF

echo
echo -e "${YELLOW}SYSTEM sees all 7 rows — every SSN, every salary, every department.${NC}"
echo

# =====================================================================
# 2. Marvin (manager) — sees himself + direct reports, no SSN for reports
# =====================================================================
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}  2/3  Connecting as Marvin (Manager) — same query                          ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo -e "${CYAN}Executing: sqlplus -s marvin/******@${PDB_NAME}${NC}"
echo

sqlplus -s marvin/Oracle123@${PDB_NAME} <<EOF

set echo off
set feedback on
set serveroutput on
set lines 130
set pages 9999
col first_name  format a12
col last_name   format a12
col ssn         format a15
col salary      format 999,999.99

${SQL_QUERY}

exit;
EOF

echo
echo -e "${YELLOW}Marvin sees 4 rows — himself and his 3 direct reports.${NC}"
echo -e "${YELLOW}His own SSN is visible (employee grant). Reports' SSNs are hidden (manager grant excludes SSN).${NC}"
echo

# =====================================================================
# 3. Emma (employee) — sees only herself
# =====================================================================
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}  3/3  Connecting as Emma (Employee) — same query                           ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo -e "${CYAN}Executing: sqlplus -s emma/******@${PDB_NAME}${NC}"
echo

sqlplus -s emma/Oracle123@${PDB_NAME} <<EOF

set echo off
set feedback on
set serveroutput on
set lines 130
set pages 9999
col first_name  format a12
col last_name   format a12
col ssn         format a15
col salary      format 999,999.99

${SQL_QUERY}

exit;
EOF

echo
echo -e "${YELLOW}Emma sees 1 row — only herself. Her own SSN and salary are visible.${NC}"
echo

echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Same SQL. Same table. Same AI agent. Different data.                  ${NC}"
echo -e "${GREEN}      Enforced by Oracle Deep Data Security — not application code.         ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
