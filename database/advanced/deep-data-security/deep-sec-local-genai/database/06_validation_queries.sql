-- Execute with an attached local end-user security context.
-- The Flask app uses the same SELECT before and after Marvin's role change.
set echo off
set linesize 160 pagesize 100
column customer_Name format a25
column sales_rep format a10
prompt SQL> SELECT * FROM APPLAB.CUSTOMERS ORDER BY REVENUE DESC
prompt This is the same deliberately broad application query. Oracle Deep Data Security determines the rows and columns returned.
select *
  from applab.customers
 order by revenue desc;

column username format a20
prompt SQL> SELECT ORA_END_USER_CONTEXT.USERNAME FROM DUAL
prompt Showing the authenticated local end user Oracle used for the authorization decision.
select ora_end_user_context.username as end_user from dual;

column active_data_role format a20
prompt SQL> SELECT ROLE_NAME FROM V$END_USER_DATA_ROLE ORDER BY ROLE_NAME
prompt Showing the active Oracle Deep Data Security data roles for this session.
select role_name as active_data_role
  from v$end_user_data_role
 order by role_name;
