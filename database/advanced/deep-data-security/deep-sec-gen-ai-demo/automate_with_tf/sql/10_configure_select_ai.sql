-- Minimal Select AI profile. This profile is owned by ADMIN and only its
-- fixed chat smoke test is executed here. No HR rows are queried or sent.

set echo off
set verify off
set feedback on
set serveroutput on size unlimited
set linesize 200
set pagesize 100
set long 1000000
set longchunksize 1000000
whenever sqlerror exit sql.sqlcode rollback

define GENAI_COMPARTMENT_OCID = '&1'
define GENAI_REGION = '&2'
define GENAI_MODEL = '&3'

prompt ============================================================================
prompt Enable OCI resource-principal authentication for ADMIN
prompt ============================================================================
BEGIN
  DBMS_CLOUD_ADMIN.ENABLE_PRINCIPAL_AUTH(provider => 'OCI');
END;
/

prompt ============================================================================
prompt Replace only the ADMIN-owned DEEPSEC_HR_CHAT Select AI profile
prompt ============================================================================
BEGIN
  DBMS_CLOUD_AI.DROP_PROFILE('DEEPSEC_HR_CHAT');
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
/

BEGIN
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'DEEPSEC_HR_CHAT',
    attributes   => q'~{
      "provider": "oci",
      "credential_name": "OCI$RESOURCE_PRINCIPAL",
      "oci_compartment_id": "&GENAI_COMPARTMENT_OCID",
      "region": "&GENAI_REGION",
      "model": "&GENAI_MODEL",
      "oci_apiformat": "GENERIC",
      "object_list": [{"owner": "HR", "name": "EMPLOYEES"}],
      "enforce_object_list": "true",
      "temperature": 0
    }~'
  );
END;
/

BEGIN
  DBMS_CLOUD_AI.SET_PROFILE('DEEPSEC_HR_CHAT');
END;
/

prompt ============================================================================
prompt Verify the active Select AI profile
prompt ============================================================================
SELECT DBMS_CLOUD_AI.GET_PROFILE() AS active_profile FROM dual;

prompt ============================================================================
prompt Harmless Select AI chat smoke test through DBMS_CLOUD_AI.GENERATE (does not query HR data)
prompt ============================================================================
SELECT DBMS_CLOUD_AI.GENERATE(
         prompt       => 'Reply with exactly: Select AI profile smoke test passed.',
         profile_name => 'DEEPSEC_HR_CHAT',
         action       => 'chat'
       ) AS response
FROM dual;

exit success
