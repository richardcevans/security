Rem
Rem $Header: setup.sql 17-jun-2026.09:59:51 tanisaga Exp $
Rem
Rem setup.sql
Rem
Rem Copyright (c) 2026, Oracle and/or its affiliates.
Rem
Rem    NAME
Rem      setup.sql - <one-line expansion of the name>
Rem
Rem    DESCRIPTION
Rem      <short description of component this file declares/defines>
Rem
Rem    NOTES
Rem      <other useful comments, qualifications, etc.>
Rem
Rem    BEGIN SQL_FILE_METADATA
Rem    SQL_SOURCE_FILE: tkmain_3/tzfd/src/oci_iam_single_agent/setup.sql
Rem    SQL_SHIPPED_FILE:
Rem    SQL_PHASE:
Rem    SQL_STARTUP_MODE: NORMAL
Rem    SQL_IGNORABLE_ERRORS: NONE
Rem    SQL_CALLING_FILE:
Rem    END SQL_FILE_METADATA
Rem
Rem    MODIFIED   (MM/DD/YY)
Rem    tanisaga    06/17/26 - Created
Rem

SET ECHO ON
SET FEEDBACK 1
SET NUMWIDTH 10
SET LINESIZE 80
SET TRIMSPOOL ON
SET TAB OFF
SET PAGESIZE 100

REM SET ECHO OFF
REM SET FEEDBACK 1
REM SET NUMWIDTH 10
REM SET LINESIZE 80
REM SET TRIMSPOOL ON
REM SET TAB OFF
REM SET PAGESIZE 100
REM SET ECHO ON
define passwd=knl_test7
define db_usr_passwd=db_usr
define conn_str=cdb1_pdb1
define nstempl_passwd=nstempl

----------------------------------------------------------------------
-- 1. ADD SSN column to HR table
----------------------------------------------------------------------
connect hr/hr@cdb1_pdb1;
update hr.employees set first_name = 'Hannah', email = 'HANNAH' where first_name = 'Susan' and last_name = 'Mavris';
update hr.employees set first_name = 'Marvin', email = 'MARVIN' where first_name = 'Nancy' and last_name = 'Greenberg';
update hr.employees set first_name = 'Emma', email = 'EMMA' where first_name = 'David' and last_name = 'Austin';
commit;
ALTER TABLE employees ADD ssn VARCHAR2(11);
BEGIN
  FOR rec IN (SELECT employee_id FROM employees) LOOP
   UPDATE employees
   SET ssn = LPAD(DBMS_RANDOM.VALUE(100, 999), 3, '0') || '-' ||
        LPAD(DBMS_RANDOM.VALUE(10, 99), 2, '0') || '-' ||
        LPAD(DBMS_RANDOM.VALUE(1000, 9999), 4, '0')
   WHERE employee_id = rec.employee_id;
  END LOOP;
  COMMIT;
END;
/

-- Update SSN for Marvin, Emma and Hannah to get consistent result 
update hr.employees set ssn = '841-11-4324'
  where first_name = 'Emma' and email = 'EMMA';
update hr.employees set ssn = '798-13-9372'
  where first_name = 'Hannah' and email = 'HANNAH';
update hr.employees set ssn = '166-46-3472'
  where first_name = 'Marvin' and email = 'MARVIN';

alter table hr.employees modify (email varchar2(250));

-- Update email ids of the user MARVIN, EMMA and HANNAH
-- Please Note: These user accounts have been created in OCI IAM.
UPDATE hr.employees
   SET email = 'EmmaBaker'
 WHERE UPPER(first_name) = 'EMMA'   AND UPPER(email) = 'EMMA';

UPDATE hr.employees
   SET email = 'MarvinGreenberg'
 WHERE UPPER(first_name) = 'MARVIN' AND UPPER(email) = 'MARVIN';

COMMIT;

create table hr.managers as select * from hr.employees;


 
connect sys/&passwd@&conn_str as sysdba
-- Create DB user: connection pool user
create user db_usr identified by &db_usr_passwd;
grant connect to db_usr;
grant CREATE END USER SECURITY CONTEXT to db_usr;

-- Create policy to capture audit records
create audit policy AUD_FULLSEC actions CREATE END USER, ALTER END USER, DROP END USER, CREATE APPLICATION IDENTITY,
DROP APPLICATION IDENTITY, CREATE DATA ROLE, DROP DATA ROLE, GRANT DATA ROLE, REVOKE DATA ROLE, CREATE DATA GRANT,
DROP DATA GRANT, CREATE DATA PRIVILEGE, DROP DATA PRIVILEGE, CREATE END USER SECURITY CONTEXT,
ATTACH END USER SECURITY CONTEXT, DETACH END USER SECURITY CONTEXT;

audit policy AUD_FULLSEC;

create or replace data role employee_role mapped to
'iam_oauth_group=Employee';

