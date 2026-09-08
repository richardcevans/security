# Optional Lab 2: Connect Cline to the MCP Server

## Introduction

Connect Cline to the OCI Database Tools MCP server created in Lab 2. This lab
uses `mcp-remote` and a registered OCI IAM public client so Cline can complete
the OAuth browser flow without relying on dynamic client registration.

Estimated Time: 25 minutes

### Objectives

In this lab, you will:

- Confirm the MCP server endpoint and toolset values.
- Register a public MCP client in the OCI identity domain.
- Register a Cline public OAuth client through the lab script.
- Generate a Cline `mcp-remote` configuration with that client ID.
- Complete OCI IAM OAuth without placing an access token in Cline settings.
- Run controlled prompt tests and review each tool call before approval.

### Prerequisites

- Completed Lab 2.
- Cline installed in VS Code on your workstation.
- Node.js 20 or later and `npx` available where the VS Code Server runs Cline.
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

## Task 2: Register the Cline Public Client

1. Run the registration script. It discovers the scope from the actual MCP
    resource application, previews the public-client configuration, and asks
    for `CREATE` only after showing the redirect URI.

    ```bash
    <copy>
    ./02_register_cline_mcp_client.sh
    </copy>
    ```

2. The script registers this exact redirect URI for Cline through
    `mcp-remote`:

    ```text
    <copy>
    http://localhost:8080/oauth/callback
    </copy>
    ```

    The script sets the Identity Domains `all-url-schemes-allowed` option for
    this public client. That is required when a domain otherwise rejects the
    localhost HTTP callback. It still registers only the URI shown above.

3. Generate the Cline settings entry. This creates a local file only; it does
    not alter VS Code settings.

    ```bash
    <copy>
    ./create_cline_mcp_config.sh
    </copy>
    ```

## Task 3: Add the MCP Server to Cline

1. On the workstation that runs Cline, install the `mcp-remote` helper if it
    is not already available.

    ```bash
    <copy>
    npm install -g mcp-remote
    </copy>
    ```

2. Verify the VS Code Server has Node.js 20 or later. Current `mcp-remote`
    releases require Node.js 20 or later.

    ```bash
    <copy>
    ./03_verify_cline_runtime.sh
    </copy>
    ```

3. Open Cline's `cline_mcp_settings.json` file and merge the `deep-sec-mcp`
    entry from `cline_mcp_settings.generated.json`.

4. Close every VS Code window, then reopen the Remote/WSL workspace and
    connect to `deep-sec-mcp` in Cline. This ensures Cline inherits the Node.js
    runtime selected for the remote environment.

5. Complete the OCI IAM browser sign-in as the intended test user. The local
    callback must remain on port `8080`, which is the port registered in the
    public client.

6. Confirm that Cline lists the OCI Database Tools MCP tools. Keep manual
    tool approval enabled for this workshop.

## Task 4: Test Controlled Tool Calls

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

4. Treat the first protected-data request as an identity-propagation test, not
    as proof that the interactive OCI IAM identity reached ADB. Before approving
    it, note the signed-in OCI IAM user and run the GenAI audit report in a
    separate Cloud Shell tab after the request completes.

    ```text
    <copy>
    Use the DeepSec MCP SQL tool to show the employee rows I am allowed to see. Include employee_id, full name, manager_id, department_name, salary, and ssn if those columns are available.
    </copy>
    ```

5. Compare the MCP result and the new audit event with the direct GenAI
    baseline. The audit entry must be evaluated for database user, client
    program, and Deep Data Security end user.

    | Test result | Meaning |
    | --- | --- |
    | The expected OCI IAM end user is recorded and the visible rows match the direct GenAI baseline | Record the result; the managed MCP path has evidence for this tested configuration. |
    | The end user is absent, different, or the visible rows differ from the direct GenAI baseline | Stop the protected-data exercise. Do not claim Deep Data Security identity propagation for this MCP configuration. |

