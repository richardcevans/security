#!/bin/bash
# Create the HR schema and sample data on ADB.

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/lib_adb.sh"
require_adb_env

export OCI_USERNAME_DOMAIN="${OCI_USERNAME_DOMAIN:-example.com}"
export ADB_LAB_USERNAME="${ADB_LAB_USERNAME:-marvin@${OCI_USERNAME_DOMAIN}}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 2: Create HR Schema and Employee Data                            ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}OCI_USERNAME_DOMAIN = ${OCI_USERNAME_DOMAIN}${NC}"
echo -e "${CYAN}ADB_LAB_USERNAME    = ${ADB_LAB_USERNAME}${NC}"
echo -e "${CYAN}Marvin's HR row will use this IAM database user name.${NC}"
echo

admin_sqlplus <<SQL
set echo on
set serveroutput on
set lines 180
whenever sqlerror exit sql.sqlcode

BEGIN
  EXECUTE IMMEDIATE 'DROP USER hr CASCADE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1918 THEN
      RAISE;
    END IF;
END;
/

CREATE USER hr NO AUTHENTICATION
  DEFAULT TABLESPACE data
  QUOTA UNLIMITED ON data;

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

INSERT INTO hr.employees VALUES (1, 'Grace', 'Young', 'CEO', NULL, '111-11-1111', NULL, '555-100-0001', 235000, 'grace@${OCI_USERNAME_DOMAIN}', NULL);
INSERT INTO hr.employees VALUES (2, 'Marvin', 'Morgan', 'SWE_MGR', 1, '222-22-2222', NULL, '555-100-0002', 175000, '${ADB_LAB_USERNAME}', 1);
INSERT INTO hr.employees VALUES (3, 'Emma', 'Baker', 'SWE2', 1, '333-33-3333', NULL, '555-100-0003', 120000, 'emma@${OCI_USERNAME_DOMAIN}', 2);
INSERT INTO hr.employees VALUES (4, 'Charlie', 'Davis', 'SWE1', 1, '444-44-4444', NULL, '555-100-0004', 95000, 'charlie@${OCI_USERNAME_DOMAIN}', 2);
INSERT INTO hr.employees VALUES (5, 'Dana', 'Lee', 'SWE3', 1, '555-55-5555', NULL, '555-100-0005', 130000, 'dana@${OCI_USERNAME_DOMAIN}', 2);
INSERT INTO hr.employees VALUES (6, 'Bob', 'Smith', 'SALES_REP', 2, '666-66-6666', NULL, '555-100-0006', 145000, 'bob@${OCI_USERNAME_DOMAIN}', 1);
INSERT INTO hr.employees VALUES (7, 'Fiona', 'Chen', 'HR_REP', 3, '777-77-7777', NULL, '555-100-0007', 92000, 'fiona@${OCI_USERNAME_DOMAIN}', 1);
COMMIT;

SELECT COUNT(*) AS hr_employee_rows FROM hr.employees;

exit;
SQL

echo
echo -e "${GREEN}Task 2 completed. Next: run ./03_create_data_roles_and_grants.sh${NC}"
echo
