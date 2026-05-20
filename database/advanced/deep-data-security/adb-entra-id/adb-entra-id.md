# ADB Microsoft Entra ID Deep Data Security Lab

This lab builds the Deep Data Security data grants demo on Autonomous Database
Serverless using Microsoft Entra ID authentication.

The database is named `deepsec7` by default so it can run separately from the
ADB OCI IAM lab database.

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
export DB_NAME=deepsec7
export DB_DISPLAY_NAME=deepsec7
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

## 0. Download and Unzip the Lab Files

Move to the Deep Data Security labs directory and download the lab archive:

```bash
<copy>
cd $DBSEC_LABS/deep-data-security
wget -O adb-entra-id.zip \
  "https://objectstorage.us-ashburn-1.oraclecloud.com/p/X-TmpjlwHTI2DWNBGAha58H-SFMol_iE5FZz7kEIPe1MKGVMFNyCHlfOwBtJgZwt/n/oradbclouducm/b/dbsec_public/o/adb-entra-id.zip"
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

If the archive creates a nested `adb-entra-id` directory, move its contents up
into the current lab directory:

```bash
<copy>
if [ -d adb-entra-id ]; then
  cp -R adb-entra-id/. .
  rm -rf adb-entra-id
fi
</copy>
```

## 1. Create ADB-S, Wallet, and Entra ID Apps

```bash
./00_setup_adb_entra_id.sh
```

Load the generated environment file:

```bash
source ./.adb-entra-id.env
```

The Entra enterprise app names include the ADB name. With the default database
name, these are:

- `Oracle Database 26ai ADB - deepsec7`
- `Oracle Client Interactive ADB - deepsec7`

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

- `HRAPP_EMPLOYEES`, mapped to `AZURE_ROLE=EMPLOYEES`
- `HRAPP_MANAGERS`, mapped to `AZURE_ROLE=MANAGERS`
- `DIRECT_LOGON_ROLE`, carrying `CREATE SESSION`
- `HR.EMP_CTX`, an end user context populated from the Entra ID user name
- HR row and column data grants

The manager grant uses `ORA_END_USER_CONTEXT.HR.EMP_CTX.ID` to resolve the
current Entra ID user to an employee ID. The setup grants
`UPDATE ANY END USER CONTEXT` to `HR` so the context handler can populate
`HR.EMP_CTX` on first read.

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

## 8. Verify Data Grants as Emma

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

To delete the Entra app registrations from the command line:

```bash
./08_cleanup_entra_id.sh
```

To skip the prompt:

```bash
./08_cleanup_entra_id.sh --DELETE
```

## References

- [Install Azure CLI on Linux](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux)
- [Enable Microsoft Entra ID Authentication on Autonomous Database](https://docs.public.content.oci.oraclecloud.com/iaas/autonomous-database-serverless/doc/manage-users-azure-ad.html)
- [DBMS_CLOUD_ADMIN package](https://docs.oracle.com/en/cloud/paas/autonomous-database/dedicated/adbaa/dbmscloudadmin-package.html)
- [Oracle Net `TOKEN_AUTH` parameter](https://docs.oracle.com/en/database/oracle/oracle-database/26/netrf/local-naming-parameters-in-tns-ora-file.html)
- [Oracle Deep Data Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/oracle-deep-data-security-guide.pdf)
