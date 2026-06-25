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
- Configures SQL*Plus with `TOKEN_AUTH=OAUTH` and a local Entra access token.
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
<copy>
export OCI_COMPARTMENT=my-compartment
</copy>
```

To use the root compartment:

```bash
<copy>
export OCI_COMPARTMENT=root
</copy>
```

You can also use a compartment OCID directly:

```bash
<copy>
export ROOT_COMP_ID=ocid1.compartment.oc1..aaaa...
</copy>
```

Optional overrides:

```bash
<copy>
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
</copy>
```

By default, `MARVIN_UPN` is the signed-in Azure Cloud Shell user. The Azure
setup script assigns that user to the `EMPLOYEES` and `MANAGERS` app roles, and
the Oracle setup creates Marvin's HR row with that UPN. This makes the
verification step runnable without pre-creating a separate Marvin account.

`ADB_IS_FREE_TIER` defaults to `true`. Always Free Autonomous AI Database does
not accept the `--license-model` create option. If you need a paid database,
set these before running `00_setup_adb_entra_id.sh`:

```bash
<copy>
export ADB_IS_FREE_TIER=false
export ADB_LICENSE_MODEL=LICENSE_INCLUDED
</copy>
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
| `04_get_entra_oauth_token.sh` | Gets a Microsoft Entra OAuth2 token for the signed-in user |
| `04_configure_azure_interactive.sh` | Compatibility wrapper for `04_get_entra_oauth_token.sh` |
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
| Task 6: Get a Microsoft Entra OAuth2 access token | `04_get_entra_oauth_token.sh` |
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
resource. The interactive client application is the public client used by the
authorization-code flow. The app roles are included in the issued token and are
mapped to database data roles with
`AZURE_ROLE=...`.

## Task 2: Enable Entra ID on Autonomous AI Database

```bash
<copy>
./01_enable_entra_id.sh
</copy>
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
<copy>
./02_create_hr_schema.sh
</copy>
```

The HR schema is created with `NO AUTHENTICATION`. It owns the data, but users do
not log in as `HR`.

## Task 4: Create Data Roles and Data Grants

```bash
<copy>
./03_create_data_roles_and_grants.sh
</copy>
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
<copy>
./verify_db_setup.sh
</copy>
```

This confirms that Entra ID is enabled, the HR rows exist, and the data roles are
mapped.

## Task 6: Get a Microsoft Entra OAuth2 Access Token

Use `--headless` in Oracle Cloud Shell. This prints a Microsoft Entra login URL
and prompts you to paste the final localhost callback URL.

> **Important:** This task uses two browser contexts. Keep Oracle Cloud Shell
> open in its current browser tab. Copy the printed login URL into a separate
> private window, incognito window, separate browser profile, or different
> browser. Sign in there as the demo user. The final
> `localhost:8888/callback?...` page will usually fail to load. That is
> expected. Copy the entire localhost URL from the browser address bar and paste
> it back into Oracle Cloud Shell.

```bash
<copy>
./04_get_entra_oauth_token.sh --headless
</copy>
```

This configures `sqlnet.ora` using:

```text
TOKEN_AUTH=OAUTH
TOKEN_LOCATION=$HOME/.azure/adb-entra-id
```

Then it starts the Microsoft Entra OAuth2 authorization-code flow for the user
you sign in as. The token helper uses the values from `.adb-entra-id.env`:

```bash
<copy>
source ./.adb-entra-id.env
</copy>
```

The login flow for the verification tasks is:

- The token helper prints a Microsoft Entra login URL.
- You paste the login URL into a separate browser session and sign in as Marvin
  or Emma.
- The browser redirects to `http://localhost:8888/callback?...`. The page will
  usually fail to load because the browser is outside Oracle Cloud Shell.
- You copy the entire localhost callback URL from the browser address bar and
  paste it back into Oracle Cloud Shell.
- The token helper exchanges the authorization code for an access token and
  writes it to `$HOME/.azure/adb-entra-id/token`.
- SQL*Plus reads that token through `TOKEN_AUTH=OAUTH`.
- Autonomous AI Database validates the token and maps Entra app-role claims to
  data roles such as `AZURE_ROLE=EMPLOYEES`.

## Task 7: Verify Data Grants as Marvin

```bash
<copy>
./05_verify_as_marvin.sh
</copy>
```

The script connects with the token from Task 6:

```bash
<copy>
sqlplus -L -s /@${ADB_SERVICE}
</copy>
```

If you need a fresh Marvin token, remove the existing token and rerun Task 6:

```bash
<copy>
rm -f ${AZURE_TOKEN_DIR:-$HOME/.azure/adb-entra-id}/token
./04_get_entra_oauth_token.sh --headless
</copy>
```

You should see:

- The authenticated Entra ID identity.
- Active data roles from Entra app role mappings.
- Marvin's own HR row with SSN visible.
- Marvin's direct reports with SSN hidden.

## Task 8: Verify Data Grants as Emma

Before testing Emma, clear Marvin's token and get a fresh token as `EMMA_UPN`:

```bash
<copy>
rm -f ${AZURE_TOKEN_DIR:-$HOME/.azure/adb-entra-id}/token
./04_get_entra_oauth_token.sh --headless
</copy>
```

Then verify Emma's data grants:

```bash
<copy>
./06_verify_as_emma.sh
</copy>
```

You should see:

- The authenticated Entra ID identity for Emma.
- Active data roles from the `EMPLOYEES` app role.
- Emma's own HR row only.
- Emma can view her SSN and salary but cannot update salary.

## Clean Up

To remove the database objects:

```bash
<copy>
./07_cleanup_adb_lab.sh
</copy>
```

To skip the prompt:

```bash
<copy>
./07_cleanup_adb_lab.sh --DELETE
</copy>
```

To delete the ADB instance too:

```bash
<copy>
./07_cleanup_adb_lab.sh --delete-adb
</copy>
```

This cleanup script does not delete the Entra app registrations. Reusing them is
usually safer while iterating on the lab. Delete them from Entra ID when you are
done with the environment.

To remove local Microsoft Entra OAuth2 tokens:

```bash
<copy>
rm -rf ${AZURE_TOKEN_DIR:-$HOME/.azure/adb-entra-id}
</copy>
```

To delete the Entra app registrations from the command line, run this in Azure
Cloud Shell from the `adb-entra-id` directory that contains
`.adb-entra-id.azure.env`:

```bash
<copy>
./08_cleanup_entra_id.sh
</copy>
```

To skip the prompt:

```bash
<copy>
./08_cleanup_entra_id.sh --DELETE
</copy>
```

## References

- [Azure Cloud Shell overview](https://learn.microsoft.com/en-us/azure/cloud-shell/overview)
- [Enable Microsoft Entra ID Authentication on Autonomous Database](https://docs.public.content.oci.oraclecloud.com/iaas/autonomous-database-serverless/doc/manage-users-azure-ad.html)
- [DBMS_CLOUD_ADMIN package](https://docs.oracle.com/en/cloud/paas/autonomous-database/dedicated/adbaa/dbmscloudadmin-package.html)
- [Oracle Net `TOKEN_AUTH` parameter](https://docs.oracle.com/en/database/oracle/oracle-database/26/netrf/local-naming-parameters-in-tns-ora-file.html)
- [Oracle Deep Data Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/oracle-deep-data-security-guide.pdf)

## Acknowledgements

- **Author** - Richard Evans, Oracle
