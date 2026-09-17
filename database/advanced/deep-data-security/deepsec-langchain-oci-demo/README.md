# LangChain OCI IAM HR and Compensation Agents

This command-line LangChain sample uses OCI IAM for user sign-in and Oracle Deep Data Security in Oracle Autonomous AI Database (ADB) to enforce the database policy for every tool call.

| Agent | Purpose |
| --- | --- |
| HR Agent | Lets an employee or manager use the HR data that their Deep Data Security policy permits. |
| Compensation Analytics Agent | Provides aggregate compensation analysis only. Its application identity, not the signed-in user, is granted the salary-analysis data role. |

The database is the security boundary. An agent only sees rows and columns returned by the database session that Deep Data Security creates.

## Authentication and authorization flow

    Browser sign-in as an OCI IAM user
            |
            | Authorization Code token for the selected agent scope
            v
    Python application
            |
            | Client Credentials database token for the agent's database client
            | + end-user token attached by python-oracledb
            v
    Oracle Autonomous AI Database
            |
            v
    Deep Data Security data roles and data grants

langchain_app.py obtains the end-user token once at startup. db_connection.py creates a python-oracledb connection pool with the OCI end-user-security provider. Before every pool acquisition, the application attaches the end-user token. Each LangChain tool therefore runs on a pooled connection carrying the authenticated user context.

## Repository layout

    langchain_app.py       CLI entry point and agent loop
    langchain_tools.py     HR and compensation tools
    db_connection.py       ADB connection pool and Deep Data Security provider setup
    get_user_token.py      OCI IAM authorization-code login helper
    app_config.py          Environment-backed application configuration
    requirements.txt       Python dependencies
    .env                   Local runtime configuration; never commit secrets
    setup.sql              Consolidated schema/policy setup; destructive against an existing ADB

## Prerequisites

- Python 3.12.
- An Autonomous AI Database with OCI IAM external authentication and Deep Data Security enabled.
- A database wallet extracted on the machine running the application.
- An OCI IAM identity domain containing the database, HR, compensation, and browser-login applications described below.
- An OCI API-key profile with permission to use OCI Generative AI in the chosen compartment.
- An OCI IAM user who is allowed to sign in to the applicable agent.

The application uses ChatOCIGenAI with API-key authentication. Configure the model OCID, compartment OCID, and Generative AI endpoint for your tenancy and region. The OCI user in the selected API-key profile must have the corresponding Generative AI policy.

## OCI IAM configuration

Configure these applications in the same OCI IAM identity domain. In the OCI Console, use Identity & Security → Domains → _domain_ → Integrated applications.

### 1. Database resource application

Create or reuse a confidential application for the database. Configure it as a resource server and create a database access scope such as DB_ACCESS_SCOPE. Record:

- the Application ID: database IAM registration (HR_DB_APP_ID and COMP_DB_APP_ID); and
- the scope's exact fully qualified scope (FQS): HR_DB_SCOPE and COMP_DB_SCOPE.

Both agents use the same database resource application and database scope.

### 2. HR Midtier application

Create or reuse a confidential application for the HR agent. It is a client of the database resource application and needs Client Credentials enabled. Allow the database access scope under its client configuration.

Record its OAuth Client ID and Client secret as:

    HR_DB_CLIENT_ID=<HR Midtier OAuth client ID>
    HR_DB_CLIENT_SECRET=<HR Midtier client secret>

This client obtains the HR agent's database-access token.

### 3. Compensation application

Create a confidential COMPENSATION_AGENT application. It has two purposes:

1. As a resource server, it exposes an access scope such as COMPENSATION_AGENT_ACCESS for a user signing in to the compensation agent.
2. As an OAuth client, it has Client Credentials enabled and is allowed to request the database resource application's database-access scope.

Record its OAuth client credentials as:

    COMP_DB_CLIENT_ID=<COMPENSATION_AGENT OAuth client ID>
    COMP_DB_CLIENT_SECRET=<COMPENSATION_AGENT client secret>

Its FQS access scope is used as COMP_APP_SCOPE.

### 4. Browser-login client

Create or reuse a confidential OAuth client used only for interactive browser login. Enable Authorization Code and register both callback URLs:

    http://localhost:8888/callback
    http://localhost:8889/callback

Under its client configuration, allow these resources/scopes:

- the HR agent access scope; and
- the compensation agent access scope.

Use this application's OAuth credentials for both HR_APP_CLIENT_* and COMP_APP_CLIENT_*. It is expected that those two pairs have the same values. They are intentionally different from HR_DB_CLIENT_* and COMP_DB_CLIENT_*.

### 5. Group-based authorization

Create or reuse OCI IAM groups with these names:

| Group | Database purpose |
| --- | --- |
| EMPLOYEES | Enables the employee data role. |
| MANAGERS | Enables the manager data role. |
| HR_REPS | Authorizes access to the compensation-agent scope. |

