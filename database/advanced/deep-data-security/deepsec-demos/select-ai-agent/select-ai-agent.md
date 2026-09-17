# Lab 4: Run a Select AI Agent Team with Deep Data Security

## Introduction

Build the database-native Select AI Agent objects in
`deepsec-demos-select-ai-oci-demo`, then run the supplied Python CLI as an
OCI IAM end user. The CLI attaches the end-user identity to a
`python-oracledb` connection and calls `DBMS_CLOUD_AI_AGENT.RUN_TEAM` on that
same session. Deep Data Security controls the SQL Tool's rows and columns.

This lab is independent of the LangChain and MCP labs. Its database setup is
destructive because it recreates the sample HR schema; use only a disposable
database or a separately approved existing-database path.

Estimated Time: 35 minutes

### Objectives

In this lab, you will:

- Prepare the disposable HR database and Deep Data Security runner role.
- Create a GenAI credential, Select AI profile, SQL Tool, Agent, Task, and
  Team with least-privilege grants.
- Run the Team through the signed-in user's token-attached session.
- Compare user questions and verify that agent instructions do not replace
  database authorization.

### Prerequisites

- Autonomous AI Database with OCI IAM external authentication and Select AI
  Agent support enabled.
- An extracted wallet, SQLcl or SQL*Plus, Python 3.10 or later, and `curl` if
  needed for diagnostics.
- OCI IAM employee and manager groups with users assigned, plus browser-login
  and database-access applications with an exact redirect URI.
- OCI Generative AI access, a permitted model, and an OCI API signing key for
  the database credential. Never commit or save the private key in `.env`.
- The [source README](../../deepsec-demos-select-ai-oci-demo/README.md) and
  SQL files available under the `LAB_ROOT` source directory.

### Required files, directories, packages, and configuration

| Item | Required state |
| --- | --- |
| Source application | `app_config.py`, `db_connection.py`, `get_user_token.py`, `select_ai_agent_app.py`, `requirements.txt`, and `.env.example`. |
| Database scripts | `setup_demo_database.sql` (destructive `ADMIN` setup), `setup_select_ai_access.sql` (`ADMIN` credential sharing), and `setup_select_ai.sql` (`DB_USR` Select AI objects). |
| Runtime configuration | Copy `.env.example` to ignored `.env`, set mode `600`, and populate database, IAM, wallet, and Select AI owner/name values. |
| ADB wallet | `SSL_CONFIG_DIR` must contain `tnsnames.ora`, `sqlnet.ora`, `cwallet.sso`, and `ewallet.p12`; set `TNS_ADMIN` to the same directory for SQL*Plus/SQLcl. |
| Python runtime | Python 3.10 or later, `venv`, and `pip`; the requirements file supplies `oracledb` and the OAuth/CLI dependencies. |
| Host packages and tools | `curl`, `wget`, `openssl`, `ca-certificates`, `libffi`, `gcc`, and `make` as needed for wheels; SQL*Plus or SQLcl is required for the SQL setup steps. |

The GenAI private key is entered only in the `DBMS_CLOUD.CREATE_CREDENTIAL`
call and must not be placed in `.env`, a wallet archive, or Git.

## Task 1: Prepare the wallet and database connection

1. Set the source root and database connection values in the current shell.
   Replace placeholders locally; do not put real values in the Markdown or
   Git.

    ```bash
    <copy>
    export LAB_ROOT="${LAB_ROOT:-$HOME/dbsec-labs/deep-data-security}"
    cd "$LAB_ROOT/deepsec-demos-select-ai-oci-demo"
    export WALLET_DIR="$HOME/adb_wallet/<extracted-wallet-directory>"
    export TNS_ADMIN="$WALLET_DIR"
    export ADB_SERVICE="<wallet-tns-alias>"
    </copy>
    ```

2. Confirm that the source files and wallet directory exist without printing
   the wallet contents.

    ```bash
    <copy>
    test -f setup_demo_database.sql
    test -f setup_select_ai_access.sql
    test -f setup_select_ai.sql
    test -d "$WALLET_DIR"
    </copy>
    ```

## Task 2: Create the sample HR data and runner role

1. Read the `DEFINE` values at the top of `setup_demo_database.sql` and replace
   its placeholders in a private working copy or SQL terminal input. This
   script drops and recreates the sample `HR` schema. Do not run it against a
   shared or production database.

2. Connect as `ADMIN` and run the setup script.

    ```bash
    <copy>
    sql "admin@$ADB_SERVICE"
    </copy>
    ```

    ```sql
    <copy>
    @/absolute/path/to/deepsec-demos-select-ai-oci-demo/setup_demo_database.sql
    </copy>
    ```

