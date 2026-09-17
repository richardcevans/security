# LangChain Agent HR Application on OCI

## Overview

This sample shows a LangChain HR assistant over Oracle Autonomous AI Database using Oracle Deep Data Security. The Python app authenticates an OCI IAM end user, propagates that end-user identity to the database through the Oracle Python driver end-user security provider, and lets database data roles/data grants enforce row and column visibility.

The setup scripts in `adb-oci-iam` create the demo OCI IAM applications, groups, users, HR schema, data roles, and generated environment files. By default they also create an Autonomous AI Database and download its wallet. If you already have an Autonomous AI Database, you can provide its connect string and wallet directory instead. Users should not need to manually create OCI IAM applications or manually configure database identity-provider settings for this sample.

The Python app creates one Oracle Database connection pool at startup, sets the authenticated OCI IAM end-user identity before each pooled connection is acquired, and passes those connections to the LangChain tools. The pool uses the confidential HR midtier app credentials for database access and the login client app only for the end-user browser login flow.

The Oracle Python driver end-user security provider is the bridge between the OCI IAM login token and the database session. In the source, the login flow and `set_end_user_identity(...)` call live in `langchain_app.py`, while the pool configuration lives in `db_connection.py`. The condensed flow looks like this:

```python
import oracledb.plugins.end_user_sec_provider as deepsec_provider

end_user_identity = get_access_token(
    domain_url=OCI_DOMAIN_URL,
    client_id=HR_LOGIN_CLIENT_ID,
    client_secret=HR_LOGIN_CLIENT_SECRET,
    scope=HR_MIDTIER_SCOPE,
    redirect_uri=HR_REDIRECT_URI,
)

pool = oracledb.create_pool(
    min=int(os.getenv("DB_POOL_MIN", "1")),
    max=int(os.getenv("DB_POOL_MAX", "4")),
    increment=int(os.getenv("DB_POOL_INCREMENT", "1")),
    user=APP_DB_USER,
    password=APP_DB_PASSWORD,
    dsn=ADB_SERVICE,
    ssl_server_dn_match=False,
    config_dir=WALLET_DIR,
    wallet_location=WALLET_DIR,
    wallet_password=WALLET_PWD,
    extra_auth_params={
        "end_user_sec_params": {
            "spi_type": "oci_tokens",
            "auth_flow": "client_credentials",
            "client_id": HR_MIDTIER_CLIENT_ID,
            "client_credential": HR_MIDTIER_CLIENT_SECRET,
            "authority": OCI_DOMAIN_URL.rstrip("/") + "/oauth2/v1/token",
            "scopes": HR_DB_SCOPE,
        }
    },
)

deepsec_provider.set_end_user_identity(end_user_identity)
with pool.acquire() as connection:
    # LangChain tools query through this pooled connection.
    ...
```

The CLI also includes a lightweight working-memory harness in `langchain_app.py`. It keeps recent conversation turns, summarizes older context, and tracks simple request details such as row limits and sort preferences. This helps the demo feel conversational, but it is not required for the database security model or the LangChain tools to function.

## Architecture

The setup creates three OCI IAM applications:

| Application | Purpose |
| --- | --- |
| Database resource app | Represents Autonomous AI Database as an OAuth resource and exposes the database-access scope used by the Oracle driver. |
| HR midtier app | Confidential app and OAuth resource server for the LangChain HR agent. It exposes the agent-access scope, is configured for application-mediated database access, and has EMPLOYEES and MANAGERS assigned to it. |
| Login client app | Confidential OAuth client used by the Python CLI to perform the browser authorization-code login flow. It requests the HR midtier agent-access scope and is not configured as a resource server. |

The setup also creates or reuses OCI IAM groups and demo users:

| Demo user | Groups |
| --- | --- |
| `marvin` | EMPLOYEES, MANAGERS |
| `emma` | EMPLOYEES |

## Prerequisites

- OCI Cloud Shell, or Bash 4.x with OCI CLI, Python 3, SQL*Plus, and unzip.
- An OCI CLI profile that can create Identity Domain apps, groups, and users. The default database-create mode also requires permission to create Autonomous AI Database and generate wallet files in the target compartment.
- An OCI configuration file and key files under your home directory, for example `~/.oci/config` and the private key referenced by that config. The setup scripts and Python app read this profile unless you override `OCI_CONFIG_FILE` and `OCI_PROFILE`.
- An OCI IAM identity domain where the demo users and groups can be created or reused.
- Autonomous AI Database 26ai. The setup script can create one, or you can provide an existing database connect string and unzipped wallet directory.
- OCI Generative AI chat quota in the OCI region selected by the OCI profile if you want the LangChain agent to answer questions. The database/IAM setup can still be verified without GenAI quota.
- If the tenancy enforces mandatory tags on IAM resources, the required tag value to apply to created Identity Domain resources.

### Troubleshooting OCI Authentication

The default lab path assumes the OCI SDK and OCI CLI can authenticate from `~/.oci/config`, usually with the `[DEFAULT]` profile. This is especially relevant when running from Bash with OCI CLI instead of OCI Cloud Shell.

