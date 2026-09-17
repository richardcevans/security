# Lab 2: Run an OCI IAM-Protected Oracle SQL MCP Server

## Introduction

Run the local Streamable HTTP Oracle SQL MCP server from
`deepsec-demos-mcp-oci-script-demo`. Its setup bundle creates or reuses the
ADB and OCI IAM configuration, then the Python server validates the caller's
OCI IAM token before its read-only tools query Oracle through the end-user
security provider.

This is a local FastMCP application pattern. It is not the managed OCI
Database Tools MCP Server. The lab is independent; it does not require Lab 1.

Estimated Time: 35 minutes

### Objectives

In this lab, you will:

- Create or reuse the demo ADB, IAM, HR schema, and Deep Data Security setup.
- Install and configure the OAuth-protected MCP server and companion client.
- Inspect the read-only tools and token-validation boundary.
- Run identity and table-discovery prompts and record the authorized result.

### Prerequisites

- OCI Cloud Shell or Linux with Bash, OCI CLI, Python 3.11 or later, and an
  extracted wallet when using the included setup.
- Permission to create or reuse the OCI IAM and ADB resources used by
  `adb-oci-iam`.
- OCI Generative AI access and an OCI CLI profile for the companion client.
- The [source README](../../deepsec-demos-mcp-oci-script-demo/README.md) and
  source files available under a parent directory named by `LAB_ROOT`.

### Required files, directories, packages, and configuration

| Item | Required state |
| --- | --- |
| Source application | `pyproject.toml`, `src/oracle_sql_mcp/`, and `tests/test_sql.py` with the server, verifier, database, SQL guard, OAuth client, optional GenAI client, and read-only guard tests. |
| Setup directory | `adb-oci-iam/` with the numbered setup, verification, helper, and cleanup scripts. |
| Runtime configuration | `.env.example` is the sanitized template; copy it to ignored `.env`. The setup path also writes `adb-oci-iam/.adb-oci-iam.env`. |
| ADB wallet | `SSL_CONFIG_DIR` must point to a wallet containing `tnsnames.ora`, `sqlnet.ora`, `cwallet.sso`, and `ewallet.p12`; `WALLET_PWD` is supplied separately. |
| OCI configuration | `OCI_CONFIG_FILE`, `OCI_PROFILE`, `COMPARTMENT_ID`, `MODEL_ID`, and `OCI_GENAI_ENDPOINT` are required for the optional chat client. |
| Python runtime | Python 3.11 or later, `venv`, and `pip`; the project declares `httpx`, `mcp`, `oci`, `oracledb`, and `python-dotenv`. |
| Host packages and tools | `git`, `unzip`, `curl`, `wget`, `openssl`, `ca-certificates`, `libffi`, `gcc`, and `make` as needed for wheels; OCI CLI and SQL*Plus/SQLcl are separate tools. |

The local server is intentionally loopback-only for this lab. Its OAuth
configuration requires database settings, browser-login settings, protected
resource metadata, and an introspection client. Do not expose the demo with
`--allow-remote-http` until the production controls in
[production-readiness.md](../production-readiness.md) exist.

## Task 1: Install the MCP application

1. Set the source root and enter the MCP project.

    ```bash
    <copy>
    export LAB_ROOT="${LAB_ROOT:-$HOME/dbsec-labs/deep-data-security}"
    cd "$LAB_ROOT/deepsec-demos-mcp-oci-script-demo"
    </copy>
    ```

2. Create a project-local virtual environment and install the package in
   editable mode.

    ```bash
    <copy>
    python3 -m venv .venv
    source .venv/bin/activate
    python3 -m pip install -e .
    </copy>
    ```

3. Confirm the main runtime imports without printing secret configuration.

    ```bash
    <copy>
    PYTHONPATH="$PWD/src" python3 -c \
      'from mcp.server.fastmcp import FastMCP; import httpx, oci, oracledb; print("Dependencies available")'
    </copy>
    ```

## Task 2: Create or reuse the ADB and IAM environment

1. If you are using an existing ADB, export the wallet, database password,
   OCI profile, and optional tag values described in the source README. Do not
   save those values in Git.