6. If Cline proposes a broad query, inspect it before approval.

    Client-side prompts and approval dialogs are not a substitute for database
    authorization. The dedicated test above is required because the Database
    Tools MCP runtime identity is configured separately from the interactive
    OCI IAM user identity.

## Task 5: Troubleshoot Cline Connectivity

1. If Cline cannot connect to the MCP server, confirm the endpoint.

    ```bash
    <copy>
    env | grep -E '^(MCP_SERVER_ID|MCP_SERVER_ENDPOINT)=' | sort
    </copy>
    ```

2. If Cline reports an OAuth or redirect error, regenerate the settings file
    with `./create_cline_mcp_config.sh`. Confirm the entry uses `mcp-remote`
    and that the public client was registered with the localhost port `8080`.

    Then run the read-only diagnostic report. Pass the ECID shown on an OCI IAM
    error page when available.

    ```bash
    <copy>
    ./04_troubleshoot_cline_oauth.sh --minutes 120 --ecid '<ecid-from-browser-error>'
    </copy>
    ```

    The report summarizes the MCP server, Cline public-client registration,
    local generated configuration, and relevant OCI Audit events. It does not
    print OAuth tokens, refresh tokens, client secrets, or wallet passwords.

3. If OCI reports `invalid_redirect_uri`, the Cline public client's registered
    redirect URI must be:

    ```text
    <copy>
    http://localhost:8080/oauth/callback
    </copy>
    ```

    The script sets the Identity Domains `all-url-schemes-allowed` option for
    this public client. That is required when a domain otherwise rejects the
    localhost HTTP callback. It still registers only the URI shown above.

    Rerun `./02_register_cline_mcp_client.sh` if you need a new app, then
    regenerate and merge the settings file.

4. If Cline reports an authorization error after browser sign-in, remove and
    reconnect `deep-sec-mcp` in Cline, then complete sign-in again.

5. If Cline reports `Missing required permissions`, confirm the signed-in user is a member of the IAM domain group used by the MCP server policies.

    The OAuth consent page confirms authentication. It does not grant OCI permissions by itself. The user, such as Marvin or Emma, must be in the domain group that is allowed to invoke the MCP server and use the supporting Database Tools resources.

    If the error includes an `opc-request-id`, run the troubleshooting helper from Cloud Shell.

    ```bash
    <copy>
    ./troubleshoot_mcp_request.sh '<opc-request-id-from-cline>'
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

    If the MCP toolset uses extra features, add the matching service-specific policy required by your toolset. After policy or group membership changes, sign out and reconnect the MCP server in Cline.

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

7. If Cline connects but the model does not respond, verify the Cline model provider separately from the MCP server.

8. If a query returns more or less data than expected, repeat the same SQL from Lab 5 using SQL*Plus and compare the authenticated identity and database roles.

## Task 6: Review the Security Boundary

1. Confirm the result of the optional Cline test.

    | Boundary | What It Proves |
    | --- | --- |
    | Cline model provider | Generates the request and chooses whether to call a tool |
    | Cline MCP approval | Gives the user a chance to inspect a proposed tool call |
    | OCI Database Tools MCP server | Exposes database tools through an MCP resource path |
    | Autonomous Database | Evaluates the active database identity and data roles |
    | Deep Data Security | Enforces row and sensitive-attribute access at the data layer |

2. Keep Cline manual approvals enabled for any later testing.

3. Remove the MCP server from Cline settings when you no longer need the client connection.

    You may now proceed to the cleanup lab.

## Learn More

- [Creating a Database Tools MCP Server](https://docs.oracle.com/en-us/iaas/database-tools/doc/creating-mcp-server.html)
- [Registering an MCP Client](https://docs.oracle.com/en-us/iaas/database-tools/doc/registering-mcp-client.html)
- [Connect an MCP Server Using Token-Based Authentication](https://docs.oracle.com/en-us/iaas/database-tools/doc/tutorial-connect-mcp-server-using-token-based-authentication.html)

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
