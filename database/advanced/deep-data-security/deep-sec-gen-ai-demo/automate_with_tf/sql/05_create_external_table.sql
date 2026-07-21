-- Run only after resource-principal IAM access to the private bucket is proven.
-- The system credential OCI$RESOURCE_PRINCIPAL avoids a long-lived user credential.
SET ECHO ON
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE hr.employee_bonuses_ext PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
BEGIN
  DBMS_CLOUD.CREATE_EXTERNAL_TABLE(
    table_name      => 'EMPLOYEE_BONUSES_EXT',
    credential_name => 'OCI$RESOURCE_PRINCIPAL',
    file_uri_list   => '&bonus_file_uri',
    format          => JSON_OBJECT('delimiter' VALUE ',', 'skipheaders' VALUE '1'),
    column_list     => 'EMPLOYEE_ID NUMBER, BONUS_YEAR NUMBER, BONUS_AMOUNT NUMBER');
END;
/
