-- This file intentionally creates no database objects.
--
-- Oracle Customer Sales opens each database session directly as MARVIN using
-- the password entered at sign-in. Oracle Deep Data Security evaluates
-- MARVIN's end-user identity and active data roles for that session.
-- Flask receives only the rows and columns Oracle authorizes for MARVIN.
set echo off

prompt Oracle Customer Sales uses direct database authentication as MARVIN.
prompt The password entered at sign-in is verified by Oracle Database for that session.
prompt Oracle Deep Data Security evaluates MARVIN's active data roles and grants.
prompt Flask receives only the rows and columns Oracle authorizes for MARVIN.
prompt No database objects are created by this step.
