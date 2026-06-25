# Autonomous AI Database Microsoft Entra ID Deep Data Security Lab

This lab builds the Deep Data Security data grants demo on Autonomous AI
Database Serverless 26ai using Microsoft Entra ID authentication.

The database name starts with `deepsec7` by default and adds a short
machine-instance suffix so multiple DBSec-Lab environments can share the same
OCI compartment and Entra tenant without name collisions.

### Objectives

In this lab, you will:

- Create an Autonomous AI Database Serverless instance for the demo.
- Configure Microsoft Entra ID authentication for the database.
- Create Deep Data Security data roles and data grants.
- Verify end-user access through Entra-authenticated database sessions.

> **Warning:** Run this lab only in an isolated demo, sandbox, or non-production environment. The steps can create or modify identity applications, users, groups, database identity-provider settings, network files, data roles, data grants, audit policies, and other security configuration. Do not run the lab against production tenancies, tenants, databases, applications, or directories, and do not overwrite existing policies or configuration. Follow your organization's change control, approval, and security procedures before adapting any step outside a lab environment.

Estimated Time: 60 minutes

## Introduction

- Creates or reuses an Autonomous AI Database Serverless instance.
- Downloads the ADB client wallet into Oracle Cloud Shell.
- Creates Microsoft Entra ID database/resource and interactive client app registrations from Azure Cloud Shell.
- Assigns the signed-in Azure Cloud Shell user to the Entra app roles used by the lab.
- Enables Entra ID authentication with `DBMS_CLOUD_ADMIN` as `ADMIN`.
- Creates the HR demo schema and Deep Data Security data grants.
- Configures the ADB wallet with `TOKEN_AUTH=AZURE_INTERACTIVE`.
- Verifies the same SQL returns only the rows and columns authorized for the Entra user.

## Assumptions

- You use Azure Cloud Shell for all Microsoft Entra ID and Azure CLI commands.
- You use Oracle Cloud Shell for all OCI CLI, Autonomous Database, wallet, and SQL commands.
- OCI CLI is available and authenticated by Oracle Cloud Shell.
- Azure CLI is available in Azure Cloud Shell.
- SQL*Plus or SQLcl is available.
- Your OCI user can create Autonomous AI Databases in the target compartment.
- Your Entra user can create app registrations, service principals, app roles, scopes, and app role assignments.

## Use Two Cloud Shell Sessions

This lab intentionally uses two browser tabs:

- **Azure Cloud Shell** runs the Microsoft Entra ID app-registration commands.
- **Oracle Cloud Shell** runs the OCI, Autonomous Database, wallet, and SQL commands.

Do not install Azure CLI in Oracle Cloud Shell. Azure Cloud Shell already
includes Azure CLI and is the expected place to run `az` commands in this lab.

## Variables

Set the target OCI compartment by name:

```bash
export OCI_COMPARTMENT=my-compartment
```

To use the root compartment:

```bash
export OCI_COMPARTMENT=root
```

You can also use a compartment OCID directly:

```bash
export ROOT_COMP_ID=ocid1.compartment.oc1..aaaa...
```

Optional overrides:

```bash
export DB_NAME=deepsec7abc123
export DB_DISPLAY_NAME=deepsec7abc123
export DB_VERSION=26ai
export ADB_IS_FREE_TIER=true
export ADMIN_PWD='Oracle123+Oracle123+'
export WALLET_PWD='Oracle123+'
export DOMAIN_NAME=example.onmicrosoft.com
export ADB_ENTRA_LAB_INSTANCE_ID=dbsec-lab-148abe-ef143e
export MARVIN_UPN=your.user@example.com
export EMMA_UPN=emma@example.com
```

By default, `MARVIN_UPN` is the signed-in Azure Cloud Shell user. The Azure
setup script assigns that user to the `EMPLOYEES` and `MANAGERS` app roles, and
the Oracle setup creates Marvin's HR row with that UPN. This makes the
verification step runnable without pre-creating a separate Marvin account.

