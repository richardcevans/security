-- Run as an ADB administrator. These are password-authenticated local database
-- end users, not OCI IAM identities. Passwords are prompted and never spooled.
whenever sqlerror exit sql.sqlcode rollback
set echo off
set verify off

accept marvin_password char prompt 'Password for MARVIN (input hidden): ' hide

begin execute immediate 'drop end user marvin'; exception when others then if sqlcode != -52515 then raise; end if; end;
/

create end user marvin identified by "&marvin_password";

-- Begin with the intentionally insecure baseline so the student can observe
-- the before-and-after effect when Task 6 applies the employee policy.
grant data role app_baseline_access to marvin;

prompt
prompt Baseline access assignment complete.
prompt MARVIN starts with APP_BASELINE_ACCESS for the intentionally insecure baseline.
prompt Record Marvin's password, then use the application before applying the employee policy.