Assign each user to the applicable groups. For example, Hannah is an employee and HR representative when she belongs to EMPLOYEES and HR_REPS, and her username is mapped to an HR.EMPLOYEES.USER_NAME value.

On the compensation application, enable Enforce grants as authorization and grant the HR_REPS group access to the application. This prevents users outside the group from obtaining the compensation access scope.

No refresh token is required for this CLI sample: every run performs a new Authorization Code sign-in and does not persist a refresh token.

## Database policy

### HR data roles

The HR agent uses OCI IAM group mappings. setup.sql creates these data roles:

    CREATE OR REPLACE DATA ROLE hrapp_employees
      MAPPED TO 'IAM_OAUTH_GROUP=EMPLOYEES';

    CREATE OR REPLACE DATA ROLE hrapp_managers
      MAPPED TO 'IAM_OAUTH_GROUP=MANAGERS';

The end-user context maps the OCI IAM username to an HR employee:

    SELECT employee_id
    FROM hr.employees
    WHERE UPPER(user_name) = UPPER(ORA_END_USER_CONTEXT.username);

setup.sql also creates the HR policy: employees can access their own employee row, update their own phone number, and view public performance feedback. Managers can view their direct reports and private performance notes, and can create, update, or delete notes only for their direct reports. The precise rows and columns are controlled by the data grants in the database.

### Compensation application identity

Compensation access is tied to the application database token. The application identity must map to the COMPENSATION_AGENT OAuth Client ID—the value in COMP_DB_CLIENT_ID—not the browser-login client's ID.

    CREATE OR REPLACE APPLICATION IDENTITY compensation_app
      MAPPED TO 'IAM_OAUTH_CLIENT_ID=<COMP_DB_CLIENT_ID>';

    CREATE DATA ROLE IF NOT EXISTS salary_agent_fs_role;

    GRANT DATA ROLE salary_agent_fs_role TO compensation_app;

The compensation data role is read only. Its employee grant intentionally hides employee identity and direct contact fields while allowing compensation analysis:

    CREATE OR REPLACE DATA GRANT hr.sal_agent
      AS SELECT (
        ALL COLUMNS EXCEPT
          employee_id,
          first_name,
          last_name,
          user_name,
          phone_number,
          ssn
      )
      ON hr.employees
      WHERE 1 = 1
      TO salary_agent_fs_role;

    CREATE OR REPLACE DATA GRANT hr.sal_agent_departments
      AS SELECT ON hr.departments
      TO salary_agent_fs_role;

    CREATE OR REPLACE DATA GRANT hr.sal_agent_locations
      AS SELECT ON hr.locations
      TO salary_agent_fs_role;

The compensation agent exposes only aggregate salary tools and does not offer a generic SQL tool. The database grants remain the final enforcement point.

### HR change confirmation

The HR agent's generic `execute_sql` tool is read only and accepts `SELECT`
statements only. For a requested HR change, the agent first queries the target
record and then calls `propose_update`. The CLI displays the proposed change and
requires the user to reply exactly `yes`; replying `no` cancels it. Only the
confirmed statement is sent to the database.

The confirmed executor permits only `UPDATE` on `HR.EMPLOYEES` or
`HR.PERFORMANCE_NOTES`, plus `INSERT` and `DELETE` on
`HR.PERFORMANCE_NOTES`. It requires a `WHERE` clause for updates and deletes.
Deep Data Security remains the authoritative enforcement point for eligible
rows and columns.

### HR tables used by this sample

setup.sql creates the following tables and sample data:

| Table | Purpose |
| --- | --- |
| HR.EMPLOYEES | Employee identity, organization, contact, and salary data. |
| HR.DEPARTMENTS | Department names and locations. |
| HR.LOCATIONS | City, state/province, and country reference data. |
| HR.PERFORMANCE_NOTES | Private manager notes and employee-visible feedback. |

Use setup.sql as the reference implementation for the HR schema, sample data,
OCI IAM group-mapped data roles, application identity, and data grants used by
this project. Do not run it against an existing populated ADB: its first section
drops and recreates the HR schema so that it can rebuild the complete demo from
scratch.

Before running setup.sql in a new environment, replace its DEFINE placeholders
with the target OCI IAM username domain, employee IAM usernames, database
connection-pool password, IAM group names, and the COMPENSATION_AGENT OAuth
Client ID. OCI IAM external authentication for the database resource application
must be configured separately before this schema script is run.

## Environment configuration

