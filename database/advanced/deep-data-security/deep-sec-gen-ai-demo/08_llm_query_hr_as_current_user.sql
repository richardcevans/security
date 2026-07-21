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

define query_tool = '&1'

SELECT CASE '&&query_tool'
         WHEN 'employee_count' THEN
           (SELECT JSON_OBJECT(
                     'employee_count' VALUE COUNT(*)
                     RETURNING CLOB
                   )
              FROM hr.employees)
         WHEN 'employees_by_department' THEN
           (SELECT JSON_ARRAYAGG(
                     JSON_OBJECT(
                       'department_id' VALUE department_id,
                       'employee_count' VALUE employee_count
                       RETURNING CLOB
                     )
                     ORDER BY department_id
                     RETURNING CLOB
                   )
              FROM (
                SELECT department_id, COUNT(*) AS employee_count
                  FROM hr.employees
                 GROUP BY department_id
              ))
         WHEN 'employees_by_job_code' THEN
           (SELECT JSON_ARRAYAGG(
                     JSON_OBJECT(
                       'job_code' VALUE job_code,
                       'employee_count' VALUE employee_count
                       RETURNING CLOB
                     )
                     ORDER BY job_code
                     RETURNING CLOB
                   )
              FROM (
                SELECT job_code, COUNT(*) AS employee_count
                  FROM hr.employees
                 GROUP BY job_code
              ))
         WHEN 'list_authorized_employees' THEN
           (SELECT JSON_ARRAYAGG(
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
              FROM hr.employees)
       END
  FROM dual;

exit success
