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
- Creates or reuses real OCI IAM domain users for Marvin and Emma.
- Configures SQL*Plus to use an OCI IAM OAuth2 access token.
- Verifies the same SQL returns different rows and columns for Marvin and Emma.

## Assumptions

- You are running from OCI Cloud Shell.
- OCI CLI is already available and authenticated by Cloud Shell.
- SQL*Plus or SQLcl is available in Cloud Shell.
- Your OCI user can create Autonomous Databases in the target compartment.
- Your OCI user can create OCI IAM domain users and groups, or reuse existing
  Marvin and Emma users and `EMPLOYEES` / `MANAGERS` groups.
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

Most users only need to set the compartment. The defaults create:

- ADB-S database `deepsec1`
- OCI IAM users `marvin` and `emma`
- OCI IAM groups `EMPLOYEES` and `MANAGERS`
- Marvin in both groups; Emma in `EMPLOYEES` only

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
export MARVIN_USERNAME=marvin
export EMMA_USERNAME=emma
</copy>
```

`DB_DISPLAY_NAME` defaults to `DB_NAME`. Set it only if you want the OCI Console
display name to differ from the database name.

If your OCI IAM usernames are email-style, set the username domain before setup:

```bash
<copy>
export OCI_USERNAME_DOMAIN=example.com
</copy>
```

That makes the HR sample rows use `marvin@example.com` and `emma@example.com`.
If you use the default simple usernames `marvin` and `emma`, leave
`OCI_USERNAME_DOMAIN` unset.

By default, `00_setup_adb.sh` creates or reuses the real OCI IAM domain users
`marvin` and `emma`. Set `CREATE_DEMO_USERS=0` only if you want to create or
manage those users manually.

## Run Order

For a clean run, execute the tasks in this order:

```bash
<copy>
./00_setup_adb.sh
source ./.adb-oci-iam.env
./set_oci_iam_passwords.sh --all
./01_enable_oci_iam.sh
./02_create_hr_schema.sh
./03_create_data_roles_and_grants.sh
./verify_db_setup.sh
</copy>
```

Then test each user with a fresh OAuth token:

```bash
<copy>
rm -rf "$HOME/.oci/adb-oci-iam"
./04_get_iam_oauth_token.sh --headless
./05_verify_as_marvin.sh

rm -rf "$HOME/.oci/adb-oci-iam"
./04_get_iam_oauth_token.sh --headless
./06_verify_as_emma.sh
</copy>
```

Sign in as Marvin for the first token and Emma for the second token.

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

Unzip the archive into the `adb-oci-iam` directory. Use `-o`, not `-f`, so new
files from an updated archive are added:

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
Important files include:

| File | Purpose |
| --- | --- |
| `00_setup_adb.sh` | Creates OCI IAM apps, groups, demo users, ADB, wallet, and `.adb-oci-iam.env` |
| `set_oci_iam_passwords.sh` | Sets or resets passwords for Marvin and Emma |
| `01_enable_oci_iam.sh` | Enables OCI IAM authentication on ADB and creates `OCI_IAM_DOMAIN_DB_CRED$` |
| `02_create_hr_schema.sh` | Creates the HR schema and sample employee rows |
| `03_create_data_roles_and_grants.sh` | Creates data roles and data grants |
| `04_get_iam_oauth_token.sh` | Gets an OCI IAM OAuth2 token for the signed-in user |
| `05_verify_as_marvin.sh` | Verifies manager access for Marvin |
| `06_verify_as_emma.sh` | Verifies employee access for Emma |
| `verify_db_setup.sh` | Verifies the ADMIN-side database setup |
| `06_cleanup_adb_lab.sh` | Removes lab database objects and optional OCI resources |

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
- OCI IAM domain groups: `EMPLOYEES`, `MANAGERS`
- OCI IAM domain users: `marvin`, `emma`

Default group membership:

| User | Groups |
| --- | --- |
| `marvin` | `EMPLOYEES`, `MANAGERS` |
| `emma` | `EMPLOYEES` |

Set or reset the demo user passwords after setup:

```bash
<copy>
./set_oci_iam_passwords.sh --all
</copy>
```

To set only Emma's password:

```bash
<copy>
./set_oci_iam_passwords.sh --user emma
</copy>
```

The password is not written to `.adb-oci-iam.env`. If you forget a demo user's
password, rerun the password helper.

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
    type   => 'OCI_IAM',
    params => JSON_OBJECT(
      'app_id'     VALUE '<OCI_DB_APP_ID>',
      'domain_url' VALUE '<OCI_DOMAIN_URL>'
    ),
    force  => TRUE
  );
END;
/
```

The `params` argument sets `identity_provider_oauth_config` to the DB resource
app created by Task 0. The script also creates the database-side
`OCI_IAM_DOMAIN_DB_CRED$` credential with `DBMS_CLOUD.CREATE_CREDENTIAL`.
The client does not use this secret; SQL*Plus only reads the OAuth2 access token
from `TOKEN_LOCATION`.

If this task prints `ALTER SYSTEM SET identity_provider_oauth_config`, you are
running an old copy of the lab files. Re-download the ZIP and unzip with `-o`.
The current ADB script uses `DBMS_CLOUD_ADMIN.ENABLE_EXTERNAL_AUTHENTICATION`
with the `params` argument instead of a direct `ALTER SYSTEM`.

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

Expected highlights:

