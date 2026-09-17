# Select AI Agent Team + Deep Data Security HR Demo

This is an interactive Python CLI that answers HR questions through an Oracle Select AI
Agent Team while enforcing the signed-in OCI IAM user's Oracle Deep Data
Security (Deep Sec) access. It is a reference implementation for authenticated
NL-to-SQL, not a general-purpose database gateway.

## Architecture and request flow

```text
OCI IAM browser sign-in
        │ Authorization Code access token
        ▼
Python CLI ── set_end_user_identity() ──► python-oracledb
                                               │ database Client Credentials token
                                               ▼
                               ADB token-attached Deep Sec session
                                               │
                           SET_PROFILE / SET_TEAM
                                               │
                                               ▼
                     DBMS_CLOUD_AI_AGENT.RUN_TEAM
                       (directly in that session)
                                               │
                       SQL Tool ──────────────┴──► DBMS_CLOUD_AI.GENERATE
                                                          │
                                                          ▼
                                           Select AI profile → OCI Generative AI

The SQL Tool executes generated SQL with the signed-in user's Deep Sec
roles, row filters, and column grants.
```

The app attaches the user access token using
`oracledb.plugins.end_user_sec_provider.set_end_user_identity()` immediately
before acquiring every pooled connection. It calls `RUN_TEAM` directly on that
same token-attached connection. This is what preserves the end-user context through the SQL Tool.

## Authorization model

The profile and Team are owned by the application schema (`DB_USR` in this
demo). Signed-in users inherit a standard runner role via their Deep Sec data
role:

```text
OCI IAM group
  └─► Deep Sec data role (HRAPP_EMPLOYEES or HRAPP_MANAGERS)
        └─► HR_SELECT_AI_RUNNER
              ├─ EXECUTE DBMS_CLOUD_AI
              ├─ EXECUTE DBMS_CLOUD_AI_AGENT
              ├─ EXECUTE on DB_USR.GENAI_CRED
              ├─ profile access: DB_USR.HR_PROFILE
              └─ team access:    DB_USR.HR_TEAM
```

The SQL Tool runs as the signed-in user. An unqualified credential called
`GENAI_CRED` would be looked up as, for example, `EMMA.GENAI_CRED`.
The setup therefore grants the runner role access to `DB_USR.GENAI_CRED` and
creates the public synonym `HR_GENAI_CRED`. The profile references this
synonym. The synonym is only a name: the private key remains stored in the
database credential object and access still requires `EXECUTE`.

Deep Sec data grants are the security boundary. The sample policy allows:

- Employees to view directory data for everyone, and salary/SSN only on their
  own employee row.
- Managers to view their reporting hierarchy, excluding SSNs.
- Employees to view their own feedback, and managers to view notes for their
  reporting hierarchy.

## Prerequisites

- Autonomous AI Database with Select AI and OCI IAM external authentication
  configured.
- OCI IAM employee and manager groups, with users assigned to the groups.
- Two OCI IAM confidential applications:
  - Browser login: Authorization Code grant and an exact redirect URI, such as
    `http://localhost:8888/callback`.
  - Database access: Client Credentials grant and a scope accepted by the ADB
    Deep Sec configuration.
- A GenAI user permitted to use the selected model in its GenAI compartment,
  with an unencrypted OCI API signing key.
- An extracted ADB wallet, SQLcl or SQL*Plus, and Python 3.10+.

OCI IAM application setup, database identity-provider setup, group membership,
and GenAI tenancy policies are environment-specific and are not created by the
scripts in this repository.

## Setup from a fresh demo database

### 1. Build sample HR data and Deep Sec roles as `ADMIN`

[setup_demo_database.sql](setup_demo_database.sql) is destructive: it drops
and recreates the `HR` schema. Use a disposable database. Before running it,
edit its `DEFINE` values for the application password, IAM usernames, IAM
group names, and (if desired) the runner-role name.

```bash
export WALLET_DIR="$HOME/adb_wallet/<extracted-wallet-directory>"
export TNS_ADMIN="$WALLET_DIR"
export ADB_SERVICE="<wallet-tns-alias>"

sql "admin@$ADB_SERVICE"
```

```sql
@/absolute/path/to/deepsec-demos-select-ai-oci-demo/setup_demo_database.sql
```

This creates `DB_USR`, sample HR data, Deep Sec data roles and grants, and
`HR_SELECT_AI_RUNNER` with the required package privileges.

### 2. Create the GenAI credential as `DB_USR`

```bash
sql "db_usr@$ADB_SERVICE"
```

Paste the complete **unencrypted** private key only into your SQL terminal.
Never save it in `.env`, copy it to the VM, or commit it.

