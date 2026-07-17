# Optional Lab 2: Connect Cursor to the MCP Server

## Introduction

Connect an external MCP client to the OCI Database Tools MCP server created in Lab 2. This optional lab uses Cursor so you can sign in through OCI IAM, inspect MCP tools, and approve tool calls.

Estimated Time: 25 minutes

### Objectives

In this lab, you will:

- Confirm the MCP server endpoint and toolset values.
- Register a public MCP client in the OCI identity domain.
- Configure Cursor with a local or approved model provider.
- Add the OCI Database Tools MCP server as a remote MCP server.
- Use OAuth with the registered Cursor client ID instead of a bearer token.
- Run controlled prompt tests and review each tool call before approval.

### Prerequisites

- Completed Lab 2.
- Cursor installed on your workstation.
- A Cursor model provider configured. For workshop use, prefer a local or approved provider when available.
- Permission to register MCP clients for the MCP server identity domain.

## Task 1: Confirm MCP Server Values

1. In Cloud Shell, load the lab environment.

    ```bash
    <copy>
    cd "$HOME/dbsec-labs/deep-data-security/deep-sec-mcp"
    source ./.deep-sec-mcp.env
    </copy>
    ```

2. Confirm the MCP resource values.

    ```bash
    <copy>
    env | grep -E '^(MCP_SERVER_ID|MCP_SERVER_NAME|MCP_BUILT_IN_SQL_TOOLSET_ID|MCP_COMPARTMENT_OCID|MCP_IDENTITY_DOMAIN_OCID)=' | sort
    </copy>
    ```

3. Display the MCP server details.

    ```bash
    <copy>
    oci dbtools mcp-server get \
      --mcp-server-id "$MCP_SERVER_ID" \
      --query 'data.{name:"display-name",state:"lifecycle-state",endpoints:endpoints}' \
      --output json
    </copy>
    ```

4. If the CLI output does not show the endpoint clearly, get it from the OCI Console.

    Open **Developer Services**, then **Database Tools**, then **Model Context Protocol Servers**. Open the server named by `MCP_SERVER_NAME` and copy the server endpoint from the details page.

5. Save the endpoint in the current shell.

    ```bash
    <copy>
    export MCP_SERVER_ENDPOINT="<mcp_server_endpoint_url>"
    </copy>
    ```

## Task 2: Register a Cursor MCP Client

1. In the OCI Console, open **Developer Services**, then **Database Tools**, then **Model Context Protocol Servers**.

2. Open the MCP server named by `MCP_SERVER_NAME`.

3. Open the **Clients** tab.

4. Click **Register Model Context Protocol client**.

5. Use these values.

    | Field | Value |
    | --- | --- |
    | Name | `deep-sec-mcp-cursor` |
    | Description | `Cursor client for DeepSec MCP workshop` |
    | Type | `Public` |
    | Allowed grant types | Confirm the page shows `authorization_code` and `refresh_token` |
    | Scope | Use the scope displayed by the registration page |
    | Redirect URI | `cursor://anysphere.cursor-mcp/oauth/callback` |

    The scope can be server-specific. For example, the page may display a value in this shape:

    ```text
    <copy>
    urn:opc:dbtools:mcpserver:<mcp_server_ocid>:mcp:all
    </copy>
    ```

    Copy the value shown by your page instead of typing a generic scope.

6. Add Cursor's OAuth callback URI.

    ```text
    <copy>
    cursor://anysphere.cursor-mcp/oauth/callback
    </copy>
    ```

    Cursor sends this redirect URI during the OCI IAM browser login. The value must be registered exactly. If OCI later returns `invalid_redirect_uri`, edit or recreate the MCP client registration and add the redirect URI named in the error message.

7. Complete the registration.

8. Copy the **Client ID** shown on the registration details page.

    You will use this value in Cursor's `mcp.json` file. This is not an access token and it is not a client secret.

9. Save the values in the current shell if you want to generate the Cursor configuration from Cloud Shell.

    ```bash
    <copy>
    export CURSOR_MCP_CLIENT_ID="<client_id_from_registration_page>"
    </copy>
    ```

10. Do not generate a personal access token for this path.

    Cursor will start an OAuth browser sign-in flow when it connects to the MCP server.

