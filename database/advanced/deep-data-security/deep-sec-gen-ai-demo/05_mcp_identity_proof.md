# MCP identity propagation proof

Do not connect protected HR data to MCP yet.

When a Database Tools MCP Server is provisioned, register the SQL in
`05_mcp_identity_proof.sql` as a read-only Custom SQL tool or SQL Report and
call it through an MCP client while signed in as the intended user.

Pass criteria:

1. `OAUTH_SUB` identifies the MCP caller.
2. `IAM_DOMAIN_APP_ROLES` contains the expected MCP application role.
3. `RESOURCE_OCID` identifies the expected MCP server.

This proves documented `CLIENTCONTEXT` propagation only. It does not prove
that OCI IAM OAuth group claims activate `HRAPP_EMPLOYEES` or
`HRAPP_MANAGERS`; that must be tested independently before MCP is permitted to
query `HR.EMPLOYEES`.
