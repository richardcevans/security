# Optional Lab 6: Connect VS Code and Cline to the MCP Server

## Introduction

Connect an external MCP client to the OCI Database Tools MCP server created in Lab 3. This optional lab uses VS Code and Cline so you can inspect MCP tools, approve tool calls, and compare client behavior with the prompt simulator and SQL validation already used in the workshop.

Estimated Time: 25 minutes

### Objectives

In this lab, you will:

- Confirm the MCP server endpoint and toolset values.
- Register a public MCP client in the OCI identity domain.
- Configure Cline with a local or approved model provider.
- Add the OCI Database Tools MCP server as a remote MCP server.
- Run controlled prompt tests and review each tool call before approval.

### Prerequisites

- Completed Lab 3.
- Completed Lab 5 if you want to validate least-privilege behavior from Cline.
- VS Code installed on your workstation.
- Cline extension installed in VS Code.
- A Cline model provider configured. For workshop use, prefer a local provider such as Ollama or LM Studio when available.
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

## Task 2: Register a Cline MCP Client

1. In the OCI Console, open **Developer Services**, then **Database Tools**, then **Model Context Protocol Servers**.

2. Open the MCP server named by `MCP_SERVER_NAME`.

3. Open the **Clients** tab.

4. Click **Register Model Context Protocol client**.

5. Use these values.

    | Field | Value |
    | --- | --- |
    | Name | `deep-sec-mcp-cline` |
    | Description | `VS Code Cline client for DeepSec MCP workshop` |
    | Type | `Public` |
    | Allowed scope | `urn:opc:dbtools:mcpserver:all` |
    | Redirect URI | Use the localhost redirect URI shown by Cline or the default URI required by the OCI registration page |

6. Complete the registration.

7. From the registered client or MCP server page, generate or download a personal access token for the MCP client.

    If the server was created with a short token lifetime, create a fresh token shortly before testing from Cline.

8. Save the token only in your local Cline configuration. Do not paste it into workshop notes, Git commits, screenshots, or shared chat messages.

## Task 3: Configure Cline's Model Provider

1. Open VS Code.

2. Open the Cline extension.

3. Open **Settings**.

4. Configure a model provider.

    For a workshop environment that should not require new external model accounts, use a local runtime when available:

    - **Ollama** with base URL `http://localhost:11434`
    - **LM Studio** with base URL `http://localhost:1234`

5. Verify the model connection in Cline before adding the MCP server.

    Keep the first prompts small. Local models can be slower than hosted models, especially on small laptops.

## Task 4: Add the OCI MCP Server to Cline

1. In Cline, open **MCP Servers**.

2. Open the **Configure** tab.

3. Click **Configure MCP Servers**.

4. Add a remote MCP server entry.

    Use `streamableHttp` when the OCI endpoint supports streamable HTTP. Use `sse` only if the endpoint or client registration indicates legacy SSE.

    ```json
    <copy>
    {
      "mcpServers": {
        "deep-sec-mcp": {
          "type": "streamableHttp",
          "url": "<mcp_server_endpoint_url>",
          "headers": {
            "Authorization": "Bearer <mcp_personal_access_token>"
          },
          "disabled": false,
          "autoApprove": []
        }
      }
    }
    </copy>
    ```

5. Save the Cline MCP configuration.

6. Restart or refresh the MCP server in Cline.

7. Confirm that Cline lists the OCI Database Tools MCP tools.

    Keep `autoApprove` empty for this workshop. Manual approval is part of the security demonstration because it shows which SQL or tool action the client is about to run.

## Task 5: Test Controlled Tool Calls

1. In Cline, ask for available MCP tools.

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

5. Compare the Cline result with the Lab 5 expected result.

    | User Context | Expected Result After Controls |
    | --- | --- |
    | Employee | Own row only, with sensitive data controlled by policy |
    | Manager | Self and direct reports, with sensitive data controlled by policy |
    | Overprivileged administrative path | Not used for least-privilege validation |

6. If Cline proposes a broad query, inspect it before approval.

    The database policy should still enforce the data-layer rules, but the review step shows why client-side prompts and approval dialogs are not a substitute for database authorization.

## Task 6: Troubleshoot Cline Connectivity

1. If Cline cannot connect to the MCP server, confirm the endpoint and token.

    ```bash
    <copy>
    env | grep -E '^(MCP_SERVER_ID|MCP_SERVER_ENDPOINT)=' | sort
    </copy>
    ```

2. If Cline reports an authorization error, generate a fresh MCP personal access token and update the Cline MCP server headers.

3. If the tools do not appear, confirm the MCP server and built-in SQL toolset are active.

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

4. If Cline connects but the model does not respond, verify the Cline model provider separately from the MCP server.

5. If a query returns more or less data than expected, repeat the same SQL from Lab 5 using SQL*Plus and compare the authenticated identity and database roles.

## Task 7: Review the Security Boundary

1. Confirm the result of the optional Cline test.

    | Boundary | What It Proves |
    | --- | --- |
    | Cline model provider | Generates the request and chooses whether to call a tool |
    | Cline MCP approval | Gives the user a chance to inspect a proposed tool call |
    | OCI Database Tools MCP server | Exposes database tools through an MCP resource path |
    | Autonomous Database | Evaluates the active database identity and data roles |
    | Deep Data Security | Enforces row and sensitive-attribute access at the data layer |

2. Keep Cline manual approvals enabled for any later testing.

3. Remove the MCP token from local configuration when you no longer need the client connection.

    You may now proceed to the cleanup lab.

## Learn More

- [Creating a Database Tools MCP Server](https://docs.oracle.com/en-us/iaas/database-tools/doc/creating-mcp-server.html)
- [Registering an MCP Client](https://docs.oracle.com/en-us/iaas/database-tools/doc/registering-mcp-client.html)
- [Cline MCP configuration](https://docs.cline.bot/mcp/mcp-overview)
- [Cline local models](https://docs.cline.bot/running-models-locally/overview)

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