`ADB_IS_FREE_TIER` defaults to `true`. Always Free Autonomous AI Database does
not accept the `--license-model` create option. If you need a paid database,
set these before running `00_setup_adb_entra_id.sh`:

```bash
export ADB_IS_FREE_TIER=false
export ADB_LICENSE_MODEL=LICENSE_INCLUDED
```

By default, `00_create_entra_apps_azure_cloud_shell.sh` generates a lab instance
ID and writes it to `.adb-entra-id.azure.env`. Copy that file into Oracle Cloud
Shell before running `00_setup_adb_entra_id.sh`. The default `DB_NAME` is
`deepsec7<short-instance-suffix>`, such as `deepsec7ef143e`.

## Task 0: Download and Unzip the Lab Files

In Oracle Cloud Shell, move to the Deep Data Security labs directory and
download the lab archive:

```bash
<copy>
mkdir -vp $DBSEC_LABS/deep-data-security
cd $DBSEC_LABS/deep-data-security
wget -O adb-entra-id.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/X-TmpjlwHTI2DWNBGAha58H-SFMol_iE5FZz7kEIPe1MKGVMFNyCHlfOwBtJgZwt/n/oradbclouducm/b/dbsec_public/o/adb-entra-id.zip
</copy>
```

Unzip the archive into the `adb-entra-id` directory. Use `-o`, not `-f`, so new
files from an updated archive are added:

```bash
<copy>
unzip -o adb-entra-id.zip
cd adb-entra-id
</copy>
```

You should see the setup and verification scripts used by the remaining tasks.
Important files include:

| File | Purpose |
| --- | --- |
| `00_create_entra_apps_azure_cloud_shell.sh` | Runs in Azure Cloud Shell to create Entra apps, app roles, app role assignments, and `.adb-entra-id.azure.env` |
| `00_setup_adb_entra_id.sh` | Runs in Oracle Cloud Shell to create Autonomous Database, wallet, and `.adb-entra-id.env` |
| `01_enable_entra_id.sh` | Enables Microsoft Entra ID authentication on Autonomous Database |
| `02_create_hr_schema.sh` | Creates the HR schema and sample employee rows |
| `03_create_data_roles_and_grants.sh` | Creates data roles and data grants |
| `04_configure_azure_interactive.sh` | Configures the wallet alias for Entra interactive login |
| `05_verify_as_marvin.sh` | Verifies manager access for Marvin |
| `06_verify_as_emma.sh` | Verifies employee access for Emma |
| `verify_db_setup.sh` | Verifies the ADMIN-side database setup |
| `07_cleanup_adb_lab.sh` | Removes lab database objects and optional Autonomous Database resources |
| `08_cleanup_entra_id.sh` | Removes lab-created Microsoft Entra ID applications |

The script numbers are the execution order after the lab files are downloaded.
They are not the same as the LiveLabs task numbers because Task 0 is the
download step, Task 1 has one Azure Cloud Shell script and one Oracle Cloud
Shell script, and Entra cleanup is optional after the verification tasks.

| LiveLabs task | Script |
| --- | --- |
| Task 0: Download and unzip the lab files | No setup script |
| Task 1: Create Entra ID apps, Autonomous AI Database, and wallet | `00_create_entra_apps_azure_cloud_shell.sh`, `00_setup_adb_entra_id.sh` |
| Task 2: Enable Entra ID on Autonomous AI Database | `01_enable_entra_id.sh` |
| Task 3: Create the HR schema | `02_create_hr_schema.sh` |
| Task 4: Create data roles and data grants | `03_create_data_roles_and_grants.sh` |
| Task 5: Verify the ADMIN-side setup | `verify_db_setup.sh` |
| Task 6: Configure the wallet for Entra interactive login | `04_configure_azure_interactive.sh` |
| Task 7: Verify data grants as Marvin | `05_verify_as_marvin.sh` |
| Task 8: Verify data grants as Emma | `06_verify_as_emma.sh` |
| Cleanup after the lab | `07_cleanup_adb_lab.sh`, `08_cleanup_entra_id.sh` |

