# Identity-Aware Database Access with Microsoft Entra ID and Oracle Deep Data Security

## Introduction

This lab configures Oracle AI Database 26ai to accept Microsoft Entra ID tokens,
then uses Oracle Deep Data Security data roles and data grants to enforce
different row and column access for Marvin and Emma.

Marvin and Emma run the same SQL against the same HR table. Marvin is a manager
and sees himself plus direct reports. Emma is an employee and sees only herself.
The database enforces the difference from Entra ID app-role claims.

The detailed security notes, manual portal fallback, rollback commands, and
extended troubleshooting have been moved to
[`entra-id-data-grants-reference.md`](./entra-id-data-grants-reference.md).

Estimated Time: 60 minutes

### Objectives

In this lab, you will:

- Configure Microsoft Entra ID applications and app roles for database access.
- Configure Oracle AI Database 26ai to validate Entra ID tokens.
- Create Deep Data Security data roles and data grants.
- Verify that Marvin and Emma see different data through the same SQL.

## What This Lab Does

- Creates or reuses Microsoft Entra ID app registrations and enterprise apps.
- Creates Entra app roles `EMPLOYEES` and `MANAGERS`.
- Optionally assigns Marvin and Emma to the app roles.
- Configures Oracle AI Database 26ai for Entra ID token authentication.
- Configures a TCPS `hrdb` connection for browser-based login.
- Creates an HR schema with sample employee data.
- Creates Deep Data Security data roles and data grants.
- Verifies Marvin and Emma see different data from the same SQL.

## Assumptions

- You are running on the DBSec-Lab VM as OS user `oracle`.
- Oracle AI Database 26ai Free is installed and running.
- You can run `sqlplus / as sysdba` locally.
- You can administer the Microsoft Entra tenant used for the lab.
- Azure CLI is installed, or you can install it.
- Marvin and Emma exist in Entra ID, or your Entra admin can create them.
- Browser login is available from the lab desktop or NoVNC session.

## Important Defaults

| Setting | Default |
| --- | --- |
| CDB SID | `FREE` |
| PDB | `FREEPDB1` |
| TNS alias | `hrdb` |
| DB resource app | `Oracle Database 26ai - FREEPDB1` |
| Browser client app | `Oracle Client Interactive - FREEPDB1` |
| OAuth scope | `session:scope:connect` |
| Marvin UPN | `marvin@<DOMAIN_NAME>` |
| Emma UPN | `emma@<DOMAIN_NAME>` |
| Marvin role assignments | `EMPLOYEES`, `MANAGERS` |
| Emma role assignments | `EMPLOYEES` |

Optional overrides:

```bash
<copy>
export DB_SID=FREE
export PDB_NAME=FREEPDB1
export DOMAIN_NAME=example.onmicrosoft.com
export MARVIN_UPN=marvin@example.onmicrosoft.com
export EMMA_UPN=emma@example.onmicrosoft.com
export CREATE_APP_ROLE_ASSIGNMENTS=1
</copy>
```

Set `CREATE_APP_ROLE_ASSIGNMENTS=0` if your Entra administrator wants to assign
users to app roles manually.

## Task 0: Download The Lab Files

Open a terminal as OS user `oracle`, move to your Deep Data Security labs directory,
download the ZIP, and unzip it.

```bash
<copy>
cd $DBSEC_LABS/deep-data-security
wget -O entra-id-data-grants.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/aSXtPT18-67-gR7BdvSd5VtxmxemrI5KpRkoMYoN6S22aUhRnrB5O12ZaoXbjgLE/n/oradbclouducm/b/dbsec_public/o/entra-id-data-grants.zip
unzip -o entra-id-data-grants.zip
cd entra-id-data-grants
ls
</copy>
```

Use `unzip -o` when refreshing the lab files. Do not use `unzip -f` for lab
updates because it will not add new files.

Important files:

