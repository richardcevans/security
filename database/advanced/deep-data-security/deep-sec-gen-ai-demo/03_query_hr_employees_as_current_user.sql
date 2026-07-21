set echo off
set heading off
set feedback off
set pagesize 0
set linesize 32767
set long 1000000
set longchunksize 1000000
set trimspool on
set verify off
whenever sqlerror exit sql.sqlcode rollback

SELECT JSON_ARRAYAGG(
         JSON_OBJECT(
           'employee_id' VALUE employee_id,
           'first_name' VALUE first_name,
           'last_name' VALUE last_name,
           'job_code' VALUE job_code,
           'department_id' VALUE department_id,
           'manager_id' VALUE manager_id,
           'user_name' VALUE user_name
           RETURNING CLOB
         )
         ORDER BY employee_id
         RETURNING CLOB
       )
  FROM hr.employees;

exit success