## Task 1: Create Entra ID Apps, Autonomous AI Database, and Wallet

In Azure Cloud Shell, download the same lab archive and run the Entra setup
script:

```bash
<copy>
mkdir -vp ~/adb-entra-id-lab
cd ~/adb-entra-id-lab
wget -O adb-entra-id.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/X-TmpjlwHTI2DWNBGAha58H-SFMol_iE5FZz7kEIPe1MKGVMFNyCHlfOwBtJgZwt/n/oradbclouducm/b/dbsec_public/o/adb-entra-id.zip
unzip -o adb-entra-id.zip
cd adb-entra-id
./00_create_entra_apps_azure_cloud_shell.sh
</copy>
```

The Azure setup script creates `.adb-entra-id.azure.env` and prints a complete
`cat > .adb-entra-id.azure.env <<'EOF'` block.

Return to Oracle Cloud Shell. In the `adb-entra-id` lab directory, paste and run
the complete block printed by Azure Cloud Shell. This creates the Azure
environment file that the Oracle setup script needs.

Then create or reuse Autonomous AI Database and download the wallet:

```bash
<copy>
./00_setup_adb_entra_id.sh
</copy>
```

Load the generated environment file:

```bash
<copy>
source ./.adb-entra-id.env
</copy>
```

The Entra enterprise app names include the ADB name and the machine-instance
suffix:

- `Oracle Database 26ai ADB - <DB_NAME> - <machine-instance-id>`
- `Oracle Client Interactive ADB - <DB_NAME> - <machine-instance-id>`

The Azure Cloud Shell setup script creates or reuses:

- Microsoft Entra database resource application
- Microsoft Entra public interactive client application
- Entra app roles `EMPLOYEES` and `MANAGERS`
- Optional app role assignments for Marvin and Emma

The Oracle Cloud Shell setup script creates or reuses:

- Autonomous AI Database `deepsec7<short-instance-suffix>`
- Database wallet `$HOME/adb_wallet/<DB_NAME>-entra`
- Combined `.adb-entra-id.env` file used by the remaining Oracle Cloud Shell scripts

The database resource application represents Autonomous AI Database as an OAuth
resource. The interactive client application is the public client used by
SQL*Plus when it starts the browser-based Entra sign-in flow. The app roles are
included in the issued token and are mapped to database data roles with
`AZURE_ROLE=...`.

## Task 2: Enable Entra ID on Autonomous AI Database

```bash
./01_enable_entra_id.sh
```

ADB does not use a SYS connection for this. The script connects as `ADMIN` and runs
`DBMS_CLOUD_ADMIN.ENABLE_EXTERNAL_AUTHENTICATION` with:

- `type => 'AZURE_AD'`
- `tenant_id`
- `application_id`
- `application_id_uri`

This configures Autonomous AI Database to validate Microsoft Entra ID tokens for
the database resource application created in Task 1. Users do not type database
passwords for Marvin or Emma. They sign in to Entra ID, and Autonomous AI
Database uses the token claims to activate mapped data roles.

## Task 3: Create the HR Schema

```bash
./02_create_hr_schema.sh
```

The HR schema is created with `NO AUTHENTICATION`. It owns the data, but users do
not log in as `HR`.

## Task 4: Create Data Roles and Data Grants

```bash
./03_create_data_roles_and_grants.sh
```

The script creates:

- `HRAPP_EMPLOYEES`, mapped to `AZURE_ROLE=EMPLOYEES`
- `HRAPP_MANAGERS`, mapped to `AZURE_ROLE=MANAGERS`
- `DIRECT_LOGON_ROLE`, carrying `CREATE SESSION`
- `HR.EMP_CTX`, an end user context populated from the Entra ID user name
- HR row and column data grants

