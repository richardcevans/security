# ADB Microsoft Entra ID Deep Data Security Lab

This lab builds the Deep Data Security data grants demo on Autonomous Database
Serverless using Microsoft Entra ID authentication.

The first database is named `deepsec1` by default.

## What This Lab Does

- Creates or reuses an ADB-S instance.
- Downloads the ADB client wallet into Cloud Shell.
- Creates Microsoft Entra ID database/resource and interactive client app registrations.
- Assigns the current Azure CLI user to the Entra app roles used by the lab.
- Enables Entra ID authentication with `DBMS_CLOUD_ADMIN` as `ADMIN`.
- Creates the HR demo schema and Deep Data Security data grants.
- Configures the ADB wallet with `TOKEN_AUTH=AZURE_INTERACTIVE`.
- Verifies the same SQL returns only the rows and columns authorized for the Entra user.

## Assumptions

- You are running from OCI Cloud Shell.
- OCI CLI is available and authenticated by Cloud Shell.
- Azure CLI is installed and you have run `az login`.
- SQL*Plus or SQLcl is available.
- Your OCI user can create Autonomous Databases in the target compartment.
- Your Entra user can create app registrations, service principals, app roles, scopes, and app role assignments.

## Install Azure CLI

OCI Cloud Shell may not include Azure CLI. On Oracle Linux, use Microsoft's RPM
repository instructions:

```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo dnf install -y https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm
sudo dnf install -y azure-cli
```

Then sign in:

```bash
az login
```

If Cloud Shell cannot open a browser, Azure CLI will show a device-code login
URL and code. Complete that flow in your local browser.

## Variables

Set the target OCI compartment:

```bash
export ROOT_COMP_ID=ocid1.compartment.oc1..aaaa...
```

Optional overrides:

```bash
export DB_NAME=deepsec1
export DB_DISPLAY_NAME=deepsec1
export ADMIN_PWD='Oracle123+Oracle123+'
export WALLET_PWD='Oracle123+'
export DOMAIN_NAME=example.onmicrosoft.com
export MARVIN_UPN=your.user@example.com
export EMMA_UPN=emma@example.com
```

By default, `MARVIN_UPN` is the current `az login` user. The script assigns that
user to the `EMPLOYEES` and `MANAGERS` app roles and creates Marvin's HR row with
that UPN. This makes the verification step runnable without pre-creating a
separate Marvin account.

## 1. Create ADB-S, Wallet, and Entra ID Apps

```bash
./00_setup_adb_entra_id.sh
```

Load the generated environment file:

```bash
source ./.adb-entra-id.env
```

The Entra enterprise app names include the ADB name:

- `Oracle Database 26ai ADB - deepsec1`
- `Oracle Client Interactive ADB - deepsec1`

## 2. Enable Entra ID on ADB

```bash
./01_enable_entra_id.sh
```

ADB does not use a SYS connection for this. The script connects as `ADMIN` and runs
`DBMS_CLOUD_ADMIN.ENABLE_EXTERNAL_AUTHENTICATION` with:

- `type => 'AZURE_AD'`
- `tenant_id`
- `application_id`
- `application_id_uri`

## 3. Create the HR Schema

```bash
./02_create_hr_schema.sh
```

The HR schema is created with `NO AUTHENTICATION`. It owns the data, but users do
not log in as `HR`.

## 4. Create Data Roles and Data Grants

```bash
./03_create_data_roles_and_grants.sh
```

The script creates:

- `ENTRA_SHARED_SCHEMA`, mapped to `AZURE_ROLE=EMPLOYEES`
- `HRAPP_EMPLOYEES`, mapped to `AZURE_ROLE=EMPLOYEES`
- `HRAPP_MANAGERS`, mapped to `AZURE_ROLE=MANAGERS`
- `DIRECT_LOGON_ROLE`, carrying `CREATE SESSION`
- HR row and column data grants

## 5. Verify the ADMIN-Side Setup

```bash
./verify_db_setup.sh
```

This confirms that Entra ID is enabled, the HR rows exist, and the data roles are
mapped.

## 6. Configure the ADB Wallet for Entra Interactive Login

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

## 7. Verify Data Grants as Marvin

```bash
./05_verify_as_marvin.sh
```

The script connects with:

```bash
sqlplus /@hrdb_entra
```

If SQL*Plus has desktop or NoVNC browser access, the Entra login should open
automatically. In a headless Cloud Shell session, the Oracle client may print a
URL or device-flow prompt. Complete that login as `MARVIN_UPN`.

You should see:

- The authenticated Entra ID identity.
- Active data roles from Entra app role mappings.
- Marvin's own HR row with SSN visible.
- Marvin's direct reports with SSN hidden.

## Clean Up

To remove the database objects:

```bash
./06_cleanup_adb_lab.sh
```

To skip the prompt:

```bash
./06_cleanup_adb_lab.sh --DELETE
```

To delete the ADB instance too:

```bash
./06_cleanup_adb_lab.sh --delete-adb
```

This cleanup script does not delete the Entra app registrations. Reusing them is
usually safer while iterating on the lab. Delete them from Entra ID when you are
done with the environment.

To delete the Entra app registrations from the command line:

```bash
./07_cleanup_entra_id.sh
```

To skip the prompt:

```bash
./07_cleanup_entra_id.sh --DELETE
```

## References

- [Install Azure CLI on Linux](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux)
- [Enable Microsoft Entra ID Authentication on Autonomous Database](https://docs.public.content.oci.oraclecloud.com/iaas/autonomous-database-serverless/doc/manage-users-azure-ad.html)
- [DBMS_CLOUD_ADMIN package](https://docs.oracle.com/en/cloud/paas/autonomous-database/dedicated/adbaa/dbmscloudadmin-package.html)
- [Oracle Net `TOKEN_AUTH` parameter](https://docs.oracle.com/en/database/oracle/oracle-database/26/netrf/local-naming-parameters-in-tns-ora-file.html)
- [Oracle Deep Data Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/oracle-deep-data-security-guide.pdf)
