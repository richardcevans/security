# Lab 1: Build a LangChain HR Assistant with Oracle Deep Data Security

## Introduction

This lab converts the LangChain Deep Data Security demo package into a repeatable workflow. You will configure a Python HR assistant that uses LangChain tools and OCI Generative AI. Oracle Database enforces end-user access with Deep Data Security data roles and data grants.

The source package contains two identity-provider variants:

| Variant | Folder | Use when |
| --- | --- | --- |
| OCI IAM | `python-langchain-oci` | Your users, groups, OAuth applications, and scopes are in OCI IAM. |
| Microsoft Entra ID | `python-langchain-msei` | Your users, roles, and OAuth applications are in Microsoft Entra ID. |

> **Warning:** Run this lab only in an isolated demo, sandbox, or non-production environment. The setup scripts can modify users, data roles, data grants, audit policies, and HR sample data. They can also change identity-provider settings. Do not use these steps with production databases, identity tenants, or applications.

Estimated Time: 75 minutes

### Objectives

In this lab, you will:

- Extract and inspect the LangChain Deep Data Security demo package.
- Choose the OCI IAM or Microsoft Entra ID identity-provider path.
- Configure Python packages, OCI SDK access, Oracle Database connectivity, and OCI Generative AI.
- Configure Deep Data Security data roles and data grants.
- Generate or acquire an end-user OAuth access token.
- Run the LangChain HR assistant as an employee and as a manager.
- Validate that Deep Data Security changes the visible HR data by user identity.

### Prerequisites

- You have an Oracle Database environment where Deep Data Security is available.
- You can connect as a privileged database user to run setup scripts.
- You have a secure database connection string and wallet or SSL configuration directory.
- You have OCI Generative AI access in a supported region.
- You have created the identity-provider apps, users, groups or roles, and OAuth scopes.
- You will replace all masked values and placeholders in the source files before runtime testing.

## Task 1: Download and Inspect the Demo Package

1. Create a working directory.

    ```bash
    <copy>
    mkdir -p "$HOME/deepsec-langchain"
    cd "$HOME/deepsec-langchain"
    </copy>
    ```

2. Place the demo archive in the working directory.

    The archive for this lab is:

    ```text
    deepsec-demos-tanisha-langchain-poc-demo.zip
    ```

    In this repository, the archive sits next to this markdown file.

3. Extract the archive.

    ```bash
    <copy>
    unzip -o deepsec-demos-tanisha-langchain-poc-demo.zip
    cd deepsec-demos-tanisha-langchain-poc-demo
    </copy>
    ```

4. Review the two application variants.

    ```bash
    <copy>
    find python-langchain-oci python-langchain-msei -maxdepth 1 -type f | sort
    </copy>
    ```

    Important files include:

    | File | Purpose |
    | --- | --- |
    | `README.md` | Source setup notes for the variant. |
    | `.env.example` | Environment variables for database and identity-provider settings. |
    | `setup.sql` | Database setup for sample data, data roles, and data grants. |
    | `get_user_token.py` | Token acquisition helper for the selected identity provider. |
    | `db_conn.py` or `db_connection.py` | Oracle Database connection and end-user token flow. |
    | `langchain_app.py` | Interactive HR assistant entry point. |
    | `langchain_tools.py` | LangChain database tools and system prompt rules. |

## Task 2: Choose the Identity-Provider Path

1. Use the OCI IAM path when your users and OAuth apps live in OCI IAM.

    ```bash
    <copy>
    cd "$HOME/deepsec-langchain/deepsec-demos-tanisha-langchain-poc-demo/python-langchain-oci"
    </copy>
    ```

    This path uses:

    - `oci_app_default_config.ini` for OCI IAM domains, apps, users, and scopes.
    - `get_user_token.py` to create user and mid-tier access-token files.
    - `db_conn.py` to propagate the selected user token into the Oracle Database session.

2. Use the Microsoft Entra ID path when your users and OAuth apps live in Microsoft Entra ID.

    ```bash
    <copy>
    cd "$HOME/deepsec-langchain/deepsec-demos-tanisha-langchain-poc-demo/python-langchain-msei"
    </copy>
    ```

    This path uses:

    - `.env` values for Entra tenant, client app, mid-tier app, and database scopes.
    - `get_user_token.py` with MSAL interactive authentication.
    - `db_connection.py` to propagate the Entra access token into the Oracle Database session.