```sql
SET DEFINE OFF

DECLARE
  l_private_key CLOB := q'~
-----BEGIN PRIVATE KEY-----
<paste the complete unencrypted private key>
-----END PRIVATE KEY-----
~';
BEGIN
  DBMS_CLOUD.CREATE_CREDENTIAL(
    credential_name => 'GENAI_CRED',
    user_ocid       => '<GENAI_USER_OCID>',
    tenancy_ocid    => '<GENAI_TENANCY_OCID>',
    private_key     => l_private_key,
    fingerprint     => '<GENAI_API_KEY_FINGERPRINT>'
  );
END;
/
```

### 3. Share the credential as `ADMIN`

Reconnect as `ADMIN`, then run
[setup_select_ai_access.sql](setup_select_ai_access.sql). It grants the
runner role `EXECUTE` on the credential and creates the `HR_GENAI_CRED`
public synonym used by the profile.

```sql
DEFINE PROFILE_OWNER = DB_USR
DEFINE CREDENTIAL_NAME = GENAI_CRED
DEFINE CREDENTIAL_SYNONYM = HR_GENAI_CRED
DEFINE RUNNER_ROLE = HR_SELECT_AI_RUNNER

@/absolute/path/to/deepsec-demos-select-ai-oci-demo/setup_select_ai_access.sql
```

### 4. Create the Select AI profile as `DB_USR`

Reconnect as `DB_USR`. Use `HR_GENAI_CRED`, not `GENAI_CRED`, for the
`credential_name` attribute.

```sql
BEGIN
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'HR_PROFILE',
    attributes => '{
      "provider": "oci",
      "credential_name": "HR_GENAI_CRED",
      "model": "<MODEL_ID>",
      "oci_compartment_id": "<GENAI_COMPARTMENT_OCID>",
      "region": "<OCI_GENAI_REGION>",
      "object_list": [
        {"owner": "HR", "name": "EMPLOYEES"},
        {"owner": "HR", "name": "DEPARTMENTS"},
        {"owner": "HR", "name": "LOCATIONS"},
        {"owner": "HR", "name": "PERFORMANCE_NOTES"}
      ],
      "enforce_object_list": true,
      "temperature": 0,
      "max_tokens": 8192
    }',
    status => 'ENABLED',
    description => 'HR Select AI profile'
  );
END;
/
```

The GenAI tenancy can differ from the ADB tenancy when the stored credential
belongs to a GenAI user authorized in that tenancy.

### 5. Create and share the Tool, Agent, Task, and Team as `DB_USR`

Run [setup_select_ai.sql](setup_select_ai.sql). It recreates the named SQL
Tool, Agent, Task, and Team, then grants the profile and Team to the runner
role.

```sql
DEFINE PROFILE_OWNER = DB_USR
DEFINE PROFILE_NAME = HR_PROFILE
DEFINE AGENT_NAME = HR_AGENT
DEFINE TASK_NAME = HR_TASK
DEFINE TEAM_NAME = HR_TEAM
DEFINE SQL_TOOL_NAME = HR_SQL_TOOL
DEFINE RUNNER_ROLE = HR_SELECT_AI_RUNNER

@/absolute/path/to/deepsec-demos-select-ai-oci-demo/setup_select_ai.sql
```

The script reports all four objects as `ENABLED`.

### 6. Configure and run the CLI

```bash
cd /path/to/deepsec-demos-select-ai-oci-demo
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
cp .env.example .env
chmod 600 .env
```

Populate every value in `.env`:

```dotenv
# ADB wallet connection
DB_USER=db_usr
DB_PASSWORD=<db_usr_password>
DB_DSN=<wallet-tns-alias>
SSL_CONFIG_DIR=/absolute/path/to/extracted/wallet
WALLET_PWD=<wallet-password-if-required>

# Optional PEM bundle for enterprise TLS inspection
TLS_CA_BUNDLE=

# OCI IAM browser-login client: Authorization Code grant
OCI_DOMAIN_URL=https://idcs-<domain>.identity.oraclecloud.com:443
APP_CLIENT_ID=<browser-login-client-id>
APP_CLIENT_SECRET=<browser-login-client-secret>
APP_SCOPE=<browser-login-scope>
REDIRECT_URI=http://localhost:8888/callback

# OCI IAM database client: Client Credentials / Deep Sec
DB_CLIENT_ID=<database-client-id>
DB_CLIENT_SECRET=<database-client-secret>
DB_SCOPE=<database-access-scope>

# Select AI objects
SELECT_AI_PROFILE_OWNER=db_usr
SELECT_AI_PROFILE_NAME=HR_PROFILE
SELECT_AI_TEAM_OWNER=db_usr
SELECT_AI_TEAM_NAME=HR_TEAM
```