| File | Purpose |
| --- | --- |
| `00_preflight.sh` | Checks local database, listener tools, and browser readiness |
| `00_setup_entra_id.sh` | Creates or reuses Entra apps, roles, permissions, and assignments |
| `verify_entra_id_setup.sh` | Verifies Entra app objects and role setup |
| `01_configure_db_identity_provider.sh` | Configures database Entra ID parameters |
| `02_configure_network.sh` | Configures TCPS listener, wallet, `sqlnet.ora`, and `tnsnames.ora` |
| `03_create_hr_schema.sh` | Creates the HR schema and employee rows |
| `04_create_data_roles_and_grants.sh` | Creates data roles, data grants, and end user context |
| `verify_db_setup.sh` | Verifies database-side setup |
| `05_verify_as_marvin.sh` | Verifies Marvin manager access |
| `06_verify_as_emma.sh` | Verifies Emma employee access |
| `07_verify_security_boundary.sh` | Optional boundary checks |
| `08_cleanup.sh` | Cleans up database objects and network changes |
| `09_cleanup_entra_id.sh` | Deletes lab-created Entra app registrations and enterprise apps |

## Task 1: Install Azure CLI And Sign In

Azure CLI is required for `00_setup_entra_id.sh`.

For Oracle Linux 9:

```bash
<copy>
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo dnf install -y https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm
sudo dnf install -y azure-cli
</copy>
```

For Oracle Linux 8:

```bash
<copy>
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
sudo dnf install -y azure-cli
</copy>
```

Verify Azure CLI and sign in:

```bash
<copy>
az version
az login
az account show --query "{tenantId:tenantId,name:name,user:user.name}" --output table
</copy>
```

## Task 2: Configure Microsoft Entra ID

Create or reuse the Entra DB resource application, browser client application,
enterprise apps, app roles, scopes, and role assignments.

```bash
<copy>
./00_setup_entra_id.sh
source ./.entra-id-data-grants.env
</copy>
```

The script writes `.entra-id-data-grants.env`. Load it before running later
tasks.

Verify the Entra setup:

```bash
<copy>
./verify_entra_id_setup.sh
</copy>
```

Expected setup:

| User | App roles |
| --- | --- |
| Marvin | `EMPLOYEES`, `MANAGERS` |
| Emma | `EMPLOYEES` |

If your tenant policies prevent automated app creation or assignment, use the
manual portal fallback in
[`entra-id-data-grants-reference.md`](./entra-id-data-grants-reference.md).

## Task 3: Run Database Preflight

Load the database environment and run the preflight checks.

```bash
<copy>
source ./.entra-id-data-grants.env
./00_preflight.sh
</copy>
```

The preflight confirms the local database, PDB, SQL*Plus, listener utilities,
and browser-related environment are ready for the lab.

## Task 4: Configure The Database Identity Provider

Configure the PDB to validate Entra ID tokens.

```bash
<copy>
source ./.entra-id-data-grants.env
./01_configure_db_identity_provider.sh
</copy>
```

This task sets the database identity provider parameters from
`.entra-id-data-grants.env`. It must be run before browser-based login can work.

## Task 5: Configure TCPS Network Access

Configure the local wallet, listener, `sqlnet.ora`, and `tnsnames.ora` entry used
by browser-based Entra ID authentication.

```bash
<copy>
source ./.entra-id-data-grants.env
./02_configure_network.sh
</copy>
```

The script creates the `hrdb` TNS alias. Verification scripts connect with:

```bash
<copy>
sqlplus /@hrdb
</copy>
```

## Task 6: Create The HR Schema

Create the schema-only HR owner and sample employee data.

```bash
<copy>
source ./.entra-id-data-grants.env
./03_create_hr_schema.sh
</copy>
```

`HR` is created with `NO AUTHENTICATION`; end users do not log in as `HR`.
The `user_name` values are set to Entra ID user names such as
`marvin@<DOMAIN_NAME>` and `emma@<DOMAIN_NAME>`.

## Task 7: Create Data Roles And Data Grants

Create the Deep Data Security data roles, data grants, and end user context.

```bash
<copy>
source ./.entra-id-data-grants.env
./04_create_data_roles_and_grants.sh
</copy>
```

The script creates:

- `HRAPP_EMPLOYEES`, mapped to Entra app role `EMPLOYEES`
- `HRAPP_MANAGERS`, mapped to Entra app role `MANAGERS`
- `DIRECT_LOGON_ROLE`, carrying `CREATE SESSION`
- Row and column data grants on `HR.EMPLOYEES`
- End user context used to identify a manager's direct reports

