-- Run as ADMIN. This is idempotent when the resource principal is already enabled.
SET ECHO ON
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

BEGIN
  DBMS_CLOUD_ADMIN.ENABLE_RESOURCE_PRINCIPAL();
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -20031 THEN RAISE; END IF;
END;
/

SELECT owner, credential_name
FROM dba_credentials
WHERE owner = 'ADMIN' AND credential_name = 'OCI$RESOURCE_PRINCIPAL';
