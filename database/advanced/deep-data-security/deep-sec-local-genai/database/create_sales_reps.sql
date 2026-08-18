-- Run as ADB ADMIN after create_data_roles.sql.
-- Named representatives make the manager policy data-driven rather than
-- relying on a generic SALES_TEAM value.
whenever sqlerror exit sql.sqlcode rollback
set echo off

prompt SQL> DROP TABLE APPLAB.SALES_REPS (if it exists)
begin
  execute immediate 'drop table applab.sales_reps purge';
exception
  when others then
    if sqlcode != -942 then raise; end if;
end;
/
prompt SQL> CREATE TABLE APPLAB.SALES_REPS (REP_NAME, MANAGER_NAME)
create table applab.sales_reps (
  rep_name      varchar2(100) primary key,
  manager_name  varchar2(100) not null
);

prompt SQL> Populate direct-report relationships. MARVIN manages one rep, EMMA, in WEST.
insert into applab.sales_reps (rep_name, manager_name) values ('EMMA', 'MARVIN');

prompt SQL> COMMIT
commit;

prompt SALES_REPS ready: MARVIN manages EMMA in WEST. EAST, SOUTH, and NORTH belong to PRIYA and stay outside MARVIN's scope entirely.
