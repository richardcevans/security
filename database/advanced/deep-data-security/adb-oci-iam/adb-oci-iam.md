# ADB OCI IAM Deep Data Security Lab

This lab builds the Deep Data Security data grants demo on Autonomous Database
Serverless 26ai using OCI IAM authentication.

The first database is named `deepsec1` by default.

## What This Lab Does

- Creates or reuses an ADB-S 26ai instance.
- Downloads the ADB client wallet into Cloud Shell.
- Enables OCI IAM authentication with `DBMS_CLOUD_ADMIN` as `ADMIN`.
- Creates the HR demo schema and Deep Data Security data grants.
- Maps OCI IAM groups to database data roles.
- Configures SQL*Plus to use the current user's OCI IAM OAuth2 access token.
- Verifies the same SQL returns only the rows and columns authorized for the IAM user.

## Assumptions

- You are running from OCI Cloud Shell.
- OCI CLI is already available and authenticated by Cloud Shell.
- SQL*Plus or SQLcl is available in Cloud Shell.
- Your OCI user can create Autonomous Databases in the target compartment.
- Your OCI user can create IAM groups or reuse existing IAM groups.
- The target database is Autonomous Database 26ai. Deep Data Security end-user
  context privileges used by this lab are not supported on 19c.
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
<copy>
export OCI_COMPARTMENT=my-compartment
</copy>
```

To use the root compartment, set:

```bash
<copy>
export OCI_COMPARTMENT=root
</copy>
```

You can also pass the compartment to the setup script directly:

```bash
<copy>
./00_setup_adb.sh my-compartment
</copy>
```

If neither `OCI_COMPARTMENT` nor `ROOT_COMP_ID` is set, the setup script assumes
`OCI_COMPARTMENT=root`.

If you prefer to use a compartment OCID directly, set:

```bash
<copy>
export ROOT_COMP_ID=ocid1.compartment.oc1..aaaa...
</copy>
```

Optional overrides:

```bash
<copy>
export DB_NAME=deepsec1
export DB_VERSION=26ai
export ADMIN_PWD='Oracle123+Oracle123+'
export WALLET_PWD='Oracle123+'
export OCI_IAM_EMPLOYEE_GROUP=EMPLOYEES
export OCI_IAM_MANAGER_GROUP=MANAGERS
</copy>
```

`DB_DISPLAY_NAME` defaults to `DB_NAME`. Set it only if you want the OCI Console
display name to differ from the database name.

If Cloud Shell does not expose `OCI_CS_USER_OCID`, set the user OCID explicitly:

```bash
<copy>
export ADB_LAB_USER_OCID=ocid1.user.oc1..aaaa...
</copy>
```

`00_setup_adb.sh` uses that user as the lab's Marvin identity. Marvin's HR row is
created with the OCI IAM database user name for that user, so the verification step
can run with your current Cloud Shell token.

## 0. Download and Unzip the Lab Files

From the `database/advanced/deep-data-security` directory, download the lab archive:

```bash
<copy>
curl -L \
  "https://objectstorage.us-ashburn-1.oraclecloud.com/p/I8jdPFHveSlA1k1VemPIEHJuXIQtX8mq8BKi9rJbiCJ8YcxcY1pSwlSchZomVDPq/n/oradbclouducm/b/dbsec_public/o/adb-oci-iam.zip" \
  -o adb-oci-iam.zip
</copy>
```

Or, from a remote shell, use `wget -O` to save the archive with a clean file name:

```bash
<copy>
wget -O adb-oci-iam.zip \
  "https://objectstorage.us-ashburn-1.oraclecloud.com/p/I8jdPFHveSlA1k1VemPIEHJuXIQtX8mq8BKi9rJbiCJ8YcxcY1pSwlSchZomVDPq/n/oradbclouducm/b/dbsec_public/o/adb-oci-iam.zip"
</copy>
```

Unzip the archive into the `adb-oci-iam` directory:

```bash
<copy>
unzip -o adb-oci-iam.zip
cd adb-oci-iam
</copy>
```

If the archive creates a nested `adb-oci-iam` directory, move its contents up into
the current lab directory:

```bash
<copy>
if [ -d adb-oci-iam ]; then
  cp -R adb-oci-iam/. .
  rm -rf adb-oci-iam
fi
</copy>
```

Verify the extracted lab files:

```bash
<copy>
ls
</copy>
```

You should see the setup and verification scripts used by the remaining tasks.

## 1. Create ADB-S and Download the Wallet

```bash
<copy>
./00_setup_adb.sh
</copy>
```

Load the generated environment file:

```bash
<copy>
source ./.adb-oci-iam.env
</copy>
```

This script creates or reuses:

- OCI IAM OAuth resource app and public client app named with `DB_NAME`
- OAuth database access scope named with `DB_NAME`
- Database-side OCI IAM OAuth credential for the resource app
- Access-token group custom claim used by `IAM_OAUTH_GROUP=...`
- ADB-S database: `deepsec1`
- ADB wallet: `$HOME/adb_wallet/deepsec1`
- IAM groups: `EMPLOYEES`, `MANAGERS`

When `OCI_CS_USER_OCID` or `ADB_LAB_USER_OCID` is available, the script also adds
that IAM user to both lab groups.

## 2. Enable OCI IAM on ADB

```bash
<copy>
./01_enable_oci_iam.sh
</copy>
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

