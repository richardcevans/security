-- Use this exact read-only query as a Database Tools MCP Custom SQL tool or
-- SQL Report. Run it through MCP, not directly in SQL*Plus.
-- It proves Database Tools MCP CLIENTCONTEXT propagation only. It does NOT
-- prove OCI IAM OAuth group-to-data-role activation.

SELECT SYS_CONTEXT('CLIENTCONTEXT', 'OAUTH_SUB_TYPE')                 AS oauth_sub_type,
       SYS_CONTEXT('CLIENTCONTEXT', 'OAUTH_SUB')                      AS oauth_sub,
       SYS_CONTEXT('CLIENTCONTEXT', 'OAUTH_USER_OCID')                AS oauth_user_ocid,
       SYS_CONTEXT('CLIENTCONTEXT', 'IAM_DOMAIN_APP_ROLES')           AS iam_domain_app_roles,
       SYS_CONTEXT('CLIENTCONTEXT', 'RESOURCE_OCID')                  AS mcp_server_ocid,
       SYS_CONTEXT('CLIENTCONTEXT', 'RESOURCE_COMPARTMENT_OCID')      AS mcp_server_compartment_ocid
  FROM dual;