## Task 8: Verify Database Setup

Confirm the identity provider, network alias, HR rows, data roles, and data
grants are in place.

```bash
<copy>
source ./.entra-id-data-grants.env
./verify_db_setup.sh
</copy>
```

Expected highlights:

```text
identity_provider_type    AZURE_AD
HR employee rows          7
HRAPP_EMPLOYEES           azure_role=EMPLOYEES
HRAPP_MANAGERS            azure_role=MANAGERS
```

## Task 9: Verify Marvin And Emma

Run Marvin first. When the browser opens, sign in as Marvin.

```bash
<copy>
source ./.entra-id-data-grants.env
./05_verify_as_marvin.sh
</copy>
```

Expected Marvin result:

- Token identity is Marvin.
- Active data roles include `HRAPP_EMPLOYEES` and `HRAPP_MANAGERS`.
- Marvin sees 4 rows: Marvin, Emma, Charlie, and Dana.
- Marvin can see his own SSN.
- SSN is hidden for direct reports.

Run Emma next. If the browser reuses Marvin's session, close browser windows,
sign out, or use a private/incognito browser session.

```bash
<copy>
source ./.entra-id-data-grants.env
./06_verify_as_emma.sh
</copy>
```

Expected Emma result:

- Token identity is Emma.
- Active data roles include `HRAPP_EMPLOYEES` only.
- Emma sees 1 row: Emma.
- Emma can view her own SSN and salary.
- Emma can update only her phone number.

## Task 10: Verify The Security Boundary And Clean Up

Optionally run boundary checks. These tests require separate browser logins and
careful browser-session isolation.

```bash
<copy>
source ./.entra-id-data-grants.env
./07_verify_security_boundary.sh
</copy>
```

The boundary checks confirm:

- Marvin cannot see Bob's SSN because Bob is outside Marvin's scope.
- Emma cannot update her salary.
- Emma cannot update Marvin's phone number.

Clean up database objects and restore local network files:

```bash
<copy>
./08_cleanup.sh
</copy>
```

If the Entra applications were created only for this lab, remove them too:

```bash
<copy>
./09_cleanup_entra_id.sh
</copy>
```

## Troubleshooting Summary

Detailed troubleshooting moved to
[`entra-id-data-grants-reference.md`](./entra-id-data-grants-reference.md).
Start with these checks:

```bash
<copy>
source ./.entra-id-data-grants.env
./verify_entra_id_setup.sh
./verify_db_setup.sh
tnsping hrdb
</copy>
```

Common issues:

| Symptom | Check |
| --- | --- |
| Browser logs in as the wrong user | Close browser windows, sign out, or use private/incognito mode |
| Marvin sees only his own row | Confirm Marvin has `MANAGERS`; rerun browser login |
| Emma has manager access | Remove `MANAGERS` from Emma and use a fresh browser session |
| `sqlplus /@hrdb` cannot resolve | Rerun `./02_configure_network.sh` and check `tnsping hrdb` |
| No data roles activate | Verify Entra app role assignments and database role mappings |

## Reference Material

The following sections were moved to
[`entra-id-data-grants-reference.md`](./entra-id-data-grants-reference.md):

- Do Not Do This
- Security Model
- Threat Model
- Security-Critical Claims
- Least Privilege Design
- Secrets And Session Inventory
- Browser Session Handling
- Security Validation Checklist
- DBA Production Caution
- Network File Backups And Restore
- Manual portal fallback tasks
- Rerun Safety
- Database Parameter Rollback
- Audit And Log Locations
- Troubleshooting
- Key Differences: Entra ID vs. Direct Password

## Learn More

- [Microsoft identity platform documentation](https://learn.microsoft.com/entra/identity-platform/)
- [Oracle Database integration with Microsoft Entra ID](https://docs.oracle.com/en/database/oracle/oracle-database/26/dbseg/)
- [Oracle Deep Data Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/)

## Acknowledgements

- **Author** - Richard Evans, Database Security Product Management
