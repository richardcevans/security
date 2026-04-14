# Identity-Aware Database Access with Microsoft Entra ID and Oracle Deep Data Security

Welcome to this **Oracle Deep Data Security LiveLabs** workshop.

This lab walks you through configuring Microsoft Entra ID authentication for Oracle AI Database 26ai and then layering Oracle Deep Data Security — end users, data roles, and data grants — so the database enforces per-user access based on Entra ID app role assignments. By the end, Marvin (a manager) and Emma (an employee) will authenticate with Entra ID and see completely different data from the same SQL query, enforced by the database kernel.

Estimated Time: 60 minutes

## The Challenge

AI copilots and agentic applications are transforming the enterprise, but many never make it past the security review. The blocking question is always the same: *how do you guarantee the AI agent only shows each user what they're authorized to see?*

Traditional approaches rely on the application to filter data — appending WHERE clauses, checking roles, hiding columns. This is fragile: a bug, a prompt injection, or a misconfigured endpoint leaks data. And managing database passwords for every user does not scale.

This lab solves both problems:

1. **Microsoft Entra ID** handles authentication — users log in with SSO, MFA, and zero database passwords
2. **Oracle Deep Data Security** handles authorization — data grants enforce row and column access at the database kernel level

```
Marvin → Entra ID login → Browser auth → AZURE_INTERACTIVE → Database
                                                                ↓
                                                      Data grants filter
                                                      (4 rows: self + team)

Emma   → Entra ID login → Browser auth → AZURE_INTERACTIVE → Database
                                                                ↓
                                                      Data grants filter
                                                      (1 row: self only)
```

Same SQL. Zero application filtering. Zero database passwords. The security is on the grant, not the code.

## What You Will Build

![Architecture diagram](./images/architecture.png "Architecture diagram showing Marvin and Emma authenticating through Entra ID to Oracle with data grants enforcing per-user access.")

### Prerequisites

This lab assumes:

- An **Oracle AI Database 26ai** instance with TCPS listener on port 2484
- `SYSTEM` and `SYS` access to a pluggable database (e.g., PDB1)
- An **Azure subscription** with permissions to register applications, create app roles, and create users in Microsoft Entra ID
- The Oracle Database wallet is configured for TLS connections

### Task 0: Download lab scripts

1. Open a Terminal session on your **DBSec-Lab** VM as OS user *oracle* and `cd` to the livelabs directory.

    ````
    <copy>cd livelabs</copy>
    ````

2. Download the bundled script archive for this lab.

    ````
    <copy>wget https://objectstorage.us-ashburn-1.oraclecloud.com/p/_vC6pMGFQLjZ-4ndpRr54m4IKQKHNcSGc7cS4lmkFh8JcsJ3DeYz6nKeMbe88s3Q/n/oradbclouducm/b/dbsec_public/o/entra-id-data-grants.zip</copy>
    ````

3. Extract the archive.

    ````
    <copy>tar xvf dbsec-livelabs-entra-id-data-grants.tar.gz</copy>
    ````

4. Move into the lab directory.

    ````
    <copy>cd entra-id-data-grants</copy>
    ````

5. List files to confirm the scripts are present.

    ````
    <copy>ls</copy>
    ````

## Part 1: Configure Microsoft Entra ID

### Task 1: Register the Oracle AI Database with Microsoft Entra ID

Register your Oracle Database as an application in Entra ID so it can accept OAuth2 tokens.

