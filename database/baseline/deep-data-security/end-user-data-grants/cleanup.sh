#!/bin/bash
# Oracle Deep Data Security - End User Data Grants Lab Cleanup

# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------
BOLD=$(tput bold 2>/dev/null || printf '')
CYAN=$(tput setaf 6 2>/dev/null || printf '')
GREEN=$(tput setaf 2 2>/dev/null || printf '')
YELLOW=$(tput setaf 3 2>/dev/null || printf '')
BLUE=$(tput setaf 4 2>/dev/null || printf '')
RED=$(tput setaf 1 2>/dev/null || printf '')
RESET=$(tput sgr0 2>/dev/null || printf '')

banner() {
    echo ""
    echo "${BOLD}${CYAN}================================================================${RESET}"
    printf "${BOLD}${CYAN}  %s${RESET}\n" "$*"
    echo "${BOLD}${CYAN}================================================================${RESET}"
    echo ""
}

step() {
    echo "  ${BOLD}${BLUE}$*${RESET}"
    echo ""
}

show_and_run() {
    local connect_display="$1"
    local sql="$2"
    local connect_actual="${3:-$1}"

    echo "  ${YELLOW}Connect:${RESET} ${GREEN}${connect_display}${RESET}"
    echo "  ${YELLOW}SQL:${RESET}"
    printf '%s\n' "$sql" | sed 's/^/    /'
    echo ""
    printf 'SET LINESIZE 110\nSET PAGESIZE 999\n%s\nEXIT\n' "$sql" | sqlplus -s "$connect_actual"
    echo ""
}

pause() {
    echo "  ${YELLOW}Press Enter to continue...${RESET}"
    read -r
}

# ---------------------------------------------------------------------------
# Environment check
# ---------------------------------------------------------------------------
banner "Lab Cleanup — End User Data Grants"

echo "  ORACLE_HOME = $ORACLE_HOME"
echo "  ORACLE_SID  = $ORACLE_SID"
echo "  PDB_NAME    = $PDB_NAME"
echo ""
echo "  ${RED}${BOLD}This will remove all objects created by the lab.${RESET}"
echo "  ${YELLOW}If you plan to continue to the next lab, skip this cleanup.${RESET}"
echo ""

# ---------------------------------------------------------------------------
# HR cleanup option
# ---------------------------------------------------------------------------
echo "  ${BOLD}HR Schema Cleanup Option${RESET}"
echo ""
echo "    A) Restore — HR existed before the lab; drop lab tables and rename originals back"
echo "    B) Drop    — HR was created for this lab; drop the entire HR schema"
echo ""
printf "  ${YELLOW}Enter choice [A/B]:${RESET} "
read -r HR_OPTION
HR_OPTION=$(echo "$HR_OPTION" | tr '[:lower:]' '[:upper:]')

if [[ "$HR_OPTION" != "A" && "$HR_OPTION" != "B" ]]; then
    echo "  ${RED}Invalid choice. Exiting.${RESET}"
    exit 1
fi

echo ""
pause

# ---------------------------------------------------------------------------
# Step 1: Drop data grants
# ---------------------------------------------------------------------------
banner "Step 1: Drop Data Grants"

show_and_run \
    "deepsec_admin/Oracle123@${PDB_NAME}" \
    "
DROP DATA GRANT hr.HRAPP_EMPLOYEE_ACCESS;
DROP DATA GRANT hr.HRAPP_MANAGER_ACCESS;
"

# ---------------------------------------------------------------------------
# Step 2: Drop database role, data roles, and end users
# ---------------------------------------------------------------------------
banner "Step 2: Drop Roles and End Users"

show_and_run \
    "deepsec_admin/Oracle123@${PDB_NAME}" \
    "
DROP ROLE direct_logon_role;
DROP DATA ROLE HRAPP_EMPLOYEES;
DROP DATA ROLE HRAPP_MANAGERS;
DROP END USER emma;
DROP END USER marvin;
"

# ---------------------------------------------------------------------------
# Step 3: Drop deepsec_admin
# ---------------------------------------------------------------------------
banner "Step 3: Drop deepsec_admin"

show_and_run \
    "sys/Oracle123@${PDB_NAME} as sysdba" \
    "
DROP USER deepsec_admin CASCADE;
" \
    "sys/Oracle123@${PDB_NAME} as sysdba"

# ---------------------------------------------------------------------------
# Step 4: HR schema cleanup
# ---------------------------------------------------------------------------
if [[ "$HR_OPTION" == "A" ]]; then
    banner "Step 4: Restore Existing HR Schema (Option A)"

    step "Drop lab-created tables and rename originals back"
    show_and_run \
        "sys/Oracle123@${PDB_NAME} as sysdba" \
        "
DROP TABLE hr.employees PURGE;
DROP TABLE hr.managers  PURGE;
ALTER TABLE hr.employees_before_deepsec_lab RENAME TO employees;
ALTER TABLE hr.managers_before_deepsec_lab  RENAME TO managers;
" \
        "sys/Oracle123@${PDB_NAME} as sysdba"

    echo "  ${YELLOW}If HR was converted to NO AUTHENTICATION and needs its password restored:${RESET}"
    echo ""
    echo "    ALTER USER hr IDENTIFIED BY Oracle123;"
    echo ""
    printf "  ${YELLOW}Restore HR password? [y/N]:${RESET} "
    read -r RESTORE_PW
    if [[ "$RESTORE_PW" =~ ^[Yy]$ ]]; then
        show_and_run \
            "sys/Oracle123@${PDB_NAME} as sysdba" \
            "
ALTER USER hr IDENTIFIED BY Oracle123;
" \
            "sys/Oracle123@${PDB_NAME} as sysdba"
    fi

else
    banner "Step 4: Drop Lab-Created HR Schema (Option B)"

    show_and_run \
        "sys/Oracle123@${PDB_NAME} as sysdba" \
        "
DROP USER hr CASCADE;
" \
        "sys/Oracle123@${PDB_NAME} as sysdba"
fi

# ---------------------------------------------------------------------------
# Step 5: Verify cleanup
# ---------------------------------------------------------------------------
banner "Step 5: Verify Cleanup"

show_and_run \
    "sys/Oracle123@${PDB_NAME} as sysdba" \
    "
-- Should return 0
SELECT COUNT(*) AS data_grants_remaining
  FROM dba_data_grants
 WHERE grant_name LIKE '%HRAPP%';

-- Should return no rows
COLUMN data_role FORMAT A16 HEADING 'DATA_ROLE'
SELECT data_role
  FROM dba_data_roles
 WHERE data_role IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS');

-- Should return no rows
COLUMN role FORMAT A17 HEADING 'ROLE'
SELECT role
  FROM dba_roles
 WHERE role = 'DIRECT_LOGON_ROLE';

-- Should return no rows
COLUMN username FORMAT A14 HEADING 'USERNAME'
SELECT username
  FROM dba_users
 WHERE username = 'DEEPSEC_ADMIN';
" \
    "sys/Oracle123@${PDB_NAME} as sysdba"

if [[ "$HR_OPTION" == "B" ]]; then
    show_and_run \
        "sys/Oracle123@${PDB_NAME} as sysdba" \
        "
-- Should return no rows
COLUMN username FORMAT A10 HEADING 'USERNAME'
SELECT username
  FROM dba_users
 WHERE username = 'HR';
" \
        "sys/Oracle123@${PDB_NAME} as sysdba"
fi

banner "Cleanup Complete"
echo "  All lab objects have been removed."
echo ""