The manager grant uses `ORA_END_USER_CONTEXT.HR.EMP_CTX.ID` to resolve the
current Entra ID user to an employee ID. The setup grants
`UPDATE ANY END USER CONTEXT` to `HR` so the context handler can populate
`HR.EMP_CTX` on first read.

## Task 5: Verify the ADMIN-Side Setup

```bash
./verify_db_setup.sh
```

This confirms that Entra ID is enabled, the HR rows exist, and the data roles are
mapped.

## Task 6: Configure the ADB Wallet for Entra Interactive Login

```bash
./04_configure_azure_interactive.sh
```

This adds a new wallet alias named `hrdb_entra` using:

```text
TOKEN_AUTH=AZURE_INTERACTIVE
CLIENT_ID=<interactive-client-app-id>
AZURE_DB_APP_ID_URI=<database-resource-app-id-uri>
TENANT_ID=<tenant-id>
```

The login flow for the verification tasks is:

- SQL*Plus connects to the `hrdb_entra` wallet alias.
- The Oracle client sees `TOKEN_AUTH=AZURE_INTERACTIVE`.
- The Oracle client starts an Entra ID interactive login for the configured
  client application and database resource URI.
- Entra ID returns a token for the signed-in user.
- Autonomous AI Database validates the token and maps Entra app-role claims to
  data roles such as `AZURE_ROLE=EMPLOYEES`.

## Task 7: Verify Data Grants as Marvin

```bash
./05_verify_as_marvin.sh
```

The script connects with:

```bash
sqlplus /@hrdb_entra
```

If SQL*Plus has desktop or NoVNC browser access, the Entra login should open
automatically. In a headless Oracle Cloud Shell session, the Oracle client may
print a URL or device-flow prompt. Complete that login as `MARVIN_UPN`.

You should see:

- The authenticated Entra ID identity.
- Active data roles from Entra app role mappings.
- Marvin's own HR row with SSN visible.
- Marvin's direct reports with SSN hidden.

## Task 8: Verify Data Grants as Emma

```bash
./06_verify_as_emma.sh
```

Sign in as `EMMA_UPN` when prompted. If you are reusing the same browser from
the Marvin test, sign out first or use a private browser session so SQL*Plus
receives Emma's token.

You should see:

- The authenticated Entra ID identity for Emma.
- Active data roles from the `EMPLOYEES` app role.
- Emma's own HR row only.
- Emma can view her SSN and salary but cannot update salary.

## Clean Up

To remove the database objects:

```bash
./07_cleanup_adb_lab.sh
```

To skip the prompt:

```bash
./07_cleanup_adb_lab.sh --DELETE
```

To delete the ADB instance too:

```bash
./07_cleanup_adb_lab.sh --delete-adb
```

This cleanup script does not delete the Entra app registrations. Reusing them is
usually safer while iterating on the lab. Delete them from Entra ID when you are
done with the environment.

To delete the Entra app registrations from the command line, run this in Azure
Cloud Shell from the `adb-entra-id` directory that contains
`.adb-entra-id.azure.env`:

```bash
./08_cleanup_entra_id.sh
```

To skip the prompt:

```bash
./08_cleanup_entra_id.sh --DELETE
```

## References

- [Azure Cloud Shell overview](https://learn.microsoft.com/en-us/azure/cloud-shell/overview)
- [Enable Microsoft Entra ID Authentication on Autonomous Database](https://docs.public.content.oci.oraclecloud.com/iaas/autonomous-database-serverless/doc/manage-users-azure-ad.html)
- [DBMS_CLOUD_ADMIN package](https://docs.oracle.com/en/cloud/paas/autonomous-database/dedicated/adbaa/dbmscloudadmin-package.html)
- [Oracle Net `TOKEN_AUTH` parameter](https://docs.oracle.com/en/database/oracle/oracle-database/26/netrf/local-naming-parameters-in-tns-ora-file.html)
- [Oracle Deep Data Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/oracle-deep-data-security-guide.pdf)

## Acknowledgements

- **Author** - Richard Evans, Oracle
