# Lab 5: Run LangChain HR and Compensation Agents with Microsoft Entra ID

## Introduction

Configure the two-agent LangChain sample in
`deepsec-demos-ananya-langchain-demo`. The HR Agent uses Microsoft Entra ID
application roles mapped to Deep Data Security data roles. The Compensation
Analytics Agent uses a separate Entra application and an Oracle Application
Identity. Both paths use the Oracle Python end-user security provider so the
database, rather than the LangChain prompt, determines visible rows and
columns.

This lab is an independent alternate identity-provider path. It assumes a
working Oracle database and identity configuration and does not require any
earlier lab.

Estimated Time: 40 minutes

### Objectives

In this lab, you will:

- Register the database, login, HR midtier, and compensation applications in
  Microsoft Entra ID.
- Configure the Oracle identity provider, mapped data roles, and application
  identity described by the source setup script.
- Run the HR and compensation agents through separate authorization paths.
- Compare user-scoped and aggregate results without treating LLM instructions
  as an authorization boundary.

### Prerequisites

- Oracle AI Database 23.26.2 or later on Linux with Deep Data Security
  available, a named database user with DBA access, SQL*Plus, and a working
  TCPS wallet/listener environment.
- A Microsoft Entra ID tenant where you can register applications, define
  scopes and application roles, grant admin consent, and assign users.
- OCI Generative AI access and an OCI SDK/API-key profile.
- Python 3.12, the source directory, and the ability to install its
  `requirements.txt` dependencies.
- The [source README](../../deepsec-demos-ananya-langchain-demo/README.md) and
  `setup.sql` available under `LAB_ROOT`.

### Required files, directories, packages, and configuration

| Item | Required state |
| --- | --- |
| Source application | `app_config.py`, `db_connection.py`, `get_user_token.py`, `langchain_app.py`, `langchain_tools.py`, `requirements.txt`, and `.env.example`. |
| Database setup | `setup.sql` with tenant, application, user, password, and connection placeholders completed in a private working copy or controlled SQL session. |
| TCPS environment | The project-specific `T_WORK/sslserver` or approved equivalent must contain the client/server wallet and listener configuration required by the source README; `TNS_ADMIN` must point to the active directory. |
| Runtime configuration | Copy `.env.example` to ignored `.env`; configure both HR and compensation Entra downstream clients, the interactive client, database connection, OCI profile, model ID, and pool limits. |
| Python runtime | Python 3.12, `venv`, and `pip`; the requirements file supplies LangChain, OCI, Oracle, MSAL, and dotenv dependencies. |
| Host packages and tools | `openssl`, `ca-certificates`, `libffi`, `gcc`, and `make` as needed for wheels; SQL*Plus and the environment-specific `oratst`/proxy tooling are separate Oracle test-harness dependencies. |

This lab is intentionally an alternate Entra ID path. It does not depend on
the OCI IAM labs, and its local database/listener setup must be validated in a
separate non-production environment.

## Task 1: Register the Entra applications

1. Set the source root and inspect the application configuration template.

    ```bash
    <copy>
    export LAB_ROOT="${LAB_ROOT:-$HOME/dbsec-labs/deep-data-security}"
    cd "$LAB_ROOT/deepsec-demos-ananya-langchain-demo"
    sed -n '1,220p' .env.example
    </copy>
    ```

2. In the Microsoft Entra admin center, create the Database App as a
   single-tenant registration. Expose it as an API, define the delegated scope
   `sessions:scope:connect`, and save its application/client ID, tenant ID,
   and application ID URI.

3. Create the Client App as a single-tenant web registration with the exact
   redirect URI used by the source application, such as
   `http://localhost:3000`. Grant it delegated access to the Database App and
   the agent scopes after the remaining applications exist.

4. Create the HR/Midtier App. Give it an application ID URI, the delegated
   `user_access` scope, a client secret, and application roles named
   `EMPLOYEE_ROLE` and `MANAGER_ROLE`. Grant it delegated access to the
   Database App and pre-authorize it for `sessions:scope:connect`.

5. Create the Compensation App. Give it an application ID URI, the delegated
   `agent_impersonation` scope, a client secret, and the required compensation
   application role. Grant and pre-authorize its Database App access.

6. Grant admin consent and assign only the intended demo users or groups to
   the applications and roles. Record IDs and secrets in an approved secret
   store or local ignored configuration file, not in Git.

## Task 2: Configure the Oracle authorization model