```bash
python select_ai_agent_app.py
```

Open the printed URL, authenticate, then paste the complete redirect URL into
the terminal. A browser failure connecting to `localhost` after a successful
sign-in is expected: the CLI reads the authorization code from that URL and
does not run a callback server.

Example prompts:

```text
who am i
show my employee information including my ssn
show all employee records
show my team's performance notes
```

## Existing database: minimum required changes

If your Deep Sec data roles already exist, run this as `ADMIN` before the
credential, profile, and Team steps:

```sql
CREATE ROLE HR_SELECT_AI_RUNNER;

GRANT EXECUTE ON DBMS_CLOUD_AI TO DB_USR;
GRANT EXECUTE ON DBMS_CLOUD_AI_AGENT TO DB_USR;
GRANT EXECUTE ON DBMS_CLOUD_AI TO HR_SELECT_AI_RUNNER;
GRANT EXECUTE ON DBMS_CLOUD_AI_AGENT TO HR_SELECT_AI_RUNNER;

GRANT HR_SELECT_AI_RUNNER TO HRAPP_EMPLOYEES;
GRANT HR_SELECT_AI_RUNNER TO HRAPP_MANAGERS;
```

If the runner role already exists, omit `CREATE ROLE`. Then perform steps
2–5, including [setup_select_ai_access.sql](setup_select_ai_access.sql). Do
not give `DB_USR` broad HR `SELECT` privileges and do not wrap `RUN_TEAM`
in a definer-rights function.

## Repository contents

| File | Purpose |
| --- | --- |
| [setup_demo_database.sql](setup_demo_database.sql) | Destructive `ADMIN` setup for sample HR data, Deep Sec roles/data grants, and base privileges. |
| [setup_select_ai_access.sql](setup_select_ai_access.sql) | `ADMIN` script that shares the GenAI credential with token-authenticated users. |
| [setup_select_ai.sql](setup_select_ai.sql) | `DB_USR` script that creates the SQL Tool, Agent, Task, Team, and profile/team grants. |
| [select_ai_agent_app.py](select_ai_agent_app.py) | CLI that authenticates the user, attaches identity, and calls `RUN_TEAM`. |
| [db_connection.py](db_connection.py) | Wallet pool configured with the OCI-token Deep Sec provider. |
| [get_user_token.py](get_user_token.py) | Browser Authorization Code flow and verified token exchange. |
| [app_config.py](app_config.py) | Environment-backed configuration. |
| [.env.example](.env.example) | Runtime configuration template without secrets. |

## Troubleshooting

| Symptom | Resolution |
| --- | --- |
| `invalid_redirect_uri` | Add the exact `REDIRECT_URI` to the browser-login application's allowed redirect URIs. |
| `Profile "DB_USR"."HR_PROFILE" does not exist` | Check the owner with `SELECT owner, profile_name FROM dba_cloud_ai_profiles WHERE profile_name = 'HR_PROFILE';`, correct `SELECT_AI_PROFILE_OWNER`, then rerun the profile access grant. |
| `Credential "emma"."GENAI_CRED" does not exist` | Run `setup_select_ai_access.sql` as `ADMIN`, then set the profile's `credential_name` to `HR_GENAI_CRED`. |
| `PLS-00201: DBMS_CLOUD_AI_AGENT must be declared` | Confirm the runner role has `EXECUTE` on the package and is granted to the appropriate Deep Sec data role. |
| `Invalid task - ["query"]` | Re-run `setup_select_ai.sql`; it deliberately omits unsupported `input: ["query"]`. |
| Sensitive data is omitted from a broad answer | Ask explicitly for the signed-in user's field; the model may choose not to select sensitive columns for a broad request. |
| No HR rows or columns are visible | Verify IAM group membership, token username ↔ `HR.EMPLOYEES.USER_NAME` mapping, and Deep Sec data grants. Do not add broad HR `SELECT` grants. |
| `CERTIFICATE_VERIFY_FAILED` | Ensure `certifi` is installed. With corporate TLS inspection, set `TLS_CA_BUNDLE` to the enterprise CA PEM bundle. |
| `ImportError: libffi.so.8` | Install the `libffi` package matching the VM's Python runtime, or use the OS-supported Python distribution. |

## Security notes

- Authorization codes are single-use. Restart the CLI and authenticate again
  after a failed token exchange.
- Deep Sec data grants and least-privilege database roles are authoritative;
  Agent instructions are not an authorization boundary.