If you use a different OCI CLI profile, export it before running the setup scripts or the app:

```bash
export OCI_PROFILE="<profile-name>"
export OCI_CLI_PROFILE="<profile-name>"
```

If your environment uses OCI CLI session-token authentication instead of an API key, re-authenticate first:

```bash
oci session authenticate --region "<region>" --profile-name "<profile-name>"
```

Then export the matching auth settings:

```bash
export OCI_PROFILE="<profile-name>"
export OCI_CLI_PROFILE="<profile-name>"
export OCI_CLI_AUTH="security_token"
export OCI_AUTH_TYPE="SECURITY_TOKEN"
```

If your OCI config is not in the default location, set:

```bash
export OCI_CONFIG_FILE="/path/to/config"
```

Session-token authentication expires. If OCI CLI commands start returning `NotAuthenticated`, run `oci session authenticate` again.

## Repository Layout

```text
langchain-agent-oci/
  app_config.py
  db_connection.py
  get_user_token.py
  langchain_app.py
  langchain_tools.py
  requirements.txt
  adb-oci-iam/
    00_setup_adb.sh
    01_enable_oci_iam.sh
    02_create_hr_schema.sh
    03_create_data_roles_and_grants.sh
    verify_db_setup.sh
    set_oci_iam_passwords.sh
    04_get_iam_oauth_token.sh
    05_verify_as_marvin.sh
    06_verify_as_emma.sh
    07_cleanup_adb_lab.sh
```

## Setup

Run these commands from OCI Cloud Shell after uploading or cloning this folder:

```bash
cd langchain-agent-oci/adb-oci-iam
./00_setup_adb.sh
source ./.adb-oci-iam.env
./set_oci_iam_passwords.sh --all
./01_enable_oci_iam.sh
./02_create_hr_schema.sh
./03_create_data_roles_and_grants.sh
./verify_db_setup.sh
```

If your tenancy requires defined tags on Identity Domain resources, export the tag payload before running `00_setup_adb.sh`. For example:

```bash
export OCI_IAM_OCITAGS_JSON='{"definedTags":[{"namespace":"<namespace>","key":"<key>","value":"<value>"}]}'
./00_setup_adb.sh
```

Use a namespace, key, and value allowed by your tenancy's tag definition. If the OCI Console displays a friendly tag name with extra text, use the API tag key name in `OCI_IAM_OCITAGS_JSON`.

### Use An Existing ADB

If you already have an Autonomous AI Database 26ai and want the lab to skip database creation, download and unzip that database wallet, then set these values before `00_setup_adb.sh`:

```bash
export EXISTING_DB_DSN='<tnsnames alias or full connect string>'
export WALLET_DIR='<path to unzipped wallet directory>'
export WALLET_PWD='<wallet password>'
export ADMIN_PWD='<ADMIN password for the existing database>'
./00_setup_adb.sh
```

For example:

```bash
export EXISTING_DB_DSN='myadb_low'
export WALLET_DIR="$HOME/adb_wallet/myadb"
export WALLET_PWD='...'
export ADMIN_PWD='...'
export OCI_IAM_OCITAGS_JSON='{"definedTags":[{"namespace":"<namespace>","key":"<key>","value":"<value>"}]}'
./00_setup_adb.sh
```

In this mode, `00_setup_adb.sh` still creates/reuses the OCI IAM apps, groups, demo users, scopes, grants, and generated env files, but it does not call `oci db autonomous-database create` or `generate-wallet`.

`00_setup_adb.sh` writes two generated files:

| File | Purpose |
| --- | --- |
| `adb-oci-iam/.adb-oci-iam.env` | Environment for the numbered setup and verification scripts. |
| `.env` | Environment for `langchain_app.py`. |

The generated values include database connection settings, wallet location/password, OCI IAM domain URL, OAuth app IDs/secrets/scopes, OCI profile, compartment, OCI Generative AI endpoint, and a best-effort discovered `MODEL_ID`.

For OCI on-demand models, `MODEL_ID` should be the model name used by the inference API, such as `meta.llama-4-scout-17b-16e-instruct`, not the model OCID from the model catalog. If `MODEL_ID` is blank in `.env`, the tenancy or selected region did not expose a chat model to the setup script. Request OCI Generative AI quota or set `MODEL_ID` and, when useful, `MODEL_PROVIDER` to a chat model available in the same region as `OCI_GENAI_SERVICE_ENDPOINT`.

## Optional SQL*Plus Verification

The numbered scripts include the original direct SQL*Plus verification flow. To test Marvin:

```bash
cd langchain-agent-oci/adb-oci-iam
source ./.adb-oci-iam.env
./04_get_iam_oauth_token.sh --headless
./05_verify_as_marvin.sh
```

To test Emma:

```bash
./04_get_iam_oauth_token.sh --headless
./06_verify_as_emma.sh
```

## Python Dependencies

From the repository root:

```bash
python3 -m pip install --user -r requirements.txt
```

