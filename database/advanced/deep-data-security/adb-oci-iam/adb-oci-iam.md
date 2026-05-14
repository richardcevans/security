# ADB OCI IAM Deep Data Security Lab

This lab builds the Deep Data Security data grants demo on Autonomous Database
Serverless using OCI IAM authentication.

The first database is named `deepsec1` by default.

## What This Lab Does

- Creates or reuses an ADB-S instance.
- Downloads the ADB client wallet into Cloud Shell.
- Enables OCI IAM authentication with `DBMS_CLOUD_ADMIN` as `ADMIN`.
- Creates the HR demo schema and Deep Data Security data grants.
- Maps OCI IAM groups to database data roles.
- Configures SQL*Plus to use an OCI IAM `db-token`.
- Verifies the same SQL returns only the rows and columns authorized for the IAM user.

## Assumptions

- You are running from OCI Cloud Shell.
- OCI CLI is already available and authenticated by Cloud Shell.
- SQL*Plus or SQLcl is available in Cloud Shell.
- Your OCI user can create Autonomous Databases in the target compartment.
- Your OCI user can create IAM groups or reuse existing IAM groups.
- You know the compartment name where the ADB-S instance should be created, or
  you want to use the root compartment.
- The lab can run in an Always Free tenancy when Always Free ADB resources are
  available. To confirm whether your tenancy is Free Trial, Always Free, or paid,
  check the OCI Console under your profile menu and tenancy or billing details.
  The OCI CLI can confirm tenancy access, but it usually does not identify the
  billing type directly.

## Lab Variables

Set the target compartment by name before running the lab:

```bash
export OCI_COMPARTMENT=my-compartment
```

To use the root compartment, set:

```bash
export OCI_COMPARTMENT=root
```

You can also pass the compartment to the setup script directly:

```bash
./00_setup_adb.sh my-compartment
```

If neither `OCI_COMPARTMENT` nor `ROOT_COMP_ID` is set, the setup script assumes
`OCI_COMPARTMENT=root`.

If you prefer to use a compartment OCID directly, set:

```bash
export ROOT_COMP_ID=ocid1.compartment.oc1..aaaa...
```

Optional overrides:

```bash
export DB_NAME=deepsec1
export DB_DISPLAY_NAME=deepsec1
export ADMIN_PWD='Oracle123+Oracle123+'
export WALLET_PWD='Oracle123+'
export OCI_IAM_SCHEMA_GROUP=ALL_DB_USERS
export OCI_IAM_EMPLOYEE_GROUP=EMPLOYEES
export OCI_IAM_MANAGER_GROUP=MANAGERS
```

If Cloud Shell does not expose `OCI_CS_USER_OCID`, set the user OCID explicitly:

```bash
export ADB_LAB_USER_OCID=ocid1.user.oc1..aaaa...
```

`00_setup_adb.sh` uses that user as the lab's Marvin identity. Marvin's HR row is
created with the OCI IAM database user name for that user, so the verification step
can run with your current Cloud Shell token.

## 0. Download and Unzip the Lab Files

From the `database/advanced/deep-data-security` directory, download the lab archive:

```bash
curl -L \
  "https://objectstorage.us-ashburn-1.oraclecloud.com/p/I8jdPFHveSlA1k1VemPIEHJuXIQtX8mq8BKi9rJbiCJ8YcxcY1pSwlSchZomVDPq/n/oradbclouducm/b/dbsec_public/o/adb-oci-iam.zip" \
  -o adb-oci-iam.zip
```

Or, from a remote shell, use `wget -O` to save the archive with a clean file name:

```bash
wget -O adb-oci-iam.zip \
  "https://objectstorage.us-ashburn-1.oraclecloud.com/p/I8jdPFHveSlA1k1VemPIEHJuXIQtX8mq8BKi9rJbiCJ8YcxcY1pSwlSchZomVDPq/n/oradbclouducm/b/dbsec_public/o/adb-oci-iam.zip"
```

Unzip the archive into the `adb-oci-iam` directory:

```bash
unzip -o adb-oci-iam.zip
cd adb-oci-iam
```

If the archive creates a nested `adb-oci-iam` directory, move its contents up into
the current lab directory:

```bash
if [ -d adb-oci-iam ]; then
  cp -R adb-oci-iam/. .
  rm -rf adb-oci-iam
fi
```

Verify the extracted lab files:

```bash
ls
```

You should see the setup and verification scripts used by the remaining tasks.

## 1. Create ADB-S and Download the Wallet

```bash
./00_setup_adb.sh
```

Load the generated environment file:

```bash
source ./.adb-oci-iam.env
```

This script creates or reuses:

- ADB-S database: `deepsec1`
- ADB wallet: `$HOME/adb_wallet/deepsec1`
- IAM groups: `ALL_DB_USERS`, `EMPLOYEES`, `MANAGERS`

When `OCI_CS_USER_OCID` or `ADB_LAB_USER_OCID` is available, the script also adds
that IAM user to all three lab groups.

## 2. Enable OCI IAM on ADB

```bash
./01_enable_oci_iam.sh
```

ADB does not use a SYS connection for this. The script connects as `ADMIN` and runs:

```sql
BEGIN
  DBMS_CLOUD_ADMIN.ENABLE_EXTERNAL_AUTHENTICATION(
    type  => 'OCI_IAM',
    force => TRUE
  );
END;
/
```

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

- `IAM_SHARED_SCHEMA`, mapped to `IAM_GROUP_NAME=ALL_DB_USERS`
- `HRAPP_EMPLOYEES`, mapped to `IAM_OAUTH_GROUP=EMPLOYEES`
- `HRAPP_MANAGERS`, mapped to `IAM_OAUTH_GROUP=MANAGERS`
- `DIRECT_LOGON_ROLE`, carrying `CREATE SESSION`
- HR row and column data grants

## 5. Verify the ADMIN-Side Setup

```bash
./verify_db_setup.sh
```

This confirms that OCI IAM is enabled, the HR rows exist, and the data roles are
mapped.

## 6. Get an OCI IAM db-token

```bash
./04_get_iam_db_token.sh
```

This script updates the ADB wallet `sqlnet.ora` with:

```text
TOKEN_AUTH=OCI_TOKEN
```

Then it runs:

```bash
oci iam db-token get
```

In Cloud Shell, this uses the Cloud Shell delegation token for your current OCI
user. The database client reads the resulting token from the default location:

```text
$HOME/.oci/db-token
```

## 7. Verify Data Grants as the OCI IAM User

```bash
./05_verify_as_cloud_shell_user.sh
```

The script connects with:

```bash
sqlplus /@${ADB_SERVICE}
```

You should see:

- The authenticated OCI IAM identity.
- Active roles from IAM group mappings.
- Marvin's own HR row with SSN visible.
- Marvin's direct reports with SSN hidden.

## Clean Up Local Tokens

To remove local OCI IAM database tokens:

```bash
rm -rf "$HOME/.oci/db-token"
```

This removes the local token cache only. It does not change the OCI IAM user,
groups, ADB instance, wallet, or database objects.

## Clean Up the Lab

To remove the HR schema, shared IAM schema, lab roles, data roles, and data grants:

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

The cleanup script does not delete IAM groups by default. In shared tenancies,
groups are often reused by other labs or policies.

## References

- [Enable OCI IAM authentication on Autonomous Database](https://docs.public.content.oci.oraclecloud.com/en-us/iaas/autonomous-database-serverless/doc/enable-iam-authentication.html)
- [Connect to Autonomous Database with OCI IAM authentication](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/iam-access-database.html)
- [Oracle Deep Data Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/oracle-deep-data-security-guide.pdf)