The script also sets `identity_provider_oauth_config` to the DB resource app
created by Task 0 and creates the database-side `OCI_IAM_DOMAIN_DB_CRED$`
credential. The client does not use this secret; SQL*Plus only reads the OAuth2
access token from `TOKEN_LOCATION`.

## 3. Create the HR Schema

```bash
<copy>
./02_create_hr_schema.sh
</copy>
```

The HR schema is created with `NO AUTHENTICATION`. It owns the data, but users do
not log in as `HR`.

## 4. Create Data Roles and Data Grants

```bash
<copy>
./03_create_data_roles_and_grants.sh
</copy>
```

The script creates:

- `HRAPP_EMPLOYEES`, mapped to `IAM_OAUTH_GROUP=EMPLOYEES`
- `HRAPP_MANAGERS`, mapped to `IAM_OAUTH_GROUP=MANAGERS`
- `DIRECT_LOGON_ROLE`, carrying `CREATE SESSION`
- HR row and column data grants

## 5. Verify the ADMIN-Side Setup

```bash
<copy>
./verify_db_setup.sh
</copy>
```

This confirms that OCI IAM is enabled, the HR rows exist, and the data roles are
mapped.

## 6. Get an OCI IAM OAuth2 Access Token

```bash
<copy>
./04_get_iam_oauth_token.sh
</copy>
```

This script updates the ADB wallet `sqlnet.ora` with:

```text
TOKEN_AUTH=OAUTH
TOKEN_LOCATION=$HOME/.oci/adb-oci-iam
```

Then it starts the OCI IAM OAuth2 authorization-code flow for the current user.
`00_setup_adb.sh` writes the required OAuth values to `.adb-oci-iam.env`:

```bash
<copy>
source ./.adb-oci-iam.env
</copy>
```

The token helper uses OAuth authorization-code with PKCE. A client secret is not
required for SQL*Plus or for a public interactive OAuth client.

In Cloud Shell, open the printed login URL in the NoVNC browser. After login,
the script writes the user's OAuth2 access token here:

```text
$HOME/.oci/adb-oci-iam/token
```

The database client reads that token through `TOKEN_AUTH=OAUTH`.

To inspect the token contents locally:

```bash
<copy>
./decode_token.sh
</copy>
```

The helper decodes the JWT header and payload, explains the important claims,
and shows the OCI IAM group claim used by the data role mappings. It does not
validate the token signature.

## 7. Verify Data Grants as the OCI IAM User

```bash
<copy>
./05_verify_as_cloud_shell_user.sh
</copy>
```

The script connects with:

```bash
<copy>
sqlplus /@${ADB_SERVICE}
</copy>
```

You should see:

- The authenticated OCI IAM identity.
- Active roles from IAM group mappings.
- Marvin's own HR row with SSN visible.
- Marvin's direct reports with SSN hidden.

## Clean Up Local Tokens

To remove local OCI IAM OAuth2 tokens:

```bash
<copy>
rm -rf "$HOME/.oci/adb-oci-iam"
</copy>
```

This removes the local token cache only. It does not change the OCI IAM user,
groups, ADB instance, wallet, or database objects.

## Clean Up the Lab

To remove the HR schema, lab roles, data roles, and data grants:

```bash
<copy>
./06_cleanup_adb_lab.sh
</copy>
```

To skip the prompt:

```bash
<copy>
./06_cleanup_adb_lab.sh --DELETE
</copy>
```

To delete the ADB instance too:

```bash
<copy>
./06_cleanup_adb_lab.sh --delete-adb
</copy>
```

To remove database objects, delete the ADB instance, remove the lab user from
the lab IAM groups, delete empty lab IAM groups, delete the lab OAuth apps, and
remove local generated wallet/env/token files:

```bash
<copy>
./06_cleanup_adb_lab.sh --remove-all
</copy>
```

To skip all cleanup prompts:

```bash
<copy>
./06_cleanup_adb_lab.sh --remove-all --DELETE
</copy>
```

The cleanup script does not delete IAM groups or OAuth apps by default. With
`--remove-all`, it deletes lab IAM groups only after removing the lab user and
confirming the groups are empty. In shared tenancies, groups may be reused by
other labs or policies.

## References

- [Enable OCI IAM authentication on Autonomous Database](https://docs.public.content.oci.oraclecloud.com/en-us/iaas/autonomous-database-serverless/doc/enable-iam-authentication.html)
- [Connect to Autonomous Database with OCI IAM authentication](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/iam-access-database.html)
- [Oracle Deep Data Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/oracle-deep-data-security-guide.pdf)