3. Keep one terminal in the selected variant directory for the remaining tasks.

    ```bash
    <copy>
    pwd
    </copy>
    ```

## Task 3: Configure Python, OCI SDK, and OCI Generative AI

1. Create and activate a Python virtual environment.

    ```bash
    <copy>
    python3 -m venv .venv
    . .venv/bin/activate
    python -m pip install --upgrade pip
    </copy>
    ```

2. Install the demo dependencies.

    ```bash
    <copy>
    python -m pip install -r requirements.txt
    </copy>
    ```

3. Create or update the OCI SDK config file for OCI Generative AI.

    ```bash
    <copy>
    mkdir -p "$HOME/.oci"
    vi "$HOME/.oci/config"
    </copy>
    ```

    Use your own tenancy, user, fingerprint, key file, and region values.

    ```text
    [DEFAULT]
    user=<user_ocid>
    fingerprint=<fingerprint>
    key_file=/home/<username>/.oci/oci_api_key.pem
    tenancy=<tenancy_ocid>
    region=<oci_region>
    ```

4. Copy the environment template and replace the placeholders.

    ```bash
    <copy>
    cp .env.example .env
    vi .env
    </copy>
    ```

    Set the database user, password, DSN, wallet or SSL directory, and identity-provider values.

5. Update `app_config.py` with OCI Generative AI values.

    ```bash
    <copy>
    vi app_config.py
    </copy>
    ```

    Confirm these values are real Python strings:

    ```python
    MODEL_IDS = {
        "default": "<model_id>"
    }

    oci_config_file = "/home/<username>/.oci/config"
    oci_profile = "DEFAULT"
    compartment_id = "<compartment_ocid>"
    model_choice = "default"
    ```

    For Microsoft Entra ID, confirm that `app_config.py` imports `dataclass`. Also replace unquoted placeholder values before you run it.

## Task 4: Configure Database Objects and Deep Data Security

1. Open the setup script for your selected variant.

    ```bash
    <copy>
    vi setup.sql
    </copy>
    ```

2. Replace the database connection placeholders.

    ```sql
    define passwd=<sys_password>
    define db_usr_passwd=<application_database_password>
    define conn_str=<database_connection_string>
    ```

3. Review the HR sample data changes.

    The OCI IAM variant updates `HR.EMPLOYEES` and creates `HR.MANAGERS`. The Microsoft Entra ID variant creates `HR.EMPLOYEE_RECORDS` and `HR.MANAGER_RECORDS`.

4. Replace the identity-provider mapping values.

    For OCI IAM, confirm the data-role mappings use your OCI IAM group names:

    ```sql
    create or replace data role employee_role mapped to
    'iam_oauth_group=Employee';

    create or replace data role manager_role mapped to
    'iam_oauth_group=Manager';
    ```

    For Microsoft Entra ID, confirm the data-role mappings use your Entra role values:

    ```sql
    create or replace data role EMPLOYEE_FS_ROLE mapped to
    'azure_role=<employee_role>';

    create or replace data role MANAGER_FS_ROLE mapped to
    'azure_role=<manager_role>';
    ```

5. Replace the identity-provider configuration values.

    For OCI IAM, update `IDENTITY_PROVIDER_OAUTH_CONFIG` and `OCI_IAM_DOMAIN_DB_CRED$`. Use your database app ID, domain URL, client ID, and client secret.

    For Microsoft Entra ID, add the identity-provider configuration for your database and Entra application setup.

6. Run the setup script from SQL*Plus.

    ```bash
    <copy>
    sqlplus sys/<sys_password>@<database_connection_string> as sysdba
    </copy>
    ```

    ```sql
    <copy>
    @setup.sql
    </copy>
    ```

7. Confirm that the setup completed without errors.

    ```sql
    <copy>
    show errors
    select role_name from dba_data_roles order by role_name;
    select object_name from dba_objects where owner = 'HR' order by object_name;
    </copy>
    ```

## Task 5: Generate or Acquire End-User Tokens

1. For OCI IAM, update `oci_app_default_config.ini`.

    ```bash
    <copy>
    vi oci_app_default_config.ini
    </copy>
    ```

    Replace the domain URL, token URL, database app ID, client IDs, client secrets, scopes, usernames, and passwords.