## Task 3: Configure Cursor's Model Provider

1. Open Cursor.

2. Open **Settings**.

3. Configure a model provider.

    For a workshop environment that should not require new external model accounts, use a local runtime when available:

    - **Ollama** with base URL `http://localhost:11434`
    - **LM Studio** with base URL `http://localhost:1234`

4. Verify the model connection in Cursor before adding the MCP server.

    Keep the first prompts small. Local models can be slower than hosted models, especially on small laptops.

## Task 4: Add the OCI MCP Server to Cursor

1. In Cursor, open **Settings**.

2. Open **MCP**.

3. Open your global `mcp.json` file.

4. Add the OCI Database Tools MCP server entry.

    Do not add an `Authorization` header. Cursor should prompt you to sign in through OCI IAM.

    Use the **Client ID** from the OCI registration details page. Without the static client ID, Cursor can try dynamic client registration and fail with an error such as `Incompatible auth server: does not support dynamic client registration`.

    ```json
    <copy>
    {
      "mcpServers": {
        "deep-sec-mcp": {
          "type": "http",
          "url": "<mcp_server_endpoint_url>",
          "auth": {
            "CLIENT_ID": "<client_id_from_registration_page>"
          }
        }
      }
    }
    </copy>
    ```

5. Save `mcp.json`.

6. Restart Cursor or reload the Cursor window.

7. In Cursor **Settings**, open **MCP** and connect to `deep-sec-mcp`.

8. Complete the OCI IAM browser sign-in when Cursor prompts you.

9. Confirm that Cursor lists the OCI Database Tools MCP tools.

    Keep `autoApprove` empty for this workshop. Manual approval is part of the security demonstration because it shows which SQL or tool action the client is about to run.

## Task 5: Test Controlled Tool Calls

1. In Cursor, ask for available MCP tools.

    ```text
    <copy>
    List the tools available from the deep-sec-mcp MCP server. Do not run any SQL yet.
    </copy>
    ```

2. Run a harmless connectivity test.

    ```text
    <copy>
    Use the DeepSec MCP SQL tool to run: select sys_context('USERENV','AUTHENTICATED_IDENTITY') as authenticated_identity from dual
    </copy>
    ```

3. Review the proposed MCP tool call before approving it.

4. Run an employee-access prompt that matches the workshop validation matrix.

    ```text
    <copy>
    Use the DeepSec MCP SQL tool to show the employee rows I am allowed to see. Include employee_id, full name, manager_id, department_name, salary, and ssn if those columns are available.
    </copy>
    ```

5. Compare the Cursor result with the Lab 5 expected result.

    | User Context | Expected Result After Controls |
    | --- | --- |
    | Employee | Own row only, with sensitive data controlled by policy |
    | Manager | Self and direct reports, with sensitive data controlled by policy |
    | Overprivileged administrative path | Not used for least-privilege validation |

6. If Cursor proposes a broad query, inspect it before approval.

    The database policy should still enforce the data-layer rules, but the review step shows why client-side prompts and approval dialogs are not a substitute for database authorization.

## Task 6: Troubleshoot Cursor Connectivity

1. If Cursor cannot connect to the MCP server, confirm the endpoint.

    ```bash
    <copy>
    env | grep -E '^(MCP_SERVER_ID|MCP_SERVER_ENDPOINT)=' | sort
    </copy>
    ```

2. If Cursor reports `Incompatible auth server: does not support dynamic client registration`, confirm that the `deep-sec-mcp` entry in `mcp.json` includes the `auth.CLIENT_ID` value copied from the OCI registration details page.

3. If OCI reports `invalid_redirect_uri`, edit or recreate the MCP client registration and add the exact redirect URI from the error message.

    For Cursor, this is normally:

    ```text
    <copy>
    cursor://anysphere.cursor-mcp/oauth/callback
    </copy>
    ```

    After you update or recreate the registration, reconnect the MCP server in Cursor. If you created a new registration, update `auth.CLIENT_ID` in `mcp.json` with the new Client ID.

4. If Cursor reports an authorization error after the client ID and redirect URI are configured, remove and reconnect the `deep-sec-mcp` server from Cursor **Settings**, then complete the OCI IAM browser sign-in again.