2. Run the bundled database setup sequence. It writes the ignored
   `adb-oci-iam/.adb-oci-iam.env` and project `.env` files.

    ```bash
    <copy>
    cd "$LAB_ROOT/deepsec-demos-mcp-oci-script-demo/adb-oci-iam"
    ./00_setup_adb.sh
    source ./.adb-oci-iam.env
    ./01_enable_oci_iam.sh
    ./02_create_hr_schema.sh
    ./03_create_data_roles_and_grants.sh
    ./verify_db_setup.sh
    ./set_oci_iam_passwords.sh --all
    cd ..
    </copy>
    ```

3. Confirm that the generated project configuration contains values for the
   database, IAM, MCP server, and GenAI settings. Inspect names only; never
   print or share passwords, client secrets, tokens, or private keys.

    ```bash
    <copy>
    test -s .env
    test -s adb-oci-iam/.adb-oci-iam.env
    test -f .env.example
    sed -n '1,220p' .env.example
    </copy>
    ```

## Task 3: Run the local MCP server and client

1. In Terminal 1, start the server on loopback. Keep this terminal open.

    ```bash
    <copy>
    cd "$LAB_ROOT/deepsec-demos-mcp-oci-script-demo"
    source .venv/bin/activate
    PYTHONPATH="$PWD/src" python3 -m oracle_sql_mcp.server \
      --host 127.0.0.1 --port 8000
    </copy>
    ```

2. In Terminal 2, enter the same project and start the companion chat client.

    ```bash
    <copy>
    cd "$LAB_ROOT/deepsec-demos-mcp-oci-script-demo"
    source .venv/bin/activate
    PYTHONPATH="$PWD/src" python3 -m oracle_sql_mcp.client_app \
      --server-url http://127.0.0.1:8000/mcp
    </copy>
    ```

3. Complete the OCI IAM browser login. The client sends the access token to
   the local MCP server; the server introspects it and then the database
   connection applies the caller's end-user security context.

## Task 4: Exercise the tools and verify authorization

1. Ask `who am i` and record the identity returned by the database session.

2. Ask `what tables can I see` and `describe the HR employees table`. Confirm
   that metadata reflects the database privileges and data grants for the
   authenticated user.

3. Ask a narrow HR question, such as `show my employee profile`, and compare
   the result with the identity returned in the first step. Do not use an
   arbitrary SQL statement to try to bypass the lab's read-only guard.

4. Review the source guard and token verifier after the successful call.

    ```bash
    <copy>
    cd "$LAB_ROOT/deepsec-demos-mcp-oci-script-demo"
    rg -n "execute_sql|SELECT|WITH|introspect|MCP_REQUIRED_SCOPES|MCP_AUTH_AUDIENCE" \
      src/oracle_sql_mcp
    </copy>
    ```

    The application rejects missing or invalid tokens and limits the exposed
    SQL tool, but the database remains the authority for row and column access.

5. Stop the client and server with `Ctrl+C` in their respective terminals.

## Task 5: Review cleanup boundaries

1. If this lab created a disposable environment, inspect the cleanup script
   before choosing a cleanup mode.

    ```bash
    <copy>
    sed -n '1,260p' "$LAB_ROOT/deepsec-demos-mcp-oci-script-demo/adb-oci-iam/07_cleanup_adb_lab.sh"
    </copy>
    ```

2. Use the least destructive mode needed. Do not remove a shared ADB, IAM
   application, or wallet that another lab or user owns.

    ```bash
    <copy>
    cd "$LAB_ROOT/deepsec-demos-mcp-oci-script-demo/adb-oci-iam"
    ./07_cleanup_adb_lab.sh --delete-db-objects
    </copy>
    ```

    You may now proceed to the next lab, or select another independent lab.

## Learn More

- [Oracle Database Tools MCP Server](https://docs.oracle.com/en-us/iaas/database-tools/doc/mcp-servers.html)
- [Integrate Database Tools MCP Server with Oracle Deep Data Security](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/integrate-database-tools-mcp-server.html)
- [Oracle Deep Data Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/oracle-deep-data-security-guide.pdf)
- [Source README and project files](../../deepsec-demos-mcp-oci-script-demo/README.md)

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - September 2026
