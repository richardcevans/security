-- Run as an ADB administrator. Creates the plain Oracle role every Deep
-- Data Security data role will build on. Nothing here is Deep Data
-- Security yet; this is completely ordinary Oracle role security.
whenever sqlerror exit sql.sqlcode rollback
set echo off

prompt Creating the base connect role every Deep Sec data role will use later.
prompt SQL> CREATE ROLE APP_LOCAL_CONNECT (if it doesn't already exist)
begin
  execute immediate 'create role app_local_connect';
exception
  when others then
    if sqlcode != -1921 then raise; end if;
end;
/

prompt SQL> GRANT CREATE SESSION TO APP_LOCAL_CONNECT
grant create session to app_local_connect;

prompt APP_LOCAL_CONNECT is ready. This is an ordinary Oracle role with an
prompt ordinary privilege, nothing Deep Sec about it yet. The next page
prompt attaches it to Deep Data Security's data roles.
