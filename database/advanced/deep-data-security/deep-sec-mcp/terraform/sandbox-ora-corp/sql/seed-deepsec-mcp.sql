-- Starter SQL for the DeepSec MCP sandbox.
-- Replace placeholders after the final public Deep Data Security syntax is confirmed.

-- Suggested identity model per participant:
--   <participant_id>a = restricted user
--   <participant_id>b = privileged user

-- Example data-role mapping shape. Validate final mapping prefixes before use.
CREATE DATA ROLE employee_data_role
  MAPPED TO 'IAM_GROUP_NAME=employee';

-- Example application identity shape. Replace with the participant OAuth client ID.
CREATE APPLICATION IDENTITY deepsec_mcp_app
  MAPPED TO 'IAM_OAUTH_CLIENT_ID=<client_id>';

-- Example application identity grant.
GRANT DATA ROLE employee_data_role TO deepsec_mcp_app;

-- TODO: Add sample schema, synthetic sensitive data, data grants, and validation queries.