If you use Python 3.12 specifically, install with that interpreter:

```bash
python3.12 -m ensurepip --user
python3.12 -m pip install --user -r requirements.txt
```

## Running The App

From the repository root:

```bash
source adb-oci-iam/.adb-oci-iam.env
python3 langchain_app.py
```

The app opens or prints an OCI IAM login URL. Use a private browser window or separate browser profile for demo-user login, sign in as `marvin` or `emma`, and then paste the final callback URL into the terminal. The final `localhost:8888/callback?...` page may fail to load when the app runs in Cloud Shell or on a remote VM; copy the full callback URL from the browser address bar back into the terminal.

If you installed dependencies with Python 3.12:

```bash
source adb-oci-iam/.adb-oci-iam.env
python3.12 langchain_app.py
```

Runtime diagnostics are written to:

```text
langchain_demo.log
```

Read the most recent errors with:

```bash
tail -n 120 langchain_demo.log
```

### Usage Examples

Deep Data Security controls what the agent can retrieve from the database based on the authenticated OCI IAM user. Marvin is a manager, so he can see salary information for employees who report to him:

```text
Oracle HR Agent
────────────────────────────────────────
Authenticated as: marvin
Type 'exit' to quit

> Q: Who reports to me?
Working...

A:
Here are your direct reports:

EMPLOYEE_ID | FIRST_NAME | LAST_NAME | USER_NAME | JOB_CODE | MANAGER_ID | DEPARTMENT_ID | SALARY
3 | Emma | Baker | emma | SWE2 | 2 | 1 | 120000.0
4 | Charlie | Davis | charlie | SWE1 | 2 | 1 | 95000.0
5 | Dana | Lee | dana | SWE3 | 2 | 1 | 130000.0
```

Emma is an employee, so she only has access to her own salary information:

```text
Oracle HR Agent
────────────────────────────────────────
Authenticated as: emma
Type 'exit' to quit

> Q: What is the average salary in department 1?
Working...

A:
The average salary in department 1 is 120000.
```

## Configuration

Application variables normally do not have to be set manually. `00_setup_adb.sh` writes the required values into `.adb-oci-iam.env` and `.env`.

Useful overrides before running `00_setup_adb.sh`:

| Variable | Purpose |
| --- | --- |
| `OCI_COMPARTMENT` or `ROOT_COMP_ID` | Target compartment name/OCID. Defaults to root tenancy compartment. |
| `OCI_DOMAIN_URL` | Identity Domain URL when domain discovery is not permitted. |
| `DB_NAME` | Autonomous Database name. Defaults to a unique `deepsec1...` name. |
| `EXISTING_DB_DSN` | Use an existing ADB connect string and skip ADB create/wallet download. |
| `WALLET_DIR` | Wallet directory. In existing-DB mode, this must already contain the unzipped wallet. |
| `WALLET_PWD` | Wallet password used by SQL*Plus and the Python driver. |
| `CREATE_DEMO_USERS=0` | Reuse existing users instead of creating Marvin and Emma. |
| `APP_DB_USER` / `APP_DB_PASSWORD` | Database connection-pool user used by the Python app. |
| `MODEL_ID` | OCI Generative AI chat model name when automatic discovery is not possible. |
| `MODEL_PROVIDER` | Optional provider hint for `MODEL_ID`, such as `meta`, `cohere`, or `google`. |
| `OCI_GENAI_REGION` | Region for OCI Generative AI. Defaults to the OCI CLI profile region or tenancy home region. |
| `OCI_IAM_OCITAGS_JSON` | OCI tags payload applied to created Identity Domain resources when the tenancy requires tags. |

Optional runtime-only pool sizing overrides before running `langchain_app.py`:

| Variable | Purpose |
| --- | --- |
| `DB_POOL_MIN` | Minimum number of pooled database connections. Defaults to `1`. |
| `DB_POOL_MAX` | Maximum number of pooled database connections. Defaults to `4`. |
| `DB_POOL_INCREMENT` | Number of connections added when the pool grows. Defaults to `1`. |

## Cleanup

Database-object cleanup only:

```bash
cd langchain-agent-oci/adb-oci-iam
source ./.adb-oci-iam.env
./07_cleanup_adb_lab.sh --delete-db-objects
```

Full lab cleanup, including lab-created ADB, IAM apps, demo users/groups, wallet, generated env files, and OAuth token cache:

```bash
./07_cleanup_adb_lab.sh --remove-all
```

The cleanup script prompts for confirmation before destructive actions unless `--force` is supplied.
If `00_setup_adb.sh` was run with `EXISTING_DB_DSN`, cleanup skips Autonomous Database deletion because the database was not created by this lab.

## Notes

- The app has no hardcoded tenancy, compartment, database, or OCI IAM app IDs.
- OCI Generative AI endpoint and compartment are generated from the setup context.
- Deep Data Security enforces all row and column visibility; the LangChain tools do not bypass database policy.
- Run this sample only in an isolated demo, sandbox, or non-production tenancy/domain.
