-- Run as an ADB administrator. Emma is a fixed comparison persona: she always
-- holds APP_SALES_EMPLOYEE only, so a student can sign in as Emma at any point
-- to see a stable employee-level view of her own WEST rows.
whenever sqlerror exit sql.sqlcode rollback
set echo off
set verify off

define emma_password = &1

prompt SQL> DROP END USER EMMA (if it already exists)
begin
  if nvl(length('&&emma_password'), 0) = 0 then
    raise_application_error(-20001, 'The shared Stack password is empty. Sign in to the Admin Console with the generated password and run this action again.');
  end if;
  begin
    execute immediate 'drop end user emma';
  exception
    when others then
      if sqlcode != -52515 then
        raise;
      end if;
  end;
end;
/

prompt SQL> CREATE END USER EMMA IDENTIFIED BY "<shared Stack password>"
create end user emma identified by "&emma_password";

prompt SQL> GRANT DATA ROLE APP_SALES_EMPLOYEE TO EMMA
grant data role app_sales_employee to emma;

prompt
prompt Emma is ready. She always holds APP_SALES_EMPLOYEE, so signing in as Emma
prompt gives a stable point of comparison against Marvin's role as it changes
prompt through the rest of the lab.
undefine emma_password
