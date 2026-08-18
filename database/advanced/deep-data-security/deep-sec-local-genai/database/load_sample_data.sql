-- Run as an ADB administrator after create_schema.sql.
whenever sqlerror exit sql.sqlcode rollback
set echo off

-- Preserve literal ampersands in sample customer names. Re-enable substitution
-- before returning to the caller because the user-creation script accepts a parameter.
set define off

prompt SQL> ALTER SESSION SET CURRENT_SCHEMA = APPLAB
alter session set current_schema = applab;

prompt SQL> DELETE FROM APPLAB.CUSTOMERS
prompt Removing prior lab rows so this fixed 22-row dataset can be loaded again safely.
delete from customers;

prompt SQL> INSERT ALL (... 22 fixed APPLAB.CUSTOMERS rows ...)
prompt The data includes MARVIN, EMMA, PRIYA, and FINANCE accounts for the authorization demonstrations.
insert all
  into customers values ( 1, 'Acme East',       'EAST', 'PRIYA', 920000, 180000, 'E-1001-SSN')
  into customers values ( 2, 'Beacon Health',  'EAST', 'PRIYA', 870000, 160000, 'E-1002-SSN')
  into customers values ( 3, 'Cedar Retail',   'EAST', 'PRIYA', 760000, 150000, 'E-1003-SSN')
  into customers values ( 4, 'Delta Foods',    'EAST', 'PRIYA', 650000, 125000, 'E-1004-SSN')
  into customers values ( 5, 'Evergreen Labs', 'EAST', 'PRIYA', 590000, 115000, 'E-1005-SSN')
  into customers values ( 6, 'Frontier Goods', 'WEST', 'EMMA', 980000, 190000, 'W-2001-SSN')
  into customers values ( 7, 'Granite Media',  'WEST', 'EMMA', 840000, 165000, 'W-2002-SSN')
  into customers values ( 8, 'Harbor Systems', 'WEST', 'EMMA', 720000, 145000, 'W-2003-SSN')
  into customers values ( 9, 'Ironwood Bank',  'WEST', 'EMMA', 680000, 130000, 'W-2004-SSN')
  into customers values (10, 'Juniper Works',  'WEST', 'EMMA', 610000, 120000, 'W-2005-SSN')
  into customers values (11, 'Keystone Energy','CENTRAL','MARVIN',1030000, 200000, 'C-3001-SSN')
  into customers values (12, 'Lumen Freight',  'CENTRAL','MARVIN',810000, 155000, 'C-3002-SSN')
  into customers values (13, 'Meridian Hotel', 'CENTRAL','MARVIN',740000, 140000, 'C-3003-SSN')
  into customers values (14, 'Northstar Co',   'SOUTH', 'PRIYA',690000, 135000, 'S-4001-SSN')
  into customers values (15, 'Oak & Pine',     'SOUTH', 'PRIYA',560000, 110000, 'S-4002-SSN')
  into customers values (16, 'Pioneer Group',  'NORTH', 'PRIYA',520000, 105000, 'N-5001-SSN')
  into customers values (17, 'Quartz Design',  'NORTH', 'PRIYA',490000, 100000, 'N-5002-SSN')
  into customers values (18, 'Redwood Travel', 'EAST', 'PRIYA', 430000,  90000, 'E-1006-SSN')
  into customers values (19, 'Summit Auto',    'WEST', 'EMMA',410000,  85000, 'W-2006-SSN')
  into customers values (20, 'Tidal Markets',  'SOUTH', 'PRIYA',390000,  80000, 'S-4003-SSN')
  -- Finance rows remain outside the sales manager's scope.
  into customers values (21, 'Apex Treasury',  'NORTH', 'FINANCE', 1110000, 275000, 'F-6001-TAX')
  into customers values (22, 'Crown Capital',  'SOUTH', 'FINANCE', 1200000, 310000, 'F-6002-TAX')
select 1 from dual;

prompt SQL> COMMIT
commit;

prompt Sample data ready: 22 customer rows are available for the lab.

set define on