5. If Cursor reports `Missing required permissions`, confirm the signed-in user is a member of the IAM domain group used by the MCP server policies.

    The OAuth consent page confirms authentication. It does not grant OCI permissions by itself. The user, such as Marvin or Emma, must be in the domain group that is allowed to invoke the MCP server and use the supporting Database Tools resources.

    If the error includes an `opc-request-id`, run the troubleshooting helper from Cloud Shell.

    ```bash
    <copy>
    ./troubleshoot_mcp_request.sh '<opc-request-id-from-cursor>'
    </copy>
    ```

    The script searches OCI Audit for the MCP request and summarizes the signed-in user, MCP client app, MCP server app, MCP app roles, lab groups, and relevant app-role grants.

    If the OCI Audit event for `InvokeMcpServer` has HTTP status `200` but says `JSON-RPC reported an error`, the OCI API invocation reached the MCP server. In that case, check MCP application role assignments next. The signed-in user or the user's group must have an MCP application role such as `MCP_User` or `MCP_Operator`, and the role must be allowed by the toolset.

    For an MCP server that uses **Authenticated Principal** runtime identity, the policy set should include permissions in this shape, using your domain name, group name, and compartment name:

    ```text
    <copy>
    allow group '<identity_domain_name>'/'<mcp_users_group>' to use database-tools-mcp-servers-invocation in compartment <compartment_name>
    allow group '<identity_domain_name>'/'<mcp_users_group>' to use database-connections in compartment <compartment_name>
    allow group '<identity_domain_name>'/'<mcp_users_group>' to use database-tools-connections in compartment <compartment_name>
    allow group '<identity_domain_name>'/'<mcp_users_group>' to use database-tools-runtime-work-requests in compartment <compartment_name>
    allow group '<identity_domain_name>'/'<mcp_users_group>' to read secret-bundles in compartment <compartment_name>
    allow group '<identity_domain_name>'/'<mcp_users_group>' to use buckets in compartment <compartment_name>
    allow group '<identity_domain_name>'/'<mcp_users_group>' to manage objects in compartment <compartment_name>
    </copy>
    ```

    If the MCP toolset uses extra features, add the matching service-specific policy required by your toolset. After policy or group membership changes, sign out and reconnect the MCP server in Cursor.

6. If the tools do not appear, confirm the MCP server and built-in SQL toolset are active.

    ```bash
    <copy>
    oci dbtools mcp-server get \
      --mcp-server-id "$MCP_SERVER_ID" \
      --query 'data."lifecycle-state"' \
      --raw-output

    oci dbtools mcp-toolset list \
      --compartment-id "$MCP_COMPARTMENT_OCID" \
      --type BUILT_IN_SQL_TOOLS \
      --all \
      --query "data[?id=='${MCP_BUILT_IN_SQL_TOOLSET_ID}'].\"lifecycle-state\" | [0]" \
      --raw-output
    </copy>
    ```

7. If Cursor connects but the model does not respond, verify the Cursor model provider separately from the MCP server.

8. If a query returns more or less data than expected, repeat the same SQL from Lab 5 using SQL*Plus and compare the authenticated identity and database roles.

## Task 7: Review the Security Boundary

1. Confirm the result of the optional Cursor test.

    | Boundary | What It Proves |
    | --- | --- |
    | Cursor model provider | Generates the request and chooses whether to call a tool |
    | Cursor MCP approval | Gives the user a chance to inspect a proposed tool call |
    | OCI Database Tools MCP server | Exposes database tools through an MCP resource path |
    | Autonomous Database | Evaluates the active database identity and data roles |
    | Deep Data Security | Enforces row and sensitive-attribute access at the data layer |

2. Keep Cursor manual approvals enabled for any later testing.

3. Remove the MCP server from Cursor settings when you no longer need the client connection.

    You may now proceed to the cleanup lab.

## Learn More

- [Creating a Database Tools MCP Server](https://docs.oracle.com/en-us/iaas/database-tools/doc/creating-mcp-server.html)
- [Registering an MCP Client](https://docs.oracle.com/en-us/iaas/database-tools/doc/registering-mcp-client.html)
- [Cursor MCP configuration](https://docs.cursor.com/context/model-context-protocol)

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