Copy or create .env in the application directory. Store real secrets only in that local file and restrict its permissions with chmod 600 .env.

    # ADB connection pool
    DB_USER=db_usr
    DB_PASSWORD=<db_usr password>
    DB_DSN=<wallet TNS alias>
    SSL_CONFIG_DIR=/absolute/path/to/extracted/adb-wallet
    WALLET_PWD=<wallet password>

    # OCI Generative AI API-key profile
    OCI_CONFIG_FILE=/absolute/path/to/.oci/config
    OCI_PROFILE=<API-key profile name>
    COMPARTMENT_ID=<OCI compartment OCID>
    MODEL_ID=<OCI Generative AI model OCID>
    OCI_GENAI_ENDPOINT=https://inference.generativeai.<region>.oci.oraclecloud.com
    MAX_TOKENS=4096

    # Optional connection-pool settings; shown defaults are used if omitted.
    DB_POOL_MIN=1
    DB_POOL_MAX=4
    DB_POOL_INCREMENT=1

    # HR mode
    HR_OCI_DOMAIN_URL=https://idcs-<domain>.identity.oraclecloud.com:443
    HR_DB_APP_ID=<database resource application ID>
    HR_DB_SCOPE=<database access scope FQS>
    HR_DB_CLIENT_ID=<HR Midtier OAuth client ID>
    HR_DB_CLIENT_SECRET=<HR Midtier client secret>
    HR_APP_CLIENT_ID=<browser-login OAuth client ID>
    HR_APP_CLIENT_SECRET=<browser-login client secret>
    HR_APP_SCOPE=<HR agent access scope FQS>
    HR_REDIRECT_URI=http://localhost:8888/callback

    # Compensation mode
    COMP_OCI_DOMAIN_URL=https://idcs-<domain>.identity.oraclecloud.com:443
    COMP_DB_APP_ID=<same database resource application ID>
    COMP_DB_SCOPE=<same database access scope FQS>
    COMP_DB_CLIENT_ID=<COMPENSATION_AGENT OAuth client ID>
    COMP_DB_CLIENT_SECRET=<COMPENSATION_AGENT client secret>
    COMP_APP_CLIENT_ID=<browser-login OAuth client ID>
    COMP_APP_CLIENT_SECRET=<browser-login client secret>
    COMP_APP_SCOPE=<compensation agent access scope FQS>
    COMP_REDIRECT_URI=http://localhost:8889/callback

HR_DB_APP_ID and COMP_DB_APP_ID document the IAM application registered to the database. The runtime pool uses the associated *_DB_CLIENT_ID, *_DB_CLIENT_SECRET, and *_DB_SCOPE to obtain the database-access token.

Use exact FQS values copied from the OCI IAM Console. Do not construct or shorten them manually.

## Install and run

Install dependencies using Python 3.12. A virtual environment is recommended, but a user-level installation also works.

    python3.12 -m venv .venv
    source .venv/bin/activate
    python -m pip install --upgrade pip
    python -m pip install -r requirements.txt

If you choose not to use a virtual environment:

    python3.12 -m pip install --user -r requirements.txt

Start the HR agent:

    python3.12 langchain_app.py --agent hr

Start the compensation agent:

    python3.12 langchain_app.py --agent compensation

At startup, the application prints an OCI IAM authorization URL. Open it in a browser, sign in as an authorized OCI IAM user, and paste the final redirect URL back into the terminal. If the browser reports that localhost:8888 or localhost:8889 is unreachable, copy the complete URL from the address bar; this CLI does not host a callback server.

Enter exit or quit at the agent prompt to end the session.

## Available tools

### HR Agent

- get_current_user
- list_tables
- describe_table
- get_employee
- search_employees
- get_my_direct_reports
- get_salary_summary
- execute_sql
- propose_update

execute_sql runs read-only queries through the same Deep Data Security session.
propose_update stages a requested change for the CLI confirmation gate; it does
not execute the change. The database policy decides which confirmed operations
are actually permitted.

### Compensation Analytics Agent

- get_current_user
- get_salary_summary
- get_job_pay_range
- get_salary_statistics_by_location

It is restricted by its system prompt to aggregate salary questions and has no generic SQL tool.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| DPY-4026 mentioning tnsnames.ora | Set SSL_CONFIG_DIR to the VM-local extracted wallet directory; verify tnsnames.ora, sqlnet.ora, and cwallet.sso are readable. |
| OCI IAM token request fails | Verify the exact client ID, secret, scope FQS, redirect URI, and application/group grant in OCI IAM. Request a new authorization URL for every retry. |
| User signs in but sees no HR data | Confirm the user is in the EMPLOYEES or MANAGERS group as appropriate, and that HR.EMPLOYEES.USER_NAME exactly matches ORA_END_USER_CONTEXT.username. |
| Compensation scope is denied | Confirm the user belongs to HR_REPS and that group is granted access to the compensation application. |
| InvalidConfig user missing | Configure a valid OCI API-key profile containing user, tenancy, fingerprint, key_file, and region, then set OCI_CONFIG_FILE and OCI_PROFILE. |
| Agent reports an internal error | Review langchain_demo.log in the application directory. |

## Security notes

- Never commit .env, database wallet files, OCI private keys, or OAuth client secrets.
- Rotate OAuth client secrets if they are disclosed.
- Use the smallest practical IAM group assignments and Deep Data Security grants.
- The database data grants are authoritative even if an LLM prompt or tool is changed.
