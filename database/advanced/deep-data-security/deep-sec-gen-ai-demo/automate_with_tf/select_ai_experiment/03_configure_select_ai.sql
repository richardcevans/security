set echo off
set verify off
set feedback on
set serveroutput on size unlimited
set linesize 200
set long 1000000
whenever sqlerror exit sql.sqlcode rollback
column active_profile format a40

define GENAI_COMPARTMENT_OCID = '&1'
define GENAI_REGION = '&2'
define GENAI_MODEL = '&3'

prompt ============================================================================
prompt Enable OCI resource-principal authentication for ADMIN
prompt ============================================================================
prompt BEGIN DBMS_CLOUD_ADMIN.ENABLE_PRINCIPAL_AUTH(provider => 'OCI'); END;
BEGIN DBMS_CLOUD_ADMIN.ENABLE_PRINCIPAL_AUTH(provider => 'OCI'); END;
/

prompt ============================================================================
prompt Replace the ADMIN-owned DEEPSEC_HR_CHAT Select AI profile
prompt ============================================================================
prompt BEGIN DBMS_CLOUD_AI.DROP_PROFILE('DEEPSEC_HR_CHAT'); EXCEPTION WHEN OTHERS THEN NULL; END;
BEGIN DBMS_CLOUD_AI.DROP_PROFILE('DEEPSEC_HR_CHAT'); EXCEPTION WHEN OTHERS THEN NULL; END;
/
prompt BEGIN DBMS_CLOUD_AI.CREATE_PROFILE(profile_name => 'DEEPSEC_HR_CHAT', ...); END;
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
      "object_list": [{"owner":"HR","name":"EMPLOYEES"},{"owner":"HR","name":"MANAGERS"}],
      "enforce_object_list": "true",
      "temperature": 0
    }~'
  );
END;
/
prompt GRANT EXECUTE ON DBMS_CLOUD_AI TO HRAPP_EMPLOYEES;
prompt BEGIN DBMS_CLOUD_AI.SET_PROFILE('DEEPSEC_HR_CHAT'); END;
BEGIN DBMS_CLOUD_AI.SET_PROFILE('DEEPSEC_HR_CHAT'); END;
/
prompt SELECT DBMS_CLOUD_AI.GET_PROFILE() AS active_profile FROM dual;
SELECT DBMS_CLOUD_AI.GET_PROFILE() AS active_profile FROM dual;
prompt ============================================================================
prompt Harmless Select AI chat smoke test (does not query HR data)
prompt ============================================================================
prompt SELECT DBMS_CLOUD_AI.GENERATE(<fixed harmless prompt>, 'DEEPSEC_HR_CHAT', 'chat') AS response FROM dual;
SELECT DBMS_CLOUD_AI.GENERATE('Reply with exactly: Select AI profile smoke test passed.', 'DEEPSEC_HR_CHAT', 'chat') AS response FROM dual;
exit success
