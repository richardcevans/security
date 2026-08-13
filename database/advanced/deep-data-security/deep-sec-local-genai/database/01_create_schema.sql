-- Run as an ADB administrator. This fixed lab uses the APPLAB schema.

whenever sqlerror exit sql.sqlcode rollback
set echo off

begin
  execute immediate 'drop user APPLAB cascade';
exception
  when others then
    if sqlcode != -1918 then raise; end if;
end;
/

create user APPLAB identified by "ChangeMe_At_Run_Time_1";
grant create session, create table, create procedure, create sequence to APPLAB;
alter user APPLAB quota unlimited on data;

-- Keep the administrator session for all provisioning. APPLAB owns the table,
-- while MARVIN is the local end user used for validation.
create table APPLAB.customers (
  customer_id          number primary key,
  customer_name        varchar2(100) not null,
  region               varchar2(20) not null,
  sales_rep            varchar2(100) not null,
  revenue              number not null,
  credit_limit         number not null,
  sensitive_identifier varchar2(50) not null
);

create index APPLAB.customers_sales_rep_ix on APPLAB.customers (sales_rep);
