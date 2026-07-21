set echo off
set feedback on
set linesize 200
set pagesize 100
set trimspool on
whenever sqlerror exit sql.sqlcode rollback

prompt ============================================================================
prompt Latest ten HR.EMPLOYEES Unified Audit Trail entries
prompt SELECT timestamp, command, database user, client program, and Deep Data Security end user
prompt FROM UNIFIED_AUDIT_TRAIL WHERE OBJECT_SCHEMA = 'HR'
prompt   AND OBJECT_NAME = 'EMPLOYEES' ORDER BY EVENT_TIMESTAMP_UTC DESC;
prompt ============================================================================

column event_timestamp_utc format a27 heading 'TIMESTAMP (UTC)'
column command format a12 heading 'COMMAND'
column database_user format a16 heading 'DATABASE USER'
column client_program_name format a52 heading 'CLIENT PROGRAM'
column end_user format a38 heading 'DEEP DATA SECURITY END USER'

SELECT TO_CHAR(event_timestamp_utc, 'YYYY-MM-DD HH24:MI:SS.FF3') || ' UTC'
         AS event_timestamp_utc,
       action_name AS command,
       dbusername AS database_user,
       client_program_name,
       NVL(end_user_name, '-') AS end_user
  FROM (
    SELECT event_timestamp_utc,
           action_name,
           dbusername,
           client_program_name,
           end_user_name
      FROM unified_audit_trail
     WHERE object_schema = 'HR'
       AND object_name = 'EMPLOYEES'
     ORDER BY event_timestamp_utc DESC
  )
 WHERE ROWNUM <= 10;

exit success
