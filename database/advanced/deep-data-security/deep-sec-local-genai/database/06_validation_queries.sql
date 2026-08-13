-- Execute with an attached local end-user security context.
-- The Flask app uses the same SELECT before and after Marvin's role change.
set echo off
set linesize 160 pagesize 100
select *
  from applab.customers
 order by revenue desc;

select ora_end_user_context.username as end_user from dual;

select role_name as active_data_role
  from v$end_user_data_role
 order by role_name;