1. Log in to the [Azure portal](https://portal.azure.com) as an administrator with Microsoft Entra ID privileges to register applications.

      ![Azure services](./images/entra-id-page-01.png "Click on Azure services Microsoft Entra ID page")

2. Click the `+ Add` icon on the **Default Directory | Overview** page.

      ![Azure services](./images/entra-id-page-02.png "Click add")

3. Choose **App registration**

      ![Azure services](./images/entra-id-page-03.png "Choose app registration")

4. Select **New registration**:

      - **Name:** Oracle Database 26ai
      - **Supported account types:** Accounts in this organizational directory only
      - **Redirect URI:** *leave blank*
      - Click **Register**

      ![Azure services](./images/entra-id-page-04.png "Register the new application")

5. Record the **Application (client) ID** and the **Directory (tenant) ID** — you will need these for the database configuration and `tnsnames.ora`.

### Task 2: Create the Application ID URI and scope

After Task 1, you will be on the **Oracle Database 26ai** app registration **Overview** page.

1. Click on the **Application ID URI** to add one.

      ![Azure services](./images/entra-id-page-05.png "Add an Application ID URI")

2. On the **Expose an API** page, click **Add** next to the **Application ID URI**

      ![Azure services](./images/entra-id-page-06.png "Add an Application ID URI")

3. Set the **Application ID URI** to the HTTPS version:

      - **Application ID URI:** `https://<your-tenant-name>.onmicrosoft.com/<application-id>`

      ![Azure services](./images/entra-id-page-07.png "Modify the Application ID URI")

4. Click **Add a scope**:

      - **Scope name:** `session:scope:connect`
      - **Who can consent?** `Admins and users`
      - **Admin consent display name:** `Connect to Oracle AI Database`
      - **Admin consent description:** `Connect to Oracle AI Database 26ai`
      - **User consent display name:** `Connect to Oracle AI Database`
      - **User consent description:** `Connect to Oracle AI Database 26ai`
      - Click **Add scope**

      ![Azure services](./images/entra-id-page-08.png "Add a scope")

### Task 3: Create application roles

Create the Entra ID app roles that will map to Oracle data roles.

1. On the **Manage** section, click **App roles**

      ![Azure services](./images/entra-id-page-09.png "App roles")

2. Click **Create app role** and create two roles:

      **EMPLOYEES role:**
      - **Display name:** `EMPLOYEES`
      - **Allowed member types:** `Both (Users/Groups + Applications)`
      - **Value:** `EMPLOYEES`
      - **Description:** `EMPLOYEES`

      **MANAGERS role:**
      - **Display name:** `MANAGERS`
      - **Allowed member types:** `Both (Users/Groups + Applications)`
      - **Value:** `MANAGERS`
      - **Description:** `MANAGERS`

      ![Azure services](./images/entra-id-page-11.png "Create app roles")

3. Verify you have two app roles:

      ![Azure services](./images/entra-id-page-12.png "Verify app roles")

### Task 4: Assign users to app roles

Assign Marvin and Emma to the appropriate Entra ID app roles.

1. From the app roles page, click **How do I assign App roles** and then click **Enterprise applications**.

      ![Azure services](./images/entra-id-page-13a.png "Assign app roles")

2. Click **Assign users and groups**

      ![Azure services](./images/entra-id-page-14.png "Assign users and groups")

3. Click **Add user/group**

      ![Azure services](./images/entra-id-page-14a.png "Click add user/group")

4. Under **Users**, click **None Selected** and add **Marvin**

      ![Azure services](./images/entra-id-page-17.png "Add Marvin")

5. Select the **MANAGERS** role and click **Assign**

      ![Azure services](./images/entra-id-page-18.png "Assign MANAGERS role")
      ![Azure services](./images/entra-id-page-19.png "Click Assign")

6. Repeat for **Marvin** with the `EMPLOYEES` app role.

7. Repeat for **Emma** with the `EMPLOYEES` app role.

8. The final output should show three assignments:

      ![Azure services](./images/entra-id-page-20.png "Final app role assignments")

      | User | App Role |
      |---|---|
      | Marvin | MANAGERS |
      | Marvin | EMPLOYEES |
      | Emma | EMPLOYEES |

### Task 5: Create the browser authentication app

Create a second Entra ID application for interactive (browser) authentication. This app launches the user's browser for Entra ID login and passes the token to the database.

1. Navigate back to **Microsoft Entra ID** > **App registrations** > **+ New registration**

2. Register the new application:

      - **Name:** Oracle Client Interactive
      - **Supported account types:** Single tenant only - Default Directory
      - **Redirect URI:** `Public client/native (mobile & desktop)` with value `http://localhost`
      - Click **Register**

      ![Azure services](./images/entra-id-page-24.png "Register Oracle Client Interactive")

3. Record the **Application (client) ID** for this app — this is your `CLIENT_ID` for `tnsnames.ora`.

      ![Azure services](./images/entra-id-page-25.png "View essentials page")

4. Navigate to **Authentication** and ensure **Allow public client flows** is set to **Enabled**. Click **Save**.

      ![Azure services](./images/entra-id-page-25a.png "Authentication settings")
      ![Azure services](./images/entra-id-page-26.png "Allow public client flows")

### Task 6: Assign API permissions to the client app

Link the client app to the database app so tokens can flow.

1. Click **API permissions** > **Add a permission**

      ![Azure services](./images/entra-id-page-27.png "Add an API permission")

2. Click **APIs my organization uses** and search for `Oracle Database 26ai`

      ![Azure services](./images/entra-id-page-28.png "Search for Oracle Database 26ai")

3. Select **Delegated permissions**, choose `session:scope:connect`, and click **Add permissions**

      ![Azure services](./images/entra-id-page-29.png "Add delegated permissions")

4. Click **Grant admin consent for Default Directory**

      ![Azure services](./images/entra-id-page-30.png "Grant admin consent")

5. Verify the **Status** column shows "Granted":

      ![Azure services](./images/entra-id-page-31.png "Status shows Granted")

## Part 2: Configure the Oracle Database

### Task 7: Set database identity provider parameters

Configure the database to accept Entra ID tokens. You need the `APP_ID`, `TENANT_ID`, and `APP_ID_URI` from Tasks 1-2.

### Try it

```bash
./01_configure_db_identity_provider.sh
```

This script sets the `identity_provider_type` and `identity_provider_config` parameters in the pluggable database. Before running, set these environment variables:

```bash
export APP_ID=<your-oracle-db-app-id>
export APP_ID_URI=https://<your-tenant-name>.onmicrosoft.com/<your-oracle-db-app-id>
export TENANT_ID=<your-tenant-id>
```

The script runs the following as SYS:

```sql
ALTER SYSTEM SET identity_provider_type = AZURE_AD SCOPE = BOTH;

ALTER SYSTEM SET identity_provider_config =
'{
  "application_id_uri": "<APP_ID_URI>",
  "tenant_id": "<TENANT_ID>",
  "app_id": "<APP_ID>"
}' SCOPE = BOTH;
```

### Task 8: Configure TCPS listener, sqlnet.ora, and tnsnames.ora

To authenticate with Entra ID, the database must use a TLS connection. This task configures the TCPS listener, wallet, and connection descriptor.

### Try it

```bash
./02_configure_network.sh
```

This script:
1. Creates a wallet with a self-signed certificate (if one does not exist)
2. Backs up and updates `listener.ora` to add a TCPS endpoint on port 2484
3. Backs up and updates `sqlnet.ora` with the wallet location
4. Adds the `hrdb` TNS entry to `tnsnames.ora` with `TOKEN_AUTH=AZURE_INTERACTIVE`
5. Restarts the listener and registers the database

Before running, set these environment variables (in addition to the ones from Task 7):

```bash
export CLIENT_ID=<your-oracle-client-interactive-app-id>
export PDB_NAME=<your-pdb-name>      # defaults to pdb1
```

The `tnsnames.ora` entry will look like:

```
hrdb =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCPS)(HOST = <hostname>)(PORT = 2484))
    (SECURITY =
      (SSL_SERVER_DN_MATCH = YES)
      (SSL_SERVER_CERT_DN = "CN=<hostname>,O=DBSecLab,C=US")
      (TOKEN_AUTH = AZURE_INTERACTIVE)
      (CLIENT_ID = <client-id>)
      (AZURE_DB_APP_ID_URI = <app-id-uri>)
      (TENANT_ID = <tenant-id>)
    )
    (CONNECT_DATA =
      (SERVICE_NAME = <pdb>)
    )
  )
```

When you connect with `sqlplus /@hrdb`, the database launches your browser for Entra ID login.

## Part 3: Create Deep Data Security Objects

### Task 9: Create the HR schema and employee data

Create the HR schema with a `NO AUTHENTICATION` account (schema-only — it cannot log in) and populate it with 7 sample employees.

### Try it

```bash
./03_create_hr_schema.sh
```

This script creates the HR schema, the `EMPLOYEES` table, and 7 sample rows:

| Employee | Role | Department | Manager |
|---|---|---|---|
| Grace Young | CEO | — | — |
| Marvin Morgan | SWE_MGR | 1 | Grace |
| Emma Baker | SWE2 | 1 | Marvin |
| Charlie Davis | SWE1 | 1 | Marvin |
| Dana Lee | SWE3 | 1 | Marvin |
| Bob Smith | SALES_REP | 2 | Grace |
| Fiona Chen | HR_REP | 3 | Grace |

> **Key difference from the direct-auth lab:** HR is created with `NO AUTHENTICATION` from the start — there is no shared service account to migrate away from.

### Task 10: Create data roles, data grants, and end user context

This is the core of Deep Data Security. You create data roles that map to the Entra ID app roles, then attach data grants that define row and column access.

### Try it

```bash
./04_create_data_roles_and_grants.sh
```

This script:

1. **Creates data roles with `MAPPED TO`** — this is the key difference from direct-auth:

      ```sql
      CREATE OR REPLACE DATA ROLE hrapp_employees
        MAPPED TO 'azure_role=EMPLOYEES';

      CREATE OR REPLACE DATA ROLE hrapp_managers
        MAPPED TO 'azure_role=MANAGERS';
      ```

      When Marvin authenticates via Entra ID, his token contains the `EMPLOYEES` and `MANAGERS` app roles. Oracle automatically activates the corresponding data roles. No `CREATE END USER` or `GRANT DATA ROLE` needed — the mapping is declarative.

2. **Creates the employee data grant** — employees see only their own row:

      ```sql
      CREATE OR REPLACE DATA GRANT hr.HRAPP_EMPLOYEES_ACCESS
        AS SELECT (employee_id, first_name, last_name, user_name,
                   department_id, manager_id, ssn, salary, phone_number),
           UPDATE(phone_number)
        ON hr.employees
        WHERE upper(user_name) = upper(ora_end_user_context.username)
        TO HRAPP_EMPLOYEES;
      ```

3. **Creates the end user context** with `o:onFirstRead` trigger for lazy resolution of `employee_id`

4. **Creates the manager data grant** — managers see direct reports (no SSN), can update salary:

      ```sql
      CREATE OR REPLACE DATA GRANT hr.HRAPP_MANAGER_ACCESS
        AS SELECT (ALL COLUMNS EXCEPT ssn), UPDATE (salary, department_id)
        ON hr.employees
        WHERE manager_id = ORA_END_USER_CONTEXT.HR.EMP_CTX.ID
        TO HRAPP_MANAGERS;
      ```

5. **Creates context grants and role bindings** — `CREATE SESSION` via database role, context access via data grant on `SYS.END_USER_CONTEXT`.

### Task 11: Connect and verify as Marvin

Connect as Marvin via Entra ID and verify the data grants enforce per-user access.

### Try it

```bash
./05_verify_as_marvin.sh
```

This script connects as Marvin using `sqlplus /@hrdb` — which launches the Entra ID browser login. After authentication, it verifies:

1. **Identity:** `CURRENT_USER = XS$NULL`, `AUTHENTICATED_IDENTITY = marvin@<your-tenant>.onmicrosoft.com`
2. **Active data roles:** `HRAPP_EMPLOYEES`, `HRAPP_MANAGERS` (plus default roles)
3. **Query results:** `SELECT * FROM hr.employees` returns **4 rows** — Marvin + 3 direct reports
4. **Per-column authorization:** SSN visible for self only, salary visible for all 4, UPDATE only on phone_number (self) and salary/department (reports)

| EMPLOYEE\_ID | FIRST\_NAME | SSN | SALARY | MANAGER\_ID |
|---|---|---|---|---|
| 2 | Marvin | 222-22-2222 | 175000 | 1 |
| 3 | Emma | | 120000 | 2 |
| 4 | Charlie | | 95000 | 2 |
| 5 | Dana | | 130000 | 2 |

Same query as the direct-auth lab. Same results. The only difference is **how** Marvin authenticated — via Entra ID instead of a database password.

### Task 12: Connect and verify as Emma

Connect as Emma via Entra ID and verify she sees only her own data.

### Try it

```bash
./06_verify_as_emma.sh
```

Emma sees **1 row** — herself only. She can view her SSN and salary but can only update her phone number. Same SQL, completely different results.

| EMPLOYEE\_ID | FIRST\_NAME | SSN | SALARY |
|---|---|---|---|
| 3 | Emma | 333-33-3333 | 120000 |

### Task 13: Verify the security boundary

Test that end users cannot bypass data grants — even through the Entra ID authentication path.

### Try it

```bash
./07_verify_security_boundary.sh
```

This script runs four tests:

1. **Marvin tries to see Bob's SSN** — 0 rows (Bob is invisible to Marvin)
2. **Emma tries to update her salary** — 0 rows updated (only phone_number allowed)
3. **Emma tries to update Marvin's phone number** — 0 rows updated (predicate limits to own row)
4. **Direct connect as HR** — fails (NO AUTHENTICATION)

No prompt injection, misconfigured endpoint, or application bug can circumvent these controls. The enforcement is in the database kernel.

### Task 14 (Optional): Clean up

Remove all lab objects — Entra ID configuration and database objects.

### Try it

```bash
./08_cleanup.sh
```

This script:
1. Drops all data grants (context grant requires SYS)
2. Drops end user context, roles, data roles
3. Drops the HR schema
4. Resets `identity_provider_type` and `identity_provider_config`

**Azure cleanup** (manual — done in the Azure portal):
1. Delete the **Oracle Client Interactive** app registration
2. Delete the **Oracle Database 26ai** app registration

### Complete script sequence

| Script | Purpose |
|---|---|
| `01_configure_db_identity_provider.sh` | Set identity\_provider\_type and identity\_provider\_config |
| `02_configure_network.sh` | Create wallet, configure TCPS listener, sqlnet.ora, tnsnames.ora |
| `03_create_hr_schema.sh` | Create HR schema (NO AUTHENTICATION) with employee data |
| `04_create_data_roles_and_grants.sh` | Create data roles (MAPPED TO azure\_role), data grants, context |
| `05_verify_as_marvin.sh` | Connect as Marvin via Entra ID — 4 rows |
| `06_verify_as_emma.sh` | Connect as Emma via Entra ID — 1 row |
| `07_verify_security_boundary.sh` | Test bypass attempts — all fail |
| `08_cleanup.sh` | Drop everything, reset identity provider |

## Key Differences: Entra ID vs. Direct Password

| Aspect | Direct Password (migrate-apps lab) | Entra ID (this lab) |
|---|---|---|
| Authentication | `CREATE END USER marvin IDENTIFIED BY Oracle123` | Entra ID OAuth2 token via `AZURE_INTERACTIVE` |
| Data role activation | `GRANT DATA ROLE ... TO marvin` (explicit) | `MAPPED TO 'azure_role=MANAGERS'` (automatic from token) |
| End user creation | `CREATE END USER marvin` required | Not needed — identity comes from the token |
| Connection string | `sqlplus marvin/Oracle123@pdb1` | `sqlplus /@hrdb` (browser login) |
| Password management | Database manages passwords | Entra ID manages passwords, MFA, SSO |
| Data grants | Identical | Identical |
| SQL queries | Identical | Identical |

The data grants are the same in both approaches. The only difference is how the user's identity reaches the database.

## Learn More

* [Oracle AI Database 26ai Documentation](https://docs.oracle.com/en/database/)

## Acknowledgements
* **Author** - Oracle Database Security Product Management
* **Last Updated By/Date** - April 2026