2. Generate OCI IAM token files.

    ```bash
    <copy>
    python get_user_token.py oci_app_default_config.ini
    find tokens -type f | sort
    </copy>
    ```

3. Update the OCI IAM token paths in `db_conn.py`.

    ```bash
    <copy>
    vi db_conn.py
    </copy>
    ```

    Set `TOKEN_PATHS` to the files for the users you will test.

    ```python
    TOKEN_PATHS = {
        "marvin": "tokens/iam_domain_default/MarvinGreenberg_token",
        "emma": "tokens/iam_domain_default/EmmaBaker_token",
    }
    ```

4. For Microsoft Entra ID, confirm `.env` contains the public client, tenant, mid-tier app, and database scope values.

    ```bash
    <copy>
    grep -E 'AZURE_|DB_CLIENT|DB_AUTHORITY|DB_SCOPES' .env
    </copy>
    ```

    The Entra variant uses interactive MSAL authentication when the application starts.

## Task 6: Run the LangChain HR Assistant

1. Start the OCI IAM variant as the employee user.

    ```bash
    <copy>
    python langchain_app.py emma
    </copy>
    ```

2. Ask an employee-scoped question.

    ```text
    Show employee salaries that are visible to me
    ```

3. Exit the application.

    ```text
    exit
    ```

4. Start the OCI IAM variant as the manager user.

    ```bash
    <copy>
    python langchain_app.py marvin
    </copy>
    ```

5. Ask the same question.

    ```text
    Show employee salaries that are visible to me
    ```

6. For Microsoft Entra ID, start the app and complete the browser-based sign-in prompt.

    ```bash
    <copy>
    python langchain_app.py
    </copy>
    ```

    Sign in as the user you want to test. Then run the same natural-language prompts.

## Task 7: Validate Deep Data Security Behavior

1. Confirm the application reports the authenticated database end user.

    The application calls:

    ```sql
    select ORA_END_USER_CONTEXT.username from sys.dual
    ```

    The returned value should match the propagated identity-provider user.

2. Compare employee and manager results.

    Expected behavior:

    | User type | Expected result |
    | --- | --- |
    | Employee | The user can see only HR data allowed by the employee data grants. |
    | Manager | The user can see HR rows in the manager hierarchy. Restricted columns stay hidden where configured. |

3. Confirm that the application tools are read-only.

    The LangChain prompt instructs the model to inspect the schema first and use SELECT queries. Do not treat this prompt as the security boundary. Deep Data Security and database privileges enforce access.

4. If the application returns no data, check the identity mapping first.

    Verify:

    - The user token belongs to the expected identity-provider user.
    - The identity-provider group or role names match the data role mappings.
    - The HR sample data email or username values match `ORA_END_USER_CONTEXT.USERNAME`.
    - The database user has `CREATE END USER SECURITY CONTEXT` only where the app flow requires it.
    - The wallet, DSN, and SSL settings point at the configured database.

## Task 8: Clean Up or Reset the Lab

1. Stop the application.

    ```text
    exit
    ```

2. Remove local token files if you no longer need them.

    ```bash
    <copy>
    rm -rf tokens
    </copy>
    ```

3. Remove the Python virtual environment if this was a temporary workspace.

    ```bash
    <copy>
    deactivate 2>/dev/null || true
    rm -rf .venv
    </copy>
    ```

4. Ask your database or identity administrator before dropping users, data roles, data grants, identity-provider settings, or identity apps.

    Cleanup is environment-specific because the setup scripts use tenant-specific applications, users, groups, roles, credentials, and HR sample data.

## Next Steps

You may now proceed to the next lab.

## Learn More

- [Oracle Database Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/)
- [OCI Generative AI documentation](https://docs.oracle.com/en-us/iaas/Content/generative-ai/home.htm)
- [OCI SDK configuration file documentation](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/sdkconfig.htm)
- [Microsoft Authentication Library for Python](https://learn.microsoft.com/en-us/entra/msal/python/)

## Acknowledgements

- **Author** - Richard Evans, Database Security
- **Source Contributor** - Tanisha Garg, Oracle
- **Last Updated By/Date** - Richard Evans, June 2026