1. Review the placeholder definitions in `setup.sql`. Replace the database
   password, connection string, Entra tenant/application identifiers, demo
   user email addresses, and other local values in a private copy or SQL
   terminal input.

2. Confirm that the script's authorization model contains both paths:

    ```sql
    <copy>
    CREATE OR REPLACE DATA ROLE EMPLOYEE_FS_ROLE
    MAPPED TO 'AZURE_APP=<HR application URI>:azure_role=EMPLOYEE_ROLE';

    CREATE OR REPLACE DATA ROLE MANAGER_FS_ROLE
    MAPPED TO 'AZURE_APP=<HR application URI>:azure_role=MANAGER_ROLE';

    CREATE OR REPLACE APPLICATION IDENTITY compensation_app
    MAPPED TO 'AZURE_CLIENT_ID=<Compensation App client ID>';
    </copy>
    ```

3. Run the setup script as instructed by the source README in a non-production
   environment. It updates sample HR data, creates performance notes and
   Deep Data Security data grants, and configures
   `IDENTITY_PROVIDER_TYPE=AZURE_AD` with its database application settings.

    ```bash
    <copy>
    sqlplus / as sysdba
    </copy>
    ```

    ```sql
    <copy>
    @/absolute/path/to/deepsec-demos-ananya-langchain-demo/setup.sql
    </copy>
    ```

4. Verify the data-role and application-identity definitions before starting
   the Python application. Do not broaden HR privileges to make a failed
   identity mapping appear to work.

## Task 3: Configure OCI SDK and Python dependencies

1. Create or reuse an OCI SDK profile with access to the selected Generative
   AI endpoint. Keep the API private key in the OCI configuration directory
   with restrictive permissions.

    ```bash
    <copy>
    mkdir -p ~/.oci
    chmod 700 ~/.oci
    </copy>
    ```

2. Install the application dependencies in a project-local virtual environment.

    ```bash
    <copy>
    cd "$LAB_ROOT/deepsec-demos-ananya-langchain-demo"
    python3.12 -m venv .venv
    .venv/bin/python -m pip install -r requirements.txt
    </copy>
    ```

3. Copy `.env.example` to the ignored `.env` and configure the database wallet,
   Entra client settings, agent scopes, OCI Generative AI model, and region.
   The source application reads `MODEL_ID` and
   `OCI_GENAI_SERVICE_ENDPOINT` from `.env`; do not commit client secrets,
   private keys, passwords, wallets, or bearer tokens.

## Task 4: Run the HR Agent

1. Start the default HR Agent.

    ```bash
    <copy>
    cd "$LAB_ROOT/deepsec-demos-ananya-langchain-demo"
    .venv/bin/python langchain_app.py
    </copy>
    ```

2. Complete the browser sign-in for a user assigned to the HR application.
   Ask `Who reports to me?`, `show my employee information`, and a narrowly
   scoped search question.

3. Confirm that the HR Agent tools return only the rows and columns authorized
   by the mapped employee or manager data role. `execute_sql` accepts reviewed
   `SELECT` statements, while updates require the application confirmation
   flow described in the source README.

## Task 5: Run the Compensation Analytics Agent

1. Stop the HR Agent and start the separate compensation path.

    ```bash
    <copy>
    cd "$LAB_ROOT/deepsec-demos-ananya-langchain-demo"
    .venv/bin/python langchain_app.py --agent compensation
    </copy>
    ```

2. Complete the Compensation App sign-in and ask for an aggregate salary
   summary by job, location, or department. Confirm that the application
   identity receives only the columns granted to `SALARY_AGENT_FS_ROLE`.

3. Compare the output with the HR Agent. The two agents share a harness but
   use different Entra and Oracle authorization paths. An agent prompt cannot
   replace the Oracle data grants.

4. Review the most recent application log if a run fails, and redact all
   secrets before sharing diagnostics.

    ```bash
    <copy>
    tail -n 120 langchain_demo.log
    </copy>
    ```

    You may now proceed to the next lab, or select another independent lab.

## Learn More

- [Oracle Deep Data Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/oracle-deep-data-security-guide.pdf)
- [Building Trusted Generative AI Experiences with Oracle Deep Data Security](https://blogs.oracle.com/database/building-trusted-genai-experiences-with-oracle-deep-data-security)
- [Source README and setup script](../../deepsec-demos-ananya-langchain-demo/README.md)

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - September 2026