3. Confirm that the script creates `DB_USR`, sample HR data, the
   `HRAPP_EMPLOYEES` and `HRAPP_MANAGERS` data roles, and
   `HR_SELECT_AI_RUNNER`. Do not copy the generated passwords or private key
   values into the lab record.

## Task 3: Create and share the GenAI credential

1. Connect as `DB_USR` and create `GENAI_CRED` using the private key only in
   the SQL terminal. Use the `DBMS_CLOUD.CREATE_CREDENTIAL` block in the
   source README and replace its placeholders with the approved GenAI user,
   tenancy, fingerprint, and private key values.

    ```bash
    <copy>
    sql "db_usr@$ADB_SERVICE"
    </copy>
    ```

2. Reconnect as `ADMIN` and run the access-sharing script with these definitions.

    ```sql
    <copy>
    DEFINE PROFILE_OWNER = DB_USR
    DEFINE CREDENTIAL_NAME = GENAI_CRED
    DEFINE CREDENTIAL_SYNONYM = HR_GENAI_CRED
    DEFINE RUNNER_ROLE = HR_SELECT_AI_RUNNER
    @/absolute/path/to/deepsec-demos-select-ai-oci-demo/setup_select_ai_access.sql
    </copy>
    ```

3. Confirm that the public synonym resolves to `DB_USR.GENAI_CRED` and that
   the runner role has the required `EXECUTE` access. The synonym is only a
   name; the credential remains protected by database privileges.

## Task 4: Create the Select AI profile and Agent Team

1. Reconnect as `DB_USR` and create the `HR_PROFILE` with the source README's
   `DBMS_CLOUD_AI.CREATE_PROFILE` block. Set the provider, credential name
   `HR_GENAI_CRED`, model, GenAI compartment, region, and the four allowed HR
   objects. Keep `enforce_object_list` enabled.

2. In the same `DB_USR` session, define the object names and run
   `setup_select_ai.sql`.

    ```sql
    <copy>
    DEFINE PROFILE_OWNER = DB_USR
    DEFINE PROFILE_NAME = HR_PROFILE
    DEFINE AGENT_NAME = HR_AGENT
    DEFINE TASK_NAME = HR_TASK
    DEFINE TEAM_NAME = HR_TEAM
    DEFINE SQL_TOOL_NAME = HR_SQL_TOOL
    DEFINE RUNNER_ROLE = HR_SELECT_AI_RUNNER
    @/absolute/path/to/deepsec-demos-select-ai-oci-demo/setup_select_ai.sql
    </copy>
    ```

3. Confirm that the script reports the SQL Tool, Agent, Task, and Team as
   enabled. If a package privilege error occurs, review the runner-role
   grants in `setup_demo_database.sql` before adding any broader HR privilege.

## Task 5: Configure and run the CLI

1. Create the local runtime and copy the sanitized configuration template.

    ```bash
    <copy>
    cd "$LAB_ROOT/deepsec-demos-select-ai-oci-demo"
    python3 -m venv .venv
    .venv/bin/python -m pip install -r requirements.txt
    cp .env.example .env
    chmod 600 .env
    </copy>
    ```

2. Populate `.env` with the wallet, database, browser-login, database-access,
   and Select AI object names described in the source README. Keep private
   keys, client secrets, wallet files, and tokens outside Git.

3. Run the CLI, complete the browser login, and paste the full redirect URL
   back into the terminal when prompted.

    ```bash
    <copy>
    .venv/bin/python select_ai_agent_app.py
    </copy>
    ```

## Task 6: Verify user-scoped Select AI results

1. As an employee, ask `who am i` and `show my employee information including
   my ssn`. Record which fields are returned and which are filtered or masked.

2. As a manager, ask `show my team's performance notes`. Compare the result
   with the employee session.

3. Ask `show all employee records` from both sessions. The model's answer must
   reflect the rows and columns the database returned; prompt wording cannot
   grant access to a protected field.

4. If a run fails, inspect the Select AI object views and the error text using
   the troubleshooting queries in the source README. Do not grant broad HR
   `SELECT` privileges as a workaround.

    You may now proceed to the next lab, or select another independent lab.

## Learn More

- [Getting Started with Select AI Agent](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/getting-started-select-ai-agent.html)
- [Examples of Using Select AI Agent](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/examples-using-select-ai-agent.html)
- [Oracle Deep Data Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/oracle-deep-data-security-guide.pdf)
- [Source README and SQL files](../../deepsec-demos-select-ai-oci-demo/README.md)

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - September 2026
