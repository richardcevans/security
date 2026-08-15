-- Run as an ADB administrator. These are password-authenticated local database
-- end users, not OCI IAM identities. The Admin Console passes the shared Stack
-- password as this script's first parameter; it is never spooled.
whenever sqlerror exit sql.sqlcode rollback
set echo off
set verify off

define marvin_password = &1

prompt SQL> DROP END USER MARVIN (if it already exists)
begin
  if nvl(length('&&marvin_password'), 0) = 0 then
    raise_application_error(-20001, 'The shared Stack password is empty. Sign in to the Admin Console with the generated password and run this action again.');
  end if;
  begin
    execute immediate 'drop end user marvin';
  exception
    when others then
      if sqlcode != -52515 then
        raise;
      end if;
  end;
end;
/

prompt SQL> CREATE END USER MARVIN IDENTIFIED BY "<shared Stack password>"
create end user marvin identified by "&marvin_password";

-- Begin with full access so the student can observe the before-and-after
-- effect when Task 6 applies the employee policy.
prompt SQL> GRANT DATA ROLE APP_FULL_ACCESS TO MARVIN
prompt Assigning a data role does not grant normal database administration privileges. It activates the data grant for MARVIN's database sessions.
grant data role app_full_access to marvin;

prompt
prompt Full access assignment complete.
prompt MARVIN starts with APP_FULL_ACCESS for the full-access demonstration.
prompt MARVIN uses the shared Stack password for this disposable lab. Use the application before applying the employee policy.
undefine marvin_password
