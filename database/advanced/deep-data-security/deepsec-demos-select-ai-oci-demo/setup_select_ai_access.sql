-- Copyright (c) 2026, Oracle and/or its affiliates.
--
-- Shares the GenAI credential with token-authenticated Deep Data Security
-- users. Run this script as ADMIN after DB_USR creates GENAI_CRED and before
-- DB_USR creates the Select AI profile.

SET DEFINE ON
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

-- Define these values before running the script. If omitted, SQLcl/SQL*Plus
-- prompts for each value when it is first referenced.
--
-- DEFINE PROFILE_OWNER = DB_USR
-- DEFINE CREDENTIAL_NAME = GENAI_CRED
-- DEFINE CREDENTIAL_SYNONYM = HR_GENAI_CRED
-- DEFINE RUNNER_ROLE = HR_SELECT_AI_RUNNER

PROMPT Granting the runner role access to the profile owner's GenAI credential
GRANT EXECUTE ON &PROFILE_OWNER..&CREDENTIAL_NAME TO &RUNNER_ROLE;

PROMPT Creating the public credential synonym used by the Select AI profile
-- Use a demo-specific synonym name. CREATE OR REPLACE makes rerunning this
-- script safe only when the name is reserved for this demo.
CREATE OR REPLACE PUBLIC SYNONYM &CREDENTIAL_SYNONYM
  FOR &PROFILE_OWNER..&CREDENTIAL_NAME;

PROMPT Verifying credential access setup
SELECT owner, synonym_name, table_owner, table_name
FROM dba_synonyms
WHERE owner = 'PUBLIC'
  AND synonym_name = UPPER('&CREDENTIAL_SYNONYM');

PROMPT Credential access setup completed successfully.
