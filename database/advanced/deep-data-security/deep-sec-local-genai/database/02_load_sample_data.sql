-- Run as an ADB administrator after 01_create_schema.sql.
whenever sqlerror exit sql.sqlcode rollback
set echo off

-- Preserve literal ampersands in sample customer names. Re-enable substitution
-- before returning to the caller because the user-creation script prompts for passwords.
set define off

alter session set current_schema = applab;

insert all
  into customers values ( 1, 'Acme East',       'EAST', 'SALES_TEAM', 920000, 180000, 'E-1001-SSN')
  into customers values ( 2, 'Beacon Health',  'EAST', 'SALES_TEAM', 870000, 160000, 'E-1002-SSN')
  into customers values ( 3, 'Cedar Retail',   'EAST', 'SALES_TEAM', 760000, 150000, 'E-1003-SSN')
  into customers values ( 4, 'Delta Foods',    'EAST', 'SALES_TEAM', 650000, 125000, 'E-1004-SSN')
  into customers values ( 5, 'Evergreen Labs', 'EAST', 'SALES_TEAM', 590000, 115000, 'E-1005-SSN')
  into customers values ( 6, 'Frontier Goods', 'WEST', 'MARVIN', 980000, 190000, 'W-2001-SSN')
  into customers values ( 7, 'Granite Media',  'WEST', 'MARVIN', 840000, 165000, 'W-2002-SSN')
  into customers values ( 8, 'Harbor Systems', 'WEST', 'MARVIN', 720000, 145000, 'W-2003-SSN')
  into customers values ( 9, 'Ironwood Bank',  'WEST', 'MARVIN', 680000, 130000, 'W-2004-SSN')
  into customers values (10, 'Juniper Works',  'WEST', 'MARVIN', 610000, 120000, 'W-2005-SSN')
  into customers values (11, 'Keystone Energy','CENTRAL','MARVIN',1030000, 200000, 'C-3001-SSN')
  into customers values (12, 'Lumen Freight',  'CENTRAL','MARVIN',810000, 155000, 'C-3002-SSN')
  into customers values (13, 'Meridian Hotel', 'CENTRAL','MARVIN',740000, 140000, 'C-3003-SSN')
  into customers values (14, 'Northstar Co',   'SOUTH', 'MARVIN',690000, 135000, 'S-4001-SSN')
  into customers values (15, 'Oak & Pine',     'SOUTH', 'MARVIN',560000, 110000, 'S-4002-SSN')
  into customers values (16, 'Pioneer Group',  'NORTH', 'MARVIN',520000, 105000, 'N-5001-SSN')
  into customers values (17, 'Quartz Design',  'NORTH', 'MARVIN',490000, 100000, 'N-5002-SSN')
  into customers values (18, 'Redwood Travel', 'EAST', 'SALES_TEAM', 430000,  90000, 'E-1006-SSN')
  into customers values (19, 'Summit Auto',    'WEST', 'MARVIN',410000,  85000, 'W-2006-SSN')
  into customers values (20, 'Tidal Markets',  'SOUTH', 'MARVIN',390000,  80000, 'S-4003-SSN')
  -- Finance rows remain outside the sales manager's scope.
  into customers values (21, 'Apex Treasury',  'NORTH', 'FINANCE', 1110000, 275000, 'F-6001-TAX')
  into customers values (22, 'Crown Capital',  'SOUTH', 'FINANCE', 1200000, 310000, 'F-6002-TAX')
select 1 from dual;

commit;

set define on
