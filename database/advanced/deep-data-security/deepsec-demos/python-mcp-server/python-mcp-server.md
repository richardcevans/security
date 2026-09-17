# Lab 3: Configure the Reusable Python Oracle SQL MCP Server

## Introduction

Configure the application-only Oracle SQL MCP pattern from
`deepsec-demos-python-mcp-server`. This version assumes that the database,
wallet, OCI IAM applications, scopes, and Deep Data Security policies already
exist. It shows how a reusable Streamable HTTP resource server validates the
caller token, exposes a small read-only tool set, and propagates end-user
identity to Oracle.

This lab is independent of Lab 2. You may reuse Lab 2 resources if they are
available, but copy and review this project's own `.env.example` and do not
assume that Lab 2's generated `.env` is compatible.

Estimated Time: 25 minutes

### Objectives

In this lab, you will:

- Map the required database, OAuth, introspection, and GenAI settings.
- Start the MCP resource server on loopback and inspect its protected-resource
  metadata.
- Authenticate with the companion client and exercise the read-only tools.
- Review the application controls separately from Oracle authorization.

### Prerequisites

- An existing Oracle database with Deep Data Security data roles and grants.
- An extracted wallet and a database connection identity allowed to use the
  end-user security provider.
- OCI IAM browser-login, database/midtier, and MCP resource applications with
  the scopes and introspection operation described in the [source README](../../deepsec-demos-python-mcp-server/README.md).
- Python 3.11 or later, `curl`, and an OCI CLI/API-key profile if using the
  optional GenAI client.

### Required files, directories, packages, and configuration

| Item | Required state |
| --- | --- |
| Source application | `pyproject.toml`, `.env.example`, `src/oracle_sql_mcp/`, and `tests/test_sql.py` containing the server, token verifier, database, OAuth client, SQL guard, optional GenAI client, and read-only guard tests. |
| Database and identity resources | An existing wallet-backed database, OCI IAM browser-login and confidential clients, resource audience/scope, introspection permission, and Deep Data Security data roles/grants. This project has no database setup scripts. |
| Runtime configuration | Copy `.env.example` to ignored `.env`, set mode `600`, and provide the database, OAuth, MCP, introspection, and optional GenAI values. |
| ADB wallet | `SSL_CONFIG_DIR` must contain `tnsnames.ora`, `sqlnet.ora`, `cwallet.sso`, and `ewallet.p12`; keep the wallet outside Git. |
| Python runtime | Python 3.11 or later, `venv`, and `pip`; editable install resolves `httpx`, `mcp`, `oci`, `oracledb`, and `python-dotenv`. |
| Host packages and tools | `git`, `curl`, `wget`, `openssl`, `ca-certificates`, `libffi`, `gcc`, and `make` as needed for wheels; OCI CLI and SQL*Plus/SQLcl are separate tools. |

This is an application-only lab. It does not create ADB objects, IAM apps,
wallets, or data grants, and it does not depend on Lab 2.

## Task 1: Install the application

1. Set `LAB_ROOT` and enter the application-only source directory.

    ```bash
    <copy>
    export LAB_ROOT="${LAB_ROOT:-$HOME/dbsec-labs/deep-data-security}"
    cd "$LAB_ROOT/deepsec-demos-python-mcp-server"
    </copy>
    ```

2. Create a project-local virtual environment and install the package.

    ```bash
    <copy>
    python3 -m venv .venv
    source .venv/bin/activate
    python3 -m pip install -e .
    </copy>
    ```

3. Confirm the package imports without printing configuration values.

    ```bash
    <copy>
    PYTHONPATH="$PWD/src" python3 -c \
      'from mcp.server.fastmcp import FastMCP; import httpx, oci, oracledb; print("Dependencies available")'
    </copy>
    ```

## Task 2: Configure the OAuth and database boundary

1. Copy the sanitized template into the ignored runtime file and protect its
   permissions.

    ```bash
    <copy>
    cp .env.example .env
    chmod 600 .env
    </copy>
    ```

