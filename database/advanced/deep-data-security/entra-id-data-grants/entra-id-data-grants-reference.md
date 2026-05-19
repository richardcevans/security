# Identity-Aware Database Access with Microsoft Entra ID and Oracle Deep Data Security

Welcome to this **Oracle Deep Data Security LiveLabs** workshop.

This lab walks you through configuring Microsoft Entra ID authentication for Oracle AI Database 26ai and then layering Oracle Deep Data Security — end users, data roles, and data grants — so the database enforces per-user access based on Entra ID app role assignments. By the end, Marvin (a manager) and Emma (an employee) will authenticate with Entra ID and see completely different data from the same SQL query, enforced by the database kernel.

Estimated Time: 60 minutes

### Objectives

Use this reference when you need the expanded security notes, manual fallback
steps, rollback commands, audit locations, and troubleshooting details that were
removed from the shorter task guide.

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

## Table Of Contents

- [What You Will Build](#what-you-will-build)
- [Prerequisites](#prerequisites)
- [Important Defaults](#important-defaults)
- [Do Not Do This](#do-not-do-this)
- [Security Model](#security-model)
- [Threat Model](#threat-model)
- [Security-Critical Claims](#security-critical-claims)
- [Least Privilege Design](#least-privilege-design)
- [Secrets And Session Inventory](#secrets-and-session-inventory)
- [Browser Session Handling](#browser-session-handling)
- [Security Validation Checklist](#security-validation-checklist)
- [DBA Production Caution](#dba-production-caution)
- [Network File Backups And Restore](#network-file-backups-and-restore)
- [Install Azure CLI](#install-azure-cli)
- [Part 1: Configure Microsoft Entra ID](#part-1-configure-microsoft-entra-id)
- [Part 2: Configure the Oracle Database](#part-2-configure-the-oracle-database)
- [Part 3: Create Deep Data Security Objects](#part-3-create-deep-data-security-objects)
- [Rerun Safety](#rerun-safety)
- [Database Parameter Rollback](#database-parameter-rollback)
- [Audit And Log Locations](#audit-and-log-locations)
- [Troubleshooting](#troubleshooting)
- [Key Differences: Entra ID vs. Direct Password](#key-differences-entra-id-vs-direct-password)
- [Learn More](#learn-more)

## What You Will Build

![Architecture diagram](./images/architecture.png "Architecture diagram showing Marvin and Emma authenticating through Entra ID to Oracle with data grants enforcing per-user access.")

### Prerequisites

This lab assumes:

- An **Oracle AI Database 26ai April 2026 Release Update (RU)** instance
- The `oracle` OS user, or another OS user that can run `sqlplus / as sysdba`
- A local CDB and PDB. The default script values are `DB_SID=FREE` and `PDB_NAME=FREEPDB1`
- On the DBSec-Lab VM, source the DB23 Free environment before database-side tasks:

    ```bash
    source $DBSEC_ADMIN/setEnv-db23free.sh FREE FREEPDB1
    ```

- An **Azure subscription** with permissions to register applications, create app roles, and create users in Microsoft Entra ID
- Azure CLI installed and logged in with `az login`
- A local browser-capable desktop session, such as NoVNC on the lab host, for `AZURE_INTERACTIVE` browser login

`AZURE_INTERACTIVE` should open the browser automatically when SQLPlus runs in a local graphical session. Use a manual or headless token workaround only as a last resort for environments where a browser cannot be launched from the database client host.

## Important Defaults

| Setting | Default | Purpose |
|---|---|---|
| `DB_SID` | `FREE` | Local CDB instance used by the scripts |
| `PDB_NAME` | `FREEPDB1` | PDB/service used by the lab |
| `CLIENT_ID` | none | Entra ID client app Application ID for browser authentication |
| `APP_ID` | none | Entra ID database app Application ID |
| `APP_ID_URI` | none | Entra ID Application ID URI exposed by the database app |
| `TENANT_ID` | none | Entra ID Directory tenant ID |
| `DOMAIN_NAME` | none | Entra username domain used in HR sample rows |
| `WALLET_DIR` | `$ORACLE_BASE/admin/$ORACLE_SID/wallet` | TCPS wallet location |

Use PDB-specific Entra application names so multiple database labs can coexist in the same tenant:

```text
Oracle Database 26ai - ${PDB_NAME}
```

```text
Oracle Client Interactive - ${PDB_NAME}
```

The examples below use the default `PDB_NAME=FREEPDB1`.

The setup script writes these values to:

```text
.entra-id-data-grants.env
```

Load it before running database setup scripts:

```bash
source ./.entra-id-data-grants.env
```

On the DBSec-Lab VM, always load the DB23 Free environment before loading the generated lab environment file for database-side scripts:

```bash
source $DBSEC_ADMIN/setEnv-db23free.sh FREE FREEPDB1
source ./.entra-id-data-grants.env
```

If your shell inherited `WALLET_DIR` or `TNS_ADMIN` from another database home, clear them before running `02_configure_network.sh` or the verification scripts:

```bash
unset WALLET_DIR TNS_ADMIN
```

## Do Not Do This

Do not skip admin consent on the client app API permission.

Do not continue if the verifier says you logged in as the wrong user.

Do not assume the browser will ask for credentials every time. Existing Entra browser sessions can silently sign in as the previous user.

Do not run `02_configure_network.sh` unchanged on production, RAC, Grid Infrastructure, SCAN listener, shared Oracle home, or Data Guard environments.

Do not paste browser tokens, authorization responses, or screenshots with sensitive token values into tickets or chats.

Do not give Marvin or Emma direct object grants on `HR.EMPLOYEES`. Access should come from data roles and data grants.

Do not make the `HR` schema password-authenticated for this lab. It should remain `NO AUTHENTICATION`.

## Security Model

This lab demonstrates database-enforced authorization for externally authenticated users.

Trust boundaries:

| Boundary | Responsibility |
|---|---|
| Microsoft Entra ID | Authenticates the user and issues the OAuth2 token |
| Entra app roles | Carry authorization group/role signals such as `EMPLOYEES` and `MANAGERS` |
| Oracle Database | Validates the token issuer, audience, tenant, and configured app registration |
| Data role mapping | Activates database data roles from Entra token app roles |
| Data grants | Enforce row and column access inside the database |
| SQLPlus | Client only; it does not enforce the access policy |

The security enforcement point is the database, not SQLPlus and not the application.

## Threat Model

This lab is designed to show protection against:

- an application or user running a broad `SELECT`
- end users with different Entra app roles running the same SQL
- accidental overexposure of rows or columns
- direct database logon without an Entra token that maps to a data role with `CREATE SESSION`
- application bugs that forget a row predicate or column mask

This lab does not protect against:

- `SYS`, DBA, or highly privileged database administrators
- a compromised `oracle` OS account
- a stolen OAuth2 bearer token or browser session cookie
- a compromised Microsoft Entra administrator
- a misconfigured Entra app registration or app role assignment
- a user whose Entra role assignment changed but who still has an already-issued token

## Security-Critical Claims

The Entra token must contain the expected identity and authorization claims.

Expected Marvin signals:

```text
authenticated identity contains marvin
```

```text
roles includes EMPLOYEES
```

```text
roles includes MANAGERS
```

Expected Emma signals:

```text
authenticated identity contains emma
```

```text
roles includes EMPLOYEES
```

```text
roles does not include MANAGERS
```

The database identity-provider configuration must match the Entra database app:

```text
identity_provider_type=AZURE_AD
```

```text
identity_provider_config.app_id=<APP_ID>
```

```text
identity_provider_config.tenant_id=<TENANT_ID>
```

```text
identity_provider_config.application_id_uri=<APP_ID_URI>
```

The app role values are authorization-critical. If the token does not contain the expected app role values, Oracle may authenticate the user but fail to activate the mapped data roles.

## Least Privilege Design

End users are not database schemas.

The `HR` schema is created with:

```sql
NO AUTHENTICATION
```

The direct logon role grants only:

```sql
CREATE SESSION
```

Data access comes from data grants, not normal object grants to Marvin or Emma.

The data roles map to Entra app roles:

```sql
HRAPP_EMPLOYEES -> azure_role=EMPLOYEES
```

```sql
HRAPP_MANAGERS -> azure_role=MANAGERS
```

Changing Entra app role assignments affects newly issued tokens. To test role changes, close the browser session or use a private/incognito browser window and connect again.

## Secrets And Session Inventory

Sensitive local files, values, and sessions:

| Item | Location | Notes |
|---|---|---|
| Entra database app ID | `APP_ID` | Used in database identity-provider config |
| Entra Application ID URI | `APP_ID_URI` | Token audience/resource identifier |
| Entra tenant ID | `TENANT_ID` | Token issuer/tenant validation |
| Entra client app ID | `CLIENT_ID` | Used by `AZURE_INTERACTIVE` browser login |
| Lab env file | `.entra-id-data-grants.env` | Contains app IDs, tenant ID, domain, and PDB-specific app names |
| Browser session cookies | Browser profile | Can silently log in as the previous user |
| TCPS wallet | `$ORACLE_BASE/admin/$ORACLE_SID/wallet` | Contains listener TLS wallet |
| Network backups | `$ORACLE_HOME/network/admin/*.bak` | May contain old connection descriptors |

This lab does not store an Entra client secret because the interactive client is a public/native client.

## Browser Session Handling

`AZURE_INTERACTIVE` should open the local browser automatically.

When switching from Marvin to Emma:

- close Entra ID browser windows, or
- sign out of Entra ID, or
- use a private/incognito browser window

If the browser silently authenticates the wrong user, the verification scripts should fail after login because they check `AUTHENTICATED_IDENTITY`.

## Security Validation Checklist

Before calling the lab complete, verify:

- `00_preflight.sh` has no blocking failures
- `verify_db_setup.sh` shows `identity_provider_type=AZURE_AD`
- `verify_db_setup.sh` shows `HRAPP_EMPLOYEES` maps to `azure_role=EMPLOYEES`
- `verify_db_setup.sh` shows `HRAPP_MANAGERS` maps to `azure_role=MANAGERS`
- `DIRECT_LOGON_ROLE` has only `CREATE SESSION`
- `DIRECT_LOGON_ROLE` is granted to both data roles
- `HR` has `NO AUTHENTICATION`
- Marvin login activates `HRAPP_EMPLOYEES` and `HRAPP_MANAGERS`
- Emma login activates `HRAPP_EMPLOYEES` only
- Marvin sees only his authorized rows
- Emma sees only her own row
- Emma cannot update salary
- Emma cannot update Marvin's phone number
- HR direct login fails
- Database alert log has no token validation errors after successful login

## DBA Production Caution

This lab is designed for a single-instance lab VM.

`02_configure_network.sh` rewrites these files in `$ORACLE_HOME/network/admin`:

```text
listener.ora
```

```text
sqlnet.ora
```

```text
tnsnames.ora
```

It also restarts the listener.

On production, RAC, Grid Infrastructure, SCAN listener, shared Oracle home, or Data Guard environments, do not run `02_configure_network.sh` as-is. Adapt the listener, wallet, and TNS changes manually with your normal DBA change process.

## Network File Backups And Restore

`02_configure_network.sh` creates backup files before rewriting network configuration.

Backup files are created in:

```text
$ORACLE_HOME/network/admin
```

Expected backup files:

```text
listener.ora.bak
```

```text
sqlnet.ora.bak
```

```text
tnsnames.ora.bak
```

To restore `listener.ora`:

```bash
cp -v "$ORACLE_HOME/network/admin/listener.ora.bak" "$ORACLE_HOME/network/admin/listener.ora"
```

To restore `sqlnet.ora`:

```bash
cp -v "$ORACLE_HOME/network/admin/sqlnet.ora.bak" "$ORACLE_HOME/network/admin/sqlnet.ora"
```

To restore `tnsnames.ora`:

```bash
cp -v "$ORACLE_HOME/network/admin/tnsnames.ora.bak" "$ORACLE_HOME/network/admin/tnsnames.ora"
```

Restart the listener after restoring listener files:

```bash
lsnrctl stop
```

```bash
lsnrctl start
```

### Task 0: Download entra-id-data-grants.zip file to local directory

1. Open a Terminal session on your **DBSec-Lab** VM as OS user *oracle* and use `cd` command to move to livelabs directory.

    ````
    <copy>cd livelabs</copy>
    ````

    **Note**: If you are using a remote desktop session, double-click on the *Terminal* icon on the desktop to launch a session

2. Use the Linux command 'wget' to download a bundled (zipped) file of the commands for the lab.

    ````
    <copy>wget -O entra-id-data-grants.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/aSXtPT18-67-gR7BdvSd5VtxmxemrI5KpRkoMYoN6S22aUhRnrB5O12ZaoXbjgLE/n/oradbclouducm/b/dbsec_public/o/entra-id-data-grants.zip</copy>
    ````

3. Unarchive the downloaded zip to expand the directory and scripts.

    ````
    <copy>unzip -o entra-id-data-grants.zip</copy>
    ````

4. Use `cd` command to move to entra-id-data-grants directory.

    ````
    <copy>cd entra-id-data-grants</copy>
    ````

5. Use `ls` command to list files.

    ````
    <copy>ls</copy>
    ````

## Install Azure CLI

Azure CLI is required for `00_setup_entra_id.sh`. The script uses Azure CLI and Microsoft Graph to create and update Entra ID app registrations, enterprise applications, app roles, API permissions, and optional user role assignments.

### Oracle Linux 9

````
<copy>sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc</copy>
````

````
<copy>sudo dnf install -y https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm</copy>
````

````
<copy>sudo dnf install -y azure-cli</copy>
````

### Oracle Linux 8

````
<copy>sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc</copy>
````

````
<copy>sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm</copy>
````

````
<copy>sudo dnf install -y azure-cli</copy>
````

### Generic Linux Installer

Use this only if your lab host does not use the Oracle Linux package path above.

````
<copy>curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash</copy>
````

### Verify Azure CLI

````
<copy>az version</copy>
````

## Part 1: Configure Microsoft Entra ID

### Task 1: Sign in to Azure CLI

Sign in with an account that can create Microsoft Entra app registrations, create service principals, grant admin consent, and assign app roles.

````
<copy>az login</copy>
````

Verify the selected tenant:

````
<copy>az account show --query "{tenantId:tenantId,name:name,user:user.name}" --output table</copy>
````

### Task 2: Create Entra ID Applications, Enterprise Apps, Roles, and Permissions

Run the setup script:

````
<copy>./00_setup_entra_id.sh</copy>
````

Load the generated environment file:

````
<copy>source ./.entra-id-data-grants.env</copy>
````

Verify the Entra objects:

````
<copy>./verify_entra_id_setup.sh</copy>
````

The setup script creates or reuses:

- app registration and enterprise application: `Oracle Database 26ai - ${PDB_NAME}`
- app registration and enterprise application: `Oracle Client Interactive - ${PDB_NAME}`
- app roles on the database app: `EMPLOYEES`, `MANAGERS`
- delegated permission scope: `session:scope:connect`
- public client redirect URI: `http://localhost`
- API permission from the client app to the database app
- admin consent, if the signed-in Azure account is allowed to grant it
- optional Marvin/Emma role assignments, if those users already exist

The setup script tries to discover `DOMAIN_NAME` from Microsoft Graph. If your tenant blocks domain discovery, set it explicitly and rerun:

````
<copy>export DOMAIN_NAME=example.onmicrosoft.com</copy>
````

Default user lookup:

| User | UPN |
|---|---|
| Marvin | `marvin@${DOMAIN_NAME}` |
| Emma | `emma@${DOMAIN_NAME}` |

To use different existing Entra users, set these before running `00_setup_entra_id.sh`:

````
<copy>export MARVIN_UPN=marvin@example.com
export EMMA_UPN=emma@example.com</copy>
````

If your account cannot grant admin consent automatically, grant admin consent manually for the `Oracle Client Interactive - ${PDB_NAME}` API permission in the Azure portal.

### Manual Portal Fallback

The Azure portal steps below are a fallback if your environment does not allow Azure CLI app administration. If you use `00_setup_entra_id.sh`, skip the manual portal tasks and continue with Part 2.

### Manual Task 1: Register the Oracle AI Database with Microsoft Entra ID

Register your Oracle Database as an application in Entra ID so it can accept OAuth2 tokens.

1. Log in to the [Azure portal](https://portal.azure.com) as an administrator with Microsoft Entra ID privileges to register applications.

      ![Azure services](./images/entra-id-page-01.png "Click on Azure services Microsoft Entra ID page")

2. Click the `+ Add` icon on the **Default Directory | Overview** page.

      ![Azure services](./images/entra-id-page-02.png "Click add")

3. Choose **App registration**

      ![Azure services](./images/entra-id-page-03.png "Choose app registration")

4. Select **New registration**:

      - **Name:** `Oracle Database 26ai - FREEPDB1`
      - **Supported account types:** Accounts in this organizational directory only
      - **Redirect URI:** *leave blank*
      - Click **Register**

      ![Azure services](./images/entra-id-page-04.png "Register the new application")

5. Record the **Application (client) ID** and the **Directory (tenant) ID** — you will need these for the database configuration and `tnsnames.ora`.

### Manual Task 2: Create the Application ID URI and scope

After Manual Task 1, you will be on the **Oracle Database 26ai - FREEPDB1** app registration **Overview** page.

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

### Manual Task 3: Create application roles

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

### Manual Task 4: Assign users to app roles

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

### Manual Task 5: Create the browser authentication app

Create a second Entra ID application for interactive (browser) authentication. This app launches the user's browser for Entra ID login and passes the token to the database.

1. Navigate back to **Microsoft Entra ID** > **App registrations** > **+ New registration**

2. Register the new application:

      - **Name:** `Oracle Client Interactive - FREEPDB1`
      - **Supported account types:** Single tenant only - Default Directory
      - **Redirect URI:** `Public client/native (mobile & desktop)` with value `http://localhost`
      - Click **Register**

      ![Azure services](./images/entra-id-page-24.png "Register Oracle Client Interactive - FREEPDB1")

3. Record the **Application (client) ID** for this app — this is your `CLIENT_ID` for `tnsnames.ora`.

      ![Azure services](./images/entra-id-page-25.png "View essentials page")

4. Navigate to **Authentication** and ensure **Allow public client flows** is set to **Enabled**. Click **Save**.

      ![Azure services](./images/entra-id-page-25a.png "Authentication settings")
      ![Azure services](./images/entra-id-page-26.png "Allow public client flows")

### Manual Task 6: Assign API permissions to the client app

Link the client app to the database app so tokens can flow.

1. Click **API permissions** > **Add a permission**

      ![Azure services](./images/entra-id-page-27.png "Add an API permission")

2. Click **APIs my organization uses** and search for `Oracle Database 26ai - FREEPDB1`

      ![Azure services](./images/entra-id-page-28.png "Search for Oracle Database 26ai - FREEPDB1")

3. Select **Delegated permissions**, choose `session:scope:connect`, and click **Add permissions**

      ![Azure services](./images/entra-id-page-29.png "Add delegated permissions")

4. Click **Grant admin consent for Default Directory**

      ![Azure services](./images/entra-id-page-30.png "Grant admin consent")

5. Verify the **Status** column shows "Granted":

      ![Azure services](./images/entra-id-page-31.png "Status shows Granted")

## Part 2: Configure the Oracle Database

### Set the DB23 Free environment

Open a terminal as the `oracle` user and load the DB23 Free environment before running the database-side scripts in this section:

````
<copy>source $DBSEC_ADMIN/setEnv-db23free.sh FREE FREEPDB1</copy>
````

This sets `ORACLE_HOME`, `ORACLE_SID=FREE`, and `PDB_NAME=FREEPDB1` for the Oracle AI Database 26ai Free database. If your terminal was previously using another database home, clear inherited wallet or TNS settings:

````
<copy>unset WALLET_DIR TNS_ADMIN</copy>
````

### Script 0: Run DBA preflight checks

Before changing database or network files, verify the local database, listener, wallet tools, and browser-launch environment.

````
<copy>./00_preflight.sh</copy>
````

Fix any blocking failures before continuing. A warning about browser launch means `AZURE_INTERACTIVE` may not be able to open a browser from this shell; use a local desktop or NoVNC session when possible.

### Script 1: Set database identity provider parameters

Configure the database to accept Entra ID tokens. If you used `00_setup_entra_id.sh`, these values come from `.entra-id-data-grants.env`.

### Try it

Before running, load the generated environment file:

````
<copy>source ./.entra-id-data-grants.env</copy>
````

If you used the manual portal fallback, set these values yourself instead:

````
<copy>export APP_ID=<your-oracle-db-app-id>
export APP_ID_URI=https://<your-tenant-name>.onmicrosoft.com/<your-pdb-name>
export TENANT_ID=<your-tenant-id></copy>
````

Then run:

````
<copy>./01_configure_db_identity_provider.sh</copy>
````

This script connects locally as `SYSDBA`, switches to `PDB_NAME`, and sets the `identity_provider_type` and `identity_provider_config` parameters in the pluggable database.

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

### Script 2: Configure TCPS listener, sqlnet.ora, and tnsnames.ora

To authenticate with Entra ID, the database must use a TLS connection. This task configures the TCPS listener, wallet, and connection descriptor.

### Try it

Before running, make sure the environment file is loaded:

````
<copy>source ./.entra-id-data-grants.env</copy>
````

If needed, clear inherited wallet or TNS settings from another database home:

````
<copy>unset WALLET_DIR TNS_ADMIN</copy>
````

Then run:

````
<copy>./02_configure_network.sh</copy>
````

This script:
1. Creates a wallet with a self-signed certificate (if one does not exist)
2. Backs up and updates `listener.ora` to add a TCPS endpoint on port 2484
3. Backs up and updates `sqlnet.ora` with the wallet location
4. Adds the `hrdb` TNS entry to `tnsnames.ora` with `TOKEN_AUTH=AZURE_INTERACTIVE`
5. Restarts the listener and registers the database

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

When you connect with `sqlplus /@hrdb`, the Oracle client launches your browser for Entra ID login. If the browser silently signs in as the wrong user, close all Entra ID browser windows or use a private/incognito window before retrying.

### One-off helper: Export the database server certificate for a client

If you connect from SQLcl, the VS Code Oracle SQL Developer extension, or another Oracle client outside the lab VM, that client must trust the database server certificate created by `02_configure_network.sh`. This is still one-way TLS: the client trusts the database server certificate, and the database does not request a client certificate.

Run this helper on the DBSec-Lab VM after `02_configure_network.sh`:

````
<copy>./export_server_cert_for_client.sh</copy>
````

By default, the generated TNS snippet points to a Windows client wallet directory under:

````
C:\oracle\tns_admin\wallets\hrdb-<hostname>-<pdb>
````

For a Linux client path instead, run:

````
<copy>./export_server_cert_for_client.sh --linux</copy>
````

To set the exact wallet directory written into the generated TNS alias, pass `--client-wallet-directory`:

````
<copy>./export_server_cert_for_client.sh --client-wallet-directory C:\oracle\tns_admin\wallets\hrdb</copy>
````

Quote the path if it contains spaces:

````
<copy>./export_server_cert_for_client.sh --client-wallet-directory "C:\Program Files\Oracle\wallets\hrdb"</copy>
````

The helper exports the database server certificate from the TCPS wallet and creates a client trust bundle:

````
entra-id-data-grants-client-trust.zip
````

Copy the zip file to the client machine. For Oracle Instant Client systems that do not have `orapki`, copy the generated `hrdb-<hostname>-<pdb>` wallet directory to the path shown in `tnsnames-client-snippet.ora`. For SQLcl/JDBC clients, you can also use the generated `db_server_truststore.p12`. In all cases, keep `SSL_SERVER_DN_MATCH=YES` in the client connect descriptor.

## Part 3: Create Deep Data Security Objects

### Script 3: Create the HR schema and employee data

Create the HR schema with a `NO AUTHENTICATION` account (schema-only — it cannot log in) and populate it with 7 sample employees. The `user_name` values are set to full Entra ID email addresses — these are what the data grant predicates match against.

### Try it

Before running, set your Entra ID tenant domain (in addition to the variables from Scripts 1-2):

````
<copy>export DOMAIN_NAME=yourtenant.onmicrosoft.com</copy>
````

Then run:

````
<copy>./03_create_hr_schema.sh</copy>
````

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

### Script 4: Create data roles, data grants, and end user context

This is the core of Deep Data Security. You create data roles that map to the Entra ID app roles, then attach data grants that define row and column access.

### Try it

````
<copy>./04_create_data_roles_and_grants.sh</copy>
````

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

### Verify database setup

Before testing end-user logon, confirm the database identity provider parameters, data roles, direct logon role, data grants, and HR rows.

````
<copy>./verify_db_setup.sh</copy>
````

### Script 5: Connect and verify as Marvin

Connect as Marvin via Entra ID and verify the data grants enforce per-user access.

### Try it

````
<copy>./05_verify_as_marvin.sh</copy>
````

This script connects as Marvin using `sqlplus /@hrdb`, which should launch the Entra ID browser login automatically on a local desktop or NoVNC session. After authentication, it verifies:

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

### Script 6: Connect and verify as Emma

Connect as Emma via Entra ID and verify she sees only her own data.

### Try it

````
<copy>./06_verify_as_emma.sh</copy>
````

Emma sees **1 row** — herself only. She can view her SSN and salary but can only update her phone number. Same SQL, completely different results. If the browser reuses Marvin's Entra session, close the browser or use a private/incognito window and rerun the script.

| EMPLOYEE\_ID | FIRST\_NAME | SSN | SALARY |
|---|---|---|---|
| 3 | Emma | 333-33-3333 | 120000 |

### Script 7: Verify the security boundary

Test that end users cannot bypass data grants — even through the Entra ID authentication path.

### Try it

````
<copy>./07_verify_security_boundary.sh</copy>
````

This script runs four tests:

1. **Marvin tries to see Bob's SSN** — 0 rows (Bob is invisible to Marvin)
2. **Emma tries to update her salary** — 0 rows updated (only phone_number allowed)
3. **Emma tries to update Marvin's phone number** — 0 rows updated (predicate limits to own row)
4. **Direct connect as HR** — fails (NO AUTHENTICATION)

No prompt injection, misconfigured endpoint, or application bug can circumvent these controls. The enforcement is in the database kernel.

### Script 8 (Optional): Clean up

Remove database-side lab objects and reset the database identity-provider parameters.

### Try it

````
<copy>./08_cleanup.sh</copy>
````

This script:
1. Drops all data grants (context grant requires SYS)
2. Drops end user context, roles, data roles
3. Drops the HR schema
4. Resets `identity_provider_type` and `identity_provider_config`

**Azure cleanup** (manual — done in the Azure portal):
1. Delete the **Oracle Client Interactive - FREEPDB1** app registration
2. Delete the **Oracle Database 26ai - FREEPDB1** app registration

Or use the cleanup script:

````
<copy>./09_cleanup_entra_id.sh</copy>
````

To skip the confirmation prompt:

````
<copy>./09_cleanup_entra_id.sh -f</copy>
````

Also remove or review these Entra objects if you created them only for this lab:

- Marvin test user
- Emma test user
- App role assignments for Marvin and Emma
- Admin consent granted to the client app

Database cleanup does not remove browser sessions, Entra app registrations, Entra users, network backup files, or wallet files.

### Complete script sequence

| Script | Purpose |
|---|---|
| `00_preflight.sh` | Check local database, listener tools, and browser-launch readiness |
| `00_setup_entra_id.sh` | Create or reuse Entra app registrations, enterprise apps, roles, permissions, and optional assignments |
| `verify_entra_id_setup.sh` | Verify Entra app registrations, enterprise apps, roles, scopes, and permissions |
| `01_configure_db_identity_provider.sh` | Set identity\_provider\_type and identity\_provider\_config |
| `02_configure_network.sh` | Create wallet, configure TCPS listener, sqlnet.ora, tnsnames.ora |
| `03_create_hr_schema.sh` | Create HR schema (NO AUTHENTICATION) with employee data |
| `04_create_data_roles_and_grants.sh` | Create data roles (MAPPED TO azure\_role), data grants, context |
| `verify_db_setup.sh` | Verify database-side identity provider, data roles, grants, and HR rows |
| `lib_network_check.sh` | Shared check that `hrdb` resolves before verification scripts connect |
| `05_verify_as_marvin.sh` | Connect as Marvin via Entra ID — 4 rows |
| `06_verify_as_emma.sh` | Connect as Emma via Entra ID — 1 row |
| `07_verify_security_boundary.sh` | Optional/manual bypass checks that require multiple browser logins |
| `08_cleanup.sh` | Drop everything, reset identity provider |
| `09_cleanup_entra_id.sh` | Delete lab-created Entra app registrations and enterprise applications |

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

## Rerun Safety

| Script | Safe To Rerun? | Notes |
|---|---|---|
| `00_preflight.sh` | Yes | Read-only checks. |
| `01_configure_db_identity_provider.sh` | Yes | Reapplies identity-provider parameters. |
| `02_configure_network.sh` | Yes in the lab VM | Rewrites network files and restarts listener; use caution outside the lab VM. |
| `03_create_hr_schema.sh` | Yes, destructive for HR | Drops and recreates `HR`, so lab data is reset. |
| `04_create_data_roles_and_grants.sh` | Yes | Recreates data roles, grants, context, and direct logon role. |
| `verify_db_setup.sh` | Yes | Read-only verification. |
| `05_verify_as_marvin.sh` | Yes | Requires Marvin Entra login. Browser session cache may reuse another user. |
| `06_verify_as_emma.sh` | Yes | Requires Emma Entra login. Browser session cache may reuse another user. |
| `07_verify_security_boundary.sh` | Optional | Requires multiple browser logins and careful browser-session isolation. Marvin and Emma verification scripts are the primary acceptance checks. |
| `08_cleanup.sh` | Yes | Removes database-side lab objects and resets identity-provider parameters. |

## Database Parameter Rollback

To manually reset the Entra ID identity-provider parameters, connect locally as `SYSDBA` and switch to the lab PDB:

```bash
sqlplus / as sysdba
```

```sql
ALTER SESSION SET CONTAINER = FREEPDB1;
```

Then reset the parameters:

```sql
ALTER SYSTEM RESET IDENTITY_PROVIDER_CONFIG SCOPE=BOTH;
```

```sql
ALTER SYSTEM RESET IDENTITY_PROVIDER_TYPE SCOPE=BOTH;
```

Check the result:

```sql
SELECT name, value
  FROM v$parameter
 WHERE name LIKE 'identity_provider%';
```

Exit SQLPlus:

```sql
exit;
```

## Audit And Log Locations

Listener log:

```text
$ORACLE_BASE/diag/tnslsnr/<hostname>/listener/alert/log.xml
```

Find database alert logs with ADRCI:

```bash
adrci
```

Inside ADRCI, show homes:

```text
show homes
```

Inside ADRCI, select the database home:

```text
set home diag/rdbms/<db_unique_name>/<instance_name>
```

Inside ADRCI, show recent alert messages:

```text
show alert -tail 100
```

Token validation failures are usually visible in the database alert log. Look for messages containing:

```text
AZURE_AD
```

```text
identity provider
```

```text
token
```

If Unified Auditing is enabled in your environment, review your local audit policy and audit trail for logon events. This lab does not create or modify Unified Audit policies.

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| Browser does not open | No GUI session or browser launcher available | Use NoVNC/local desktop; treat manual/headless token flow as last resort |
| Browser logs in as Marvin when testing Emma | Existing Entra browser session | Close browser windows, sign out, or use private/incognito mode |
| `ORA-12154` or `Cannot find alias hrdb` | `hrdb` alias is missing from the active `tnsnames.ora` | Rerun `02_configure_network.sh`; check `TNS_ADMIN` |
| `ORA-12514` for `FREEPDB1` | PDB service not registered with listener | Rerun `02_configure_network.sh`; verify `lsnrctl status` shows `freepdb1` or `FREEPDB1` |
| `ORA-01017` after Entra login | Token validation or role/session problem | Check database alert log and rerun `01_configure_db_identity_provider.sh` |
| No active data roles | Entra app roles missing from token or wrong role values | Confirm Marvin/Emma app role assignments and sign in again |
| Marvin sees only his own row | `MANAGERS` app role missing or stale token/session | Confirm Marvin has `MANAGERS`, close browser session, rerun `05` |
| Emma has manager access | Emma assigned `MANAGERS` by mistake or browser reused Marvin | Remove `MANAGERS` from Emma and use private/incognito login |
| `tnsping hrdb` fails | Network files were not configured or wrong `ORACLE_HOME` | Rerun `02_configure_network.sh`; check `$ORACLE_HOME/network/admin/tnsnames.ora` |
| HR direct login succeeds | HR was not created with `NO AUTHENTICATION` | Rerun `03_create_hr_schema.sh` |

### Check Listener Services

```bash
lsnrctl status
```

Look for the PDB service:

```text
freepdb1
```

or:

```text
FREEPDB1
```

### Check The `hrdb` TNS Entry

```bash
tnsping hrdb
```

The `hrdb` descriptor should contain:

```text
TOKEN_AUTH = AZURE_INTERACTIVE
```

```text
CLIENT_ID = <Oracle Client Interactive - FREEPDB1 application ID>
```

```text
AZURE_DB_APP_ID_URI = <Application ID URI>
```

```text
TENANT_ID = <Directory tenant ID>
```

### Check Database Identity Provider Parameters

```bash
./verify_db_setup.sh
```

Or check manually:

```bash
sqlplus / as sysdba
```

```sql
ALTER SESSION SET CONTAINER = FREEPDB1;
```

```sql
SELECT name, value
  FROM v$parameter
 WHERE name IN ('identity_provider_type','identity_provider_config');
```

### Check Entra App Role Assignments

In the Azure portal, verify the Oracle Database 26ai - FREEPDB1 enterprise application has:

| User | App Role |
|---|---|
| Marvin | `EMPLOYEES` |
| Marvin | `MANAGERS` |
| Emma | `EMPLOYEES` |

If assignments changed, close existing browser sessions before testing again.

## Learn More

* [Oracle AI Database 26ai Documentation](https://docs.oracle.com/en/database/)

## Acknowledgements
* **Author** - Oracle Database Security Product Management
* **Last Updated By/Date** - April 2026