create or replace data role manager_role mapped to
'iam_oauth_group=Manager';


ALTER SYSTEM SET IDENTITY_PROVIDER_TYPE=OCI_IAM SCOPE=BOTH;
ALTER SYSTEM SET IDENTITY_PROVIDER_OAUTH_CONFIG=
'{
  "app_id":"6****c",
  "domain_url":"https://idcs-7****.identity.oraclecloud.com:443"
}';
exec DBMS_CREDENTIAL.DROP_CREDENTIAL('OCI_IAM_DOMAIN_DB_CRED$');

BEGIN
DBMS_CREDENTIAL.CREATE_CREDENTIAL(
'OCI_IAM_DOMAIN_DB_CRED$',
'7****0',
'idcscs-******5'
);
END;
/

CREATE OR REPLACE DATA GRANT emp_self AS
SELECT
ON hr.employees
WHERE email = ORA_END_USER_CONTEXT.USERNAME
TO employee_role;

CREATE OR REPLACE DATA GRANT mgr_hierarchy AS
SELECT (ALL COLUMNS EXCEPT ssn)
ON hr.employees
WHERE employee_id IN
(
    SELECT employee_id
    FROM hr.managers
    START WITH employee_id =
    (
        SELECT employee_id
        FROM hr.managers
        WHERE UPPER(email) =
              UPPER(ORA_END_USER_CONTEXT.USERNAME)
    )
    CONNECT BY PRIOR employee_id = manager_id
)
TO manager_role;


create role dbrole1;
grant create session to dbrole1;
grant restricted session to dbrole1;
-- grant dbrole1 to employee_fs_role,employee_fs_v1_role,employee_fs_role_iam1,employee_fs_role_iam3,manager_fs_role_iam,manager_fs_role_iam2,employee_fs_v2_role;
grant dbrole1 to employee_role;
grant dbrole1 to manager_role;

-- Create DB user that owns the end user context callback package
create user nstempl identified by &nstempl_passwd;
grant create session, resource, unlimited tablespace to nstempl;
grant select, insert on scott.dept to nstempl; 
grant select, insert on scott.dept to dbrole1;

connect nstempl/&nstempl_passwd@&conn_str
-- Create sample package for the  end user context callback
create or replace package nstempl.TESTPACKAGE AUTHID current_user as
  PROCEDURE testcb;
end testpackage;
/
show errors
 
-- Create package body for the end user context callback
-- The callback instantiate context attribute value on first read
CREATE OR REPLACE PACKAGE BODY nstempl.testpackage AS
   PROCEDURE testcb IS
      sql_stmt VARCHAR2(4000);
   BEGIN
      DBMS_OUTPUT.PUT_LINE('instantiation callback');
      sql_stmt := 'UPDATE END_USER_CONTEXT SET END_USER_CONTEXT.CONTEXT.p3 = 9876543 WHERE owner = ''EUC'' AND name = ''HCM''';
      EXECUTE IMMEDIATE sql_stmt;
   EXCEPTION
      WHEN OTHERS THEN
         DBMS_OUTPUT.PUT_LINE('Error executing UPDATE: ' || SQLERRM);
         RAISE;
   END testcb;
END testpackage;
/
show errors
 
grant execute on nstempl.TESTPACKAGE to dbrole1;
 
conn sys/&passwd@&conn_str as sysdba
create user euc identified by euc;
drop end user context euc.hcm;
CREATE END USER CONTEXT euc.hcm USING JSON SCHEMA '{
    "type": "object",
    "properties": {
         "p1": {
            "type": "integer",
            "default": 123
         },
         "p2": {
            "type": "string",
            "default": "abc"
         },
         "p3": {
            "type": "integer",
            "o:onFirstRead": "nstempl.TESTPACKAGE.testcb"
         },
         "p4": {
            "type": "string",
            "o:onFirstRead": "nstempl.TESTPACKAGE.testcb"
         }
    }
}';

-- Grant privilege to update EUC to end users
grant update any end user context to dbrole1;

-- Grant privilege to select EUC to end users
create or replace data grant EUC.HCM_GRANT AS
SELECT on
SYS.END_USER_CONTEXT
where OWNER = 'EUC' and NAME = 'HCM'
-- to employee_fs_role, employee_fs_role_iam1,employee_fs_role_iam3, manager_fs_role_iam,manager_fs_role_iam2,employee_fs_v1_role, employee_fs_v2_role;
to employee_role, manager_role;

create end user eu1 identified by eu1;
create data role drole1;
grant CONNECT to drole1;
grant data role drole1 to eu1;
grant dbrole1 to drole1;

CREATE OR REPLACE DATA GRANT EUC.END_USER_GRANT1
  AS SELECT, UPDATE ON SYS.END_USER_CONTEXT
  WHERE OWNER='EUC'
  TO drole1;