```text
identity_provider_type              OCI_IAM
identity_provider_oauth_config      {"app_id":"...","domain_url":"..."}
HR_EMPLOYEE_ROWS                    7
OCI_IAM_DOMAIN_DB_CRED$             <OCI_DB_CLIENT_ID>
HRAPP_EMPLOYEES                     iam_oauth_group=EMPLOYEES
HRAPP_MANAGERS                      iam_oauth_group=MANAGERS
```

## 6. Get an OCI IAM OAuth2 Access Token

Use `--headless` in OCI Cloud Shell when your browser opens on your local machine:

```bash
<copy>
./04_get_iam_oauth_token.sh --headless
</copy>
```

This script updates the ADB wallet `sqlnet.ora` with:

```text
TOKEN_AUTH=OAUTH
TOKEN_LOCATION=$HOME/.oci/adb-oci-iam
```

Then it starts the OCI IAM OAuth2 authorization-code flow for the user you sign in as.
`00_setup_adb.sh` writes the required OAuth values to `.adb-oci-iam.env`:

```bash
<copy>
source ./.adb-oci-iam.env
</copy>
```

The token helper uses OAuth authorization-code with PKCE. A client secret is not
required for SQL*Plus or for a public interactive OAuth client.

In headless mode:

1. Open the printed login URL in a browser.
2. Sign in as the target demo user.
3. The final `localhost:8888/callback?...` page may fail to load. That is expected.
4. Copy the full callback URL from the browser address bar.
5. Paste it back into the Cloud Shell prompt.

After login, the script writes that user's OAuth2 access token here:

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

Before verification, check the token subject and groups:

```bash
<copy>
./decode_token.sh
</copy>
```

For Marvin, expect `user_name` or `sub` to be `marvin`, and `group` to include
`EMPLOYEES` and `MANAGERS`. For Emma, expect `emma` and `EMPLOYEES` only.

## 7. Verify Data Grants as Marvin

Get a token and sign in as Marvin:

```bash
<copy>
./04_get_iam_oauth_token.sh --headless
</copy>
```

Then verify Marvin:

```bash
<copy>
./05_verify_as_marvin.sh
</copy>
```

Marvin should have `EMPLOYEES` and `MANAGERS` in the token. He should see his own
row with SSN visible and his direct reports with SSN hidden.

Expected highlights:

```text
Token subject: marvin
Token groups : EMPLOYEES, MANAGERS

ROLE_NAME
------------------------------
HRAPP_EMPLOYEES
HRAPP_MANAGERS

Marvin sees 4 rows: Marvin, Emma, Charlie, and Dana.
```

## 8. Verify Data Grants as Emma

Clear Marvin's token, get a new token, and sign in as Emma:

```bash
<copy>
rm -rf "$HOME/.oci/adb-oci-iam"
./04_get_iam_oauth_token.sh --headless
</copy>
```

Then verify Emma:

```bash
<copy>
./06_verify_as_emma.sh
</copy>
```

Emma should have only `EMPLOYEES` in the token. She should see only her own row.

Expected highlights:

```text
Token subject: emma
Token groups : EMPLOYEES

ROLE_NAME
------------------------------
HRAPP_EMPLOYEES

Emma sees 1 row: Emma.
```

Both verification scripts connect with:

```bash
<copy>
sqlplus /@${ADB_SERVICE}
</copy>
```

## Troubleshooting

### Wrong files after re-download

If you downloaded a new ZIP over an existing folder, unzip with `-o`:

```bash
<copy>
unzip -o adb-oci-iam.zip
</copy>
```

Do not use `unzip -f` for lab updates because it does not add new files.

### Token is for the wrong user

Each token file contains one user's OAuth2 token. Clear it before switching users:

```bash
<copy>
rm -rf "$HOME/.oci/adb-oci-iam"
</copy>
```

Then rerun `./04_get_iam_oauth_token.sh --headless` and sign in as the correct user.

### ORA-01017 during slash login

First confirm the token is for the right user:

```bash
<copy>
./decode_token.sh
</copy>
```

Then rerun the database identity-provider setup:

```bash
<copy>
source ./.adb-oci-iam.env
./01_enable_oci_iam.sh
./verify_db_setup.sh
</copy>
```

The token `resource_app_id` must match `$OCI_DB_APP_ID`, and the database
`identity_provider_oauth_config.app_id` should show the same value.

### Data roles do not appear

The verification scripts show Deep Data Security data roles from
`V$END_USER_DATA_ROLE`. If expected roles are missing, get a fresh token after
confirming group membership:

```bash
<copy>
rm -rf "$HOME/.oci/adb-oci-iam"
./04_get_iam_oauth_token.sh --headless
</copy>
```

Group membership changes affect newly issued tokens. Existing tokens do not
automatically pick up group changes.

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

To remove database objects, delete the ADB instance, delete the lab OAuth apps,
and remove local generated wallet/env/token files:

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

The cleanup script does not delete OCI IAM domain users or groups by default.
Review `marvin`, `emma`, `EMPLOYEES`, and `MANAGERS` manually before deleting
them, because they may be reused by other labs or policies.

## References

- [Enable OCI IAM authentication on Autonomous Database](https://docs.public.content.oci.oraclecloud.com/en-us/iaas/autonomous-database-serverless/doc/enable-iam-authentication.html)
- [Connect to Autonomous Database with OCI IAM authentication](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/iam-access-database.html)
- [Oracle Deep Data Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/oracle-deep-data-security-guide.pdf)