2. Edit `.env` and populate the existing environment values. Use placeholders
   only in notes or commits. The required groups are:

   - `DB_USER`, `DB_PASSWORD`, `DB_DSN`, `SSL_CONFIG_DIR`, and `WALLET_PWD`.
   - `DB_CLIENT_ID`, `DB_CLIENT_SECRET`, and `DB_SCOPE` for the database or
     midtier confidential client.
   - `OCI_DOMAIN_URL`, `APP_CLIENT_ID`, `APP_CLIENT_SECRET`, `APP_SCOPE`, and
     the exact `REDIRECT_URI` for browser login.
   - `MCP_AUTHORIZATION_SERVER_URL`, `MCP_TOKEN_ISSUER`,
     `MCP_AUTH_AUDIENCE`, and `MCP_REQUIRED_SCOPES` for resource-server
     validation.
   - `OCI_CONFIG_FILE`, `OCI_PROFILE`, `COMPARTMENT_ID`, `MODEL_ID`, and
     `OCI_GENAI_ENDPOINT` only when using the companion GenAI client.

    Do not assume `APP_SCOPE` and `MCP_REQUIRED_SCOPES` are textually equal.
    The former is requested by the client; the latter must match the access
    token's actual scope claim.

3. Check only that the file exists and remains ignored.

    ```bash
    <copy>
    test -s .env
    git check-ignore -q .env
    </copy>
    ```

## Task 3: Start the resource server

1. In Terminal 1, bind the server to loopback for this lab.

    ```bash
    <copy>
    cd "$LAB_ROOT/deepsec-demos-python-mcp-server"
    source .venv/bin/activate
    PYTHONPATH="$PWD/src" python3 -m oracle_sql_mcp.server \
      --host 127.0.0.1 --port 8000
    </copy>
    ```

2. In a second terminal, inspect the protected-resource metadata.

    ```bash
    <copy>
    curl -sS http://127.0.0.1:8000/.well-known/oauth-protected-resource/mcp
    </copy>
    ```

    Confirm that the response identifies the authorization server configured
    for the resource. A local loopback listener is suitable for development;
    do not expose it directly to the internet.

## Task 4: Authenticate and exercise the MCP tools

1. In Terminal 2, start the companion client.

    ```bash
    <copy>
    cd "$LAB_ROOT/deepsec-demos-python-mcp-server"
    source .venv/bin/activate
    PYTHONPATH="$PWD/src" python3 -m oracle_sql_mcp.client_app \
      --server-url http://127.0.0.1:8000/mcp
    </copy>
    ```

2. Complete the browser login and ask `who am i`. Record the identity visible
   to the database.

3. Ask `what tables can I see` and `describe the HR employees table`. Then ask
   a narrow question about the signed-in user. Confirm that the response is
   consistent with the user's data roles and data grants.

4. Review the four exposed tools in the source. `execute_sql` is guarded as a
   read-only, bounded statement path; that guard reduces application risk but
   does not replace database privileges or Deep Data Security.

    ```bash
    <copy>
    cd "$LAB_ROOT/deepsec-demos-python-mcp-server"
    rg -n "get_current_user|list_tables|describe_table|execute_sql|introspect|set_end_user_identity" \
      src/oracle_sql_mcp
    </copy>
    ```

5. Stop the client and server with `Ctrl+C` in their respective terminals.

## Task 5: Record the deployment boundary

1. Leave the server bound to `127.0.0.1` for this demonstration. A remote
   deployment would require HTTPS, a public resource URL, network controls,
   audit logging, token-policy review, and an approved secret-management
   design.

2. Remove the local virtual environment and `.env` only if your environment's
   cleanup policy allows it. Keep any shared wallet or database resources that
   were not created by this lab.

    You may now proceed to the next lab, or select another independent lab.

## Learn More

- [Oracle Database Tools MCP Server](https://docs.oracle.com/en-us/iaas/database-tools/doc/mcp-servers.html)
- [Integrate Database Tools MCP Server with Oracle Deep Data Security](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/integrate-database-tools-mcp-server.html)
- [Oracle Deep Data Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/oracle-deep-data-security-guide.pdf)
- [Source README and project files](../../deepsec-demos-python-mcp-server/README.md)

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - September 2026
