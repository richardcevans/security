# OCI IAM Data Grants Lab

This lab shows identity-aware database access with OCI IAM OAuth2 and Oracle Deep Data Security.

End users authenticate with OCI IAM. Oracle Database reads the OAuth2 access token, activates mapped data roles from OCI IAM groups, and enforces row and column access with data grants.

## Table Of Contents

- [Architecture Flow](#architecture-flow)
- [Prerequisites](#prerequisites)
- [Required OCI Permissions](#required-oci-permissions)
- [What This Lab Creates](#what-this-lab-creates)
- [Important Defaults](#important-defaults)
- [Token Behavior](#token-behavior)
- [Do Not Do This](#do-not-do-this)
- [Security Model](#security-model)
- [Threat Model](#threat-model)
- [Security-Critical Claims](#security-critical-claims)
- [Least Privilege Design](#least-privilege-design)
- [Secrets Inventory](#secrets-inventory)
- [Bearer Token Handling](#bearer-token-handling)
- [Password Handling](#password-handling)
- [Local Callback Security](#local-callback-security)
- [Security Validation Checklist](#security-validation-checklist)
- [DBA Production Caution](#dba-production-caution)
- [Network File Backups And Restore](#network-file-backups-and-restore)
- [TNS_ADMIN Behavior](#tns_admin-behavior)
- [Step 1: Install OCI CLI](#step-1-install-oci-cli)
- [Step 2: Configure OCI CLI](#step-2-configure-oci-cli)
- [Step 3: Go To The Lab Directory](#step-3-go-to-the-lab-directory)
- [Step 4: Run DBA Preflight Checks](#step-4-run-dba-preflight-checks)
- [Step 5: Create OCI IAM Objects](#step-5-create-oci-iam-objects)
- [Step 6: Verify OCI IAM Objects](#step-6-verify-oci-iam-objects)
- [Step 7: Configure Database Identity Provider](#step-7-configure-database-identity-provider)
- [Step 8: Configure TCPS Network Files](#step-8-configure-tcps-network-files)
- [Step 9: Verify Wallet](#step-9-verify-wallet)
- [Step 10: Create HR Schema And Sample Data](#step-10-create-hr-schema-and-sample-data)
- [Step 11: Create Data Roles And Data Grants](#step-11-create-data-roles-and-data-grants)
- [Step 12: Verify Database Setup](#step-12-verify-database-setup)
- [Step 13: DBA Manual Validation SQL](#step-13-dba-manual-validation-sql)
- [Step 14: Set Demo User Passwords](#step-14-set-demo-user-passwords)
- [Step 15: Get An OAuth2 Token For Marvin](#step-15-get-an-oauth2-token-for-marvin)
- [Step 16: Verify Marvin](#step-16-verify-marvin)
- [Step 17: Get An OAuth2 Token For Emma](#step-17-get-an-oauth2-token-for-emma)
- [Step 18: Verify Emma](#step-18-verify-emma)
- [Step 19: Verify Security Boundary](#step-19-verify-security-boundary)
- [Optional: Test SQLPlus Manually](#optional-test-sqlplus-manually)
- [Optional: Use Email-Style Usernames](#optional-use-email-style-usernames)
- [Optional: Use Existing OCI IAM Users](#optional-use-existing-oci-iam-users)
- [Rerun Safety](#rerun-safety)
- [Security Notes](#security-notes)
- [Database Parameter Rollback](#database-parameter-rollback)
- [Audit And Log Locations](#audit-and-log-locations)
- [Clear Local Tokens](#clear-local-tokens)
- [Optional: Use A Specific Domain URL](#optional-use-a-specific-domain-url)
- [Custom Claim Fallback](#custom-claim-fallback)
- [Troubleshooting](#troubleshooting)
- [Cleanup Database Objects](#cleanup-database-objects)
- [Cleanup OCI IAM Objects](#cleanup-oci-iam-objects)
- [Reference](#reference)

## Architecture Flow

```text
NoVNC browser login
  -> OCI IAM authorization-code flow
  -> OAuth2 access token file
  -> sqlplus /@hrdb
  -> Oracle Database validates token
  -> OCI IAM group claim activates data roles
  -> data grants filter rows and columns
```

SQL*Plus does not open the browser in this lab. The helper script gets the OAuth2 access token first, then SQL*Plus reads the token file.

In the Microsoft Entra ID version of this lab, this helper step can be skipped because the token can be obtained through interactive browser-based authentication. For OCI IAM, this lab currently uses `get_oci_oauth_token.sh` to perform the OAuth2 authorization-code flow. We expect this helper script may not be required in the future.

## Prerequisites

Before starting, confirm you have:

- A Linux or Oracle Linux lab host. These scripts are shell scripts and are not written for Windows.
- Oracle AI Database 26ai April 2026 Release Update (RU) installed on the lab host.
- The `oracle` OS user or another OS user that can run `sqlplus / as sysdba`.
- `ORACLE_HOME` set for the database home.
- A local CDB and PDB. The default lab values are `DB_SID=FREE` and `PDB_NAME=FREEPDB1`.
- A browser for OCI IAM login. NoVNC on the lab host is simplest. A local browser also works with `./get_oci_oauth_token.sh --headless`.
- OCI CLI configured with a user that can administer the target OCI IAM identity domain.

On the DBSec-Lab VM, source the DB23 Free environment before running database-side tasks:

```bash
source $DBSEC_ADMIN/setEnv-db23free.sh FREE FREEPDB1
```

This sets `ORACLE_HOME`, `ORACLE_SID=FREE`, and `PDB_NAME=FREEPDB1` for Oracle AI Database 26ai Free. If your terminal inherited wallet or TNS settings from another database home, clear them before continuing:

```bash
unset WALLET_DIR TNS_ADMIN
```

Check `ORACLE_HOME`:

```bash
echo "$ORACLE_HOME"
```

Check the current local database SID:

```bash
echo "$ORACLE_SID"
```

The scripts set `ORACLE_SID` from `DB_SID`, so the shell prompt does not have to already show `FREE`.

Check the database release:

```bash
sqlplus -s / as sysdba
```

Run this SQL:

```sql
SELECT banner_full FROM v$version;
```

Exit SQLPlus:

```sql
exit;
```

The output should identify Oracle AI Database 26ai with the April 2026 Release Update or newer.

## Required OCI Permissions

The OCI CLI user must be able to manage identity-domain objects in the target domain.

At minimum, the user needs permissions to:

- create, update, activate, and delete identity-domain applications
- regenerate confidential application client secrets
- create and update users
- create and update groups
- add users to groups
- create or manage custom access-token claims
- list identity domains in the tenancy, unless `OCI_DOMAIN_URL` is set manually

If your organization uses tightly scoped OCI policies, ask the tenancy administrator for equivalent identity-domain administration rights before running `00_setup_oci_iam.sh`.

## What This Lab Creates

The lab creates or configures:

- OCI IAM DB resource app: `Oracle DB`
- OCI IAM OAuth client app: `Oracle Confidential Client`
- OCI IAM groups: `EMPLOYEES`, `MANAGERS`
- OCI IAM demo users: `marvin`, `emma`
- OCI IAM custom access-token claim: `group`
- Database identity provider configuration for `OCI_IAM`
- TCPS listener and `hrdb` TNS entry
- HR schema and employee sample data
- Data roles mapped to OCI IAM groups
- Data grants that give Marvin and Emma different access to the same table

Expected access:

| User | OCI IAM Groups | Expected Data Roles | Expected Rows |
|---|---|---|---|
| `marvin` | `EMPLOYEES`, `MANAGERS` | `HRAPP_EMPLOYEES`, `HRAPP_MANAGERS` | Marvin plus direct reports |
| `emma` | `EMPLOYEES` | `HRAPP_EMPLOYEES` | Emma only |

## Important Defaults

The scripts use these defaults unless you override them before running `00_setup_oci_iam.sh`:

| Variable | Default | Purpose |
|---|---|---|
| `OCI_DOMAIN_NAME` | `Default` | OCI IAM identity domain display name |
| `DB_SID` | `FREE` | Local CDB instance used for SYSDBA setup |
| `PDB_NAME` | `FREEPDB1` | PDB/service used by the lab |
| `MARVIN_USERNAME` | `marvin` | Manager test user |
| `EMMA_USERNAME` | `emma` | Employee test user |
| `OCI_SCOPE` | `OracleDBDB_ACCESS_SCOPE` | OAuth2 scope requested by the token helper |
| `OCI_REDIRECT_URI` | `http://localhost:8888/callback` | OAuth2 authorization-code redirect URI |

Network ports used by the lab:

| Port | Purpose |
|---|---|
| `1521` | TCP listener endpoint |
| `2484` | TCPS listener endpoint |
| `8888-8890` | Local OAuth2 callback ports |

Avoid using port `8080` for this lab. In some lab images, `8080` is already used by GlassFish.

To use a different local database instance:

```bash
export DB_SID=FREE
```

To use a different PDB:

```bash
export PDB_NAME=FREEPDB1
```

To use a different OCI IAM domain by display name:

```bash
export OCI_DOMAIN_NAME='Default'
```

## Token Behavior

The OAuth2 helper writes one token file:

```text
~/.oci/oci-iam-data-grants/token
```

There is only one active token file at a time.

Getting a Marvin token overwrites any Emma token.

Getting an Emma token overwrites any Marvin token.

The token usually expires after about one hour.

The verification scripts decode the token before connecting. If the token is for the wrong user, the script stops before SQL*Plus runs.

## Do Not Do This

Do not expect `sqlplus /@hrdb` to open a browser. Run `./get_oci_oauth_token.sh` first.

Do not reuse old authorization URLs. Each authorization code is one-time use.

Do not continue if a verifier reports an error.

Do not ignore a token preflight error saying the token is for the wrong user.

Do not run `09_cleanup_oci_iam.sh` unless you intend to delete the OCI IAM lab applications, users, groups, and claims.

Do not paste OAuth2 token contents into tickets, chats, or documents. The token is a bearer credential until it expires.

Do not run this lab unchanged on a production database host.

Do not run this lab unchanged on RAC, GI-managed listeners, SCAN listeners, or Data Guard environments.

## Security Model

This lab demonstrates database-enforced authorization for externally authenticated users.

Trust boundaries:

| Boundary | Responsibility |
|---|---|
| OCI IAM | Authenticates the user and issues the OAuth2 access token |
| OAuth2 access token | Carries user identity, audience, scope, resource app id, and group claims |
| Oracle Database | Validates token signature and claims |
| Data role mapping | Activates database data roles from OCI IAM group claims |
| Data grants | Enforce row and column access inside the database |
| SQLPlus | Client only; it does not enforce policy |

The security enforcement point is the database, not the application or SQLPlus.

## Threat Model

This lab is designed to show protection against:

- an application or user running a broad `SELECT`
- end users with different IAM groups running the same SQL
- accidental overexposure of rows or columns
- direct database logon without an OAuth2 token that maps to a data role with `CREATE SESSION`

This lab does not protect against:

- `SYS`, DBA, or highly privileged database administrators
- a compromised `oracle` OS account
- a stolen OAuth2 bearer token
- a compromised OCI IAM administrator
- a user or process that can read `.oci-iam-data-grants.env`
- a user or process that can read `~/.oci/oci-iam-data-grants/token`

## Security-Critical Claims

The OAuth2 token must contain the expected claims.

For Marvin, expected claims include:

```text
sub=marvin
```

```text
aud=OracleDB
```

```text
scope=DB_ACCESS_SCOPE
```

```text
group=EMPLOYEES,MANAGERS
```

```text
tok_type=AT
```

```text
resource_app_id=<OCI_DB_APP_ID>
```

For Emma, expected claims include:

```text
sub=emma
```

```text
group=EMPLOYEES
```

The `resource_app_id` claim is important. The database checks it against `identity_provider_oauth_config.app_id`. If it does not match, authentication fails.

The `group` claim is authorization-critical. Without it, the database may validate the token but fail to activate the mapped data roles.

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

Data access comes from data grants, not from normal object grants to Marvin or Emma.

The data roles map to OCI IAM groups:

```sql
HRAPP_EMPLOYEES -> IAM_OAUTH_GROUP=EMPLOYEES
```

```sql
HRAPP_MANAGERS -> IAM_OAUTH_GROUP=MANAGERS
```

Changing OCI IAM group membership changes authorization for newly issued tokens.

To test group membership changes, get a fresh token after changing group membership.

## Secrets Inventory

Sensitive local files and values:

| Secret | Location | Notes |
|---|---|---|
| OCI CLI API key | `~/.oci` | Used by OCI CLI to create IAM objects |
| Lab env file | `.oci-iam-data-grants.env` | Contains OAuth client secrets |
| DB app client secret | `OCI_DB_CLIENT_SECRET` | Stored in database credential |
| OAuth client secret | `OCI_CLIENT_SECRET` | Used by token helper |
| OAuth2 access token | `~/.oci/oci-iam-data-grants/token` | Bearer credential for SQLPlus token auth |
| TCPS wallet | `$ORACLE_BASE/admin/$ORACLE_SID/wallet` | Contains listener TLS wallet |

Check env file permissions:

```bash
ls -l .oci-iam-data-grants.env
```

Expected env file permission:

```text
-rw-------
```

Check token directory permissions:

```bash
ls -ld ~/.oci/oci-iam-data-grants
```

Expected token directory permission:

```text
drwx------
```

Check token file permissions:

```bash
ls -l ~/.oci/oci-iam-data-grants/token
```

Expected token file permission:

```text
-rw-------
```

## Bearer Token Handling

The OAuth2 access token is a bearer credential.

Anyone who can read the token file can attempt to authenticate as that user until the token expires.

Deleting the local token file prevents local reuse from that file, but it does not revoke a token that has already been copied elsewhere.

Clear local token material with the helper:

```bash
./clear_local_tokens.sh
```

Token lifetime is usually about one hour.

Group membership changes affect newly issued tokens. Do not assume an already issued token reflects a recent group removal.

## Password Handling

Prefer the secure prompt:

```bash
./set_oci_iam_passwords.sh
```

Avoid passing passwords on the command line:

```bash
./set_oci_iam_passwords.sh --user marvin --password 'PasswordHere'
```

Command-line passwords can appear in shell history or process listings.

If you used `--password` in a disposable lab shell, clear the shell history according to your organization’s policy.

## Local Callback Security

The token helper listens only on localhost callback ports.

The authorization code is short-lived and one-time use.

Do not expose callback ports externally.

Do not use a shared browser session without signing out or clearing the browser session between users.

Use a fresh token for each user test.

If you use `--headless`, the helper does not listen on localhost. It prints the authorization URL and waits for you to paste the final redirected URL or the `code` value from the browser.

## Security Validation Checklist

Before calling the lab complete, verify:

- Marvin token preflight shows `sub=marvin`
- Marvin token preflight shows `EMPLOYEES` and `MANAGERS`
- Emma token preflight shows `sub=emma`
- Emma token preflight shows `EMPLOYEES`
- `05_verify_as_marvin.sh` stops if Emma’s token is on disk
- `06_verify_as_emma.sh` stops if Marvin’s token is on disk
- `HR` has `NO AUTHENTICATION`
- `DIRECT_LOGON_ROLE` has only `CREATE SESSION`
- Marvin sees only his authorized rows
- Emma sees only her own row
- Emma cannot update salary
- Emma cannot update Marvin’s phone number
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

On production, RAC, Grid Infrastructure, SCAN listener, or shared Oracle home environments, do not run `02_configure_network.sh` as-is. Adapt the listener, wallet, and TNS changes manually with your normal DBA change process.

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

Restart the listener after restoring:

```bash
lsnrctl stop
```

```bash
lsnrctl start
```

## TNS_ADMIN Behavior

The lab scripts write to:

```text
$ORACLE_HOME/network/admin
```

If `TNS_ADMIN` is set, SQL*Plus may read network files from another directory.

Check `TNS_ADMIN`:

```bash
echo "$TNS_ADMIN"
```

If `TNS_ADMIN` is set and you want SQL*Plus to use the lab-generated `hrdb` entry, copy or merge the generated `hrdb` entry into the directory pointed to by `TNS_ADMIN`, or unset `TNS_ADMIN` for the lab shell.

Unset `TNS_ADMIN` for the current shell:

```bash
unset TNS_ADMIN
```

## Step 1: Install OCI CLI

OCI CLI is required for `00_setup_oci_iam.sh`. The script uses OCI CLI to create and update OCI IAM identity-domain objects.

### Oracle Linux 9

```bash
sudo dnf -y install oraclelinux-developer-release-el9
```

```bash
sudo dnf install python39-oci-cli
```

### Oracle Linux 8

```bash
sudo dnf -y install oraclelinux-developer-release-el8
```

```bash
sudo dnf install python36-oci-cli
```

### Oracle Linux 7

```bash
sudo yum install python36-oci-cli
```

### Generic Linux or Unix Installer

```bash
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
```

### macOS

```bash
brew update
```

```bash
brew install oci-cli
```

## Step 2: Configure OCI CLI

Run OCI CLI setup:

```bash
oci setup config
```

Verify OCI CLI can call OCI:

```bash
oci iam region list
```

Expected result: a JSON response containing OCI regions.

If you use a non-default OCI CLI profile:

```bash
export OCI_PROFILE=DEFAULT
```

If your OCI CLI config is not in the default location:

```bash
export OCI_CONFIG_FILE=/home/oracle/.oci/config
```

## Step 3: Go To The Lab Directory

Run this from the lab directory:

```bash
cd ~/DBSecLab/livelabs/deep-data-security/oci-iam-data-grants
```

Make sure scripts are executable:

```bash
chmod +x *.sh
```

## Step 4: Run DBA Preflight Checks

Run the preflight script:

```bash
./00_preflight.sh
```

Expected result:

```text
Preflight completed without blocking failures.
```

This checks:

- `ORACLE_HOME`
- `ORACLE_BASE`
- `DB_SID`
- `PDB_NAME`
- `TNS_ADMIN`
- `sqlplus / as sysdba`
- visible PDBs
- SQL patch inventory
- `opatch lspatches` when available
- listener status
- OCI CLI connectivity
- OAuth callback ports `8888-8890`

## Step 5: Create OCI IAM Objects

This script creates or reuses the OCI IAM apps, groups, users, OAuth client secret, custom claim, and environment file.

```bash
./00_setup_oci_iam.sh
```

Expected result:

```text
Task 0 Completed: OCI IAM Objects Ready
```

Load the environment file:

```bash
source ./.oci-iam-data-grants.env
```

Do this every time you run `00_setup_oci_iam.sh`.

Also do this in every new terminal before running later scripts.

Verify that the important variables are set:

```bash
env | grep -E '^(OCI_DOMAIN_URL|OCI_DB_APP_ID|OCI_DB_CLIENT_ID|OCI_CLIENT_ID|OCI_SCOPE|OCI_REDIRECT_URI|DB_SID|PDB_NAME)='
```

Important: `OCI_DB_APP_ID` and `OCI_DB_CLIENT_ID` are different values.

- `OCI_DB_APP_ID` must match the token claim named `resource_app_id`.
- `OCI_DB_CLIENT_ID` is stored in the database credential `OCI_IAM_DOMAIN_DB_CRED$`.

## Step 6: Verify OCI IAM Objects

Run the OCI IAM verifier:

```bash
./verify_oci_iam_setup.sh
```

Expected result:

```text
OCI IAM setup looks correct for the lab.
```

This checks:

- `Oracle DB` app exists
- `Oracle Confidential Client` app exists
- `EMPLOYEES` group exists
- `MANAGERS` group exists
- `marvin` user exists
- `emma` user exists
- `marvin` is in `EMPLOYEES` and `MANAGERS`
- `emma` is in `EMPLOYEES`

If this step fails, fix OCI IAM setup before continuing.

## Step 7: Configure Database Identity Provider

This configures the target PDB for OCI IAM OAuth2 validation.

```bash
./01_configure_db_identity_provider.sh
```

Expected result:

```text
Task 1 Completed: OCI IAM Identity Provider Configured!
```

This script uses local SYSDBA authentication. It sets `ORACLE_SID` from `DB_SID`, which defaults to `FREE`.

## Step 8: Configure TCPS Network Files

This configures wallet, listener, `sqlnet.ora`, and `tnsnames.ora`.

```bash
./02_configure_network.sh
```

Expected result:

```text
Task 2 Completed: Network Configured for OCI IAM Authentication!
```

Verify the `hrdb` alias resolves:

```bash
tnsping hrdb
```

Expected result:

```text
OK
```

The `hrdb` TNS entry should use:

```text
TOKEN_AUTH = OAUTH
```

and:

```text
TOKEN_LOCATION = "/home/oracle/.oci/oci-iam-data-grants"
```

Verify listener status:

```bash
lsnrctl status
```

Expected listener output should show TCP port `1521`, TCPS port `2484`, and service `freepdb1`.

## Step 9: Verify Wallet

Display the wallet:

```bash
orapki wallet display -wallet "$ORACLE_BASE/admin/$ORACLE_SID/wallet"
```

Expected details:

- auto-login wallet exists
- self-signed certificate exists
- certificate DN matches the `SSL_SERVER_CERT_DN` in `tnsnames.ora`

The lab wallet path defaults to:

```text
$ORACLE_BASE/admin/$ORACLE_SID/wallet
```

## Step 10: Create HR Schema And Sample Data

This creates the schema-only `HR` account and sample employee rows.

```bash
./03_create_hr_schema.sh
```

Expected result:

```text
Task 3 Completed: HR Schema Created!
```

This script is repeatable. If `HR` already exists, it drops and recreates the lab schema.

## Step 11: Create Data Roles And Data Grants

This creates the data roles, grants, end-user context, and direct logon role.

```bash
./04_create_data_roles_and_grants.sh
```

Expected result:

```text
Task 4 Completed: Data Roles, Grants, and Context Created!
```

The script creates:

- `HRAPP_EMPLOYEES` mapped to `IAM_OAUTH_GROUP=EMPLOYEES`
- `HRAPP_MANAGERS` mapped to `IAM_OAUTH_GROUP=MANAGERS`
- `DIRECT_LOGON_ROLE`
- `CREATE SESSION` granted to `DIRECT_LOGON_ROLE`
- `DIRECT_LOGON_ROLE` granted to both data roles
- row and column data grants on `HR.EMPLOYEES`

## Step 12: Verify Database Setup

Run the database verifier:

```bash
./verify_db_setup.sh
```

Expected output should include:

```text
identity_provider_type
OCI_IAM
```

Expected output should include:

```text
HRAPP_EMPLOYEES
HRAPP_MANAGERS
DIRECT_LOGON_ROLE
```

This checks:

- `identity_provider_type`
- `identity_provider_oauth_config`
- `OCI_IAM_DOMAIN_DB_CRED$`
- data role mappings
- `DIRECT_LOGON_ROLE`
- `CREATE SESSION`
- data grants
- HR employee rows

If this step fails, fix the database setup before continuing.

## Step 13: DBA Manual Validation SQL

These SQL statements are optional, but useful if a DBA wants to verify the setup manually.

Connect locally:

```bash
sqlplus / as sysdba
```

Switch to the PDB:

```sql
ALTER SESSION SET CONTAINER = FREEPDB1;
```

Check identity provider parameters:

```sql
SELECT name, value
  FROM v$parameter
 WHERE name LIKE 'identity_provider%';
```

Check the OCI IAM database credential:

```sql
SELECT credential_name, username
  FROM dba_credentials
 WHERE credential_name = 'OCI_IAM_DOMAIN_DB_CRED$';
```

Check data role mappings:

```sql
SELECT data_role, mapped_to, enabled_by_default
  FROM dba_data_roles
 WHERE data_role IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS');
```

Check direct logon role grants:

```sql
SELECT grantee, granted_role
  FROM dba_role_privs
 WHERE granted_role = 'DIRECT_LOGON_ROLE'
    OR grantee IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS')
 ORDER BY grantee, granted_role;
```

Check `CREATE SESSION`:

```sql
SELECT grantee, privilege
  FROM dba_sys_privs
 WHERE grantee = 'DIRECT_LOGON_ROLE';
```

Check active data roles during a token-authenticated session:

```sql
SELECT role_name FROM v$end_user_data_role;
```

Check the token-authenticated identity during a token-authenticated session:

```sql
SELECT
  sys_context('USERENV','CURRENT_USER') AS current_user,
  sys_context('USERENV','AUTHENTICATED_IDENTITY') AS authenticated_identity,
  sys_context('USERENV','AUTHENTICATION_METHOD') AS authentication_method
FROM dual;
```

Exit SQLPlus:

```sql
exit;
```

## Step 14: Set Demo User Passwords

Set or reset passwords for `marvin` and `emma`.

```bash
./set_oci_iam_passwords.sh
```

Expected result:

```text
Password set for marvin
Password set for emma
```

The script prompts securely for the new password.

To set only Marvin’s password:

```bash
./set_oci_iam_passwords.sh --user marvin
```

To set only Emma’s password:

```bash
./set_oci_iam_passwords.sh --user emma
```

Avoid passing passwords on the command line unless this is a disposable demo environment.

## Step 15: Get An OAuth2 Token For Marvin

SQL*Plus does not open the browser. You must get an OCI IAM OAuth2 token first.

Note: In the Microsoft Entra ID version of this lab, this step can be skipped because the token can be taken from interactive browser-based authentication. For OCI IAM, use this helper for now. We expect to not require this helper script in the future.

Run the helper:

```bash
./get_oci_oauth_token.sh
```

If you are using a browser on your laptop instead of a browser on the lab host, run headless mode:

```bash
./get_oci_oauth_token.sh --headless
```

Expected result:

```text
OAuth2 access token written for SQL*Plus.
```

Open the printed URL in the NoVNC browser.

Sign in as:

```text
marvin
```

After login, the helper writes the token to:

```text
~/.oci/oci-iam-data-grants/token
```

The helper listens on one of these callback URLs:

```text
http://localhost:8888/callback
```

```text
http://localhost:8889/callback
```

```text
http://localhost:8890/callback
```

If automatic callback capture fails, paste the entire final redirected URL from the browser address bar into the helper. The helper parses the URL, extracts the OAuth2 `code`, verifies `state` when it is present, and explains why it is exchanging that one-time code for an access token. You can also paste only the raw `code` value.

In headless mode, you can open the authorization URL in a browser on your local laptop. In that case, `localhost` means your laptop, not the lab VM. After a successful OCI IAM login, the browser should redirect to a URL like `http://localhost:8888/callback?code=...&state=...`. The page may say `This site can't be reached` or `connection refused`, because nothing is listening on your laptop callback port. That is expected. Copy the full redirected URL from the laptop browser address bar and paste it into the helper running on the lab VM.

If the browser silently logs in as the wrong user or reuses an old OCI IAM session, close all OCI IAM browser windows or use a private/incognito window before opening the fresh authorization URL from the helper.

If your shell still has an old `OCI_REDIRECT_URI` value such as `http://localhost:8080/callback`, the setup and token helper scripts reset it to the first lab redirect URI, normally `http://localhost:8888/callback`.

## Step 16: Verify Marvin

Run Marvin’s verification script:

```bash
./05_verify_as_marvin.sh
```

Expected token preflight:

```text
Token subject: marvin
Token groups : EMPLOYEES, MANAGERS
```

The script decodes the token before connecting. It requires:

```text
sub=marvin
```

and groups:

```text
EMPLOYEES, MANAGERS
```

If the token is for Emma, the script stops before running SQL.

## Step 17: Get An OAuth2 Token For Emma

Note: In the Microsoft Entra ID version of this lab, this step can be skipped because the token can be taken from interactive browser-based authentication. For OCI IAM, use this helper for now. We expect to not require this helper script in the future.

Run the helper again:

```bash
./get_oci_oauth_token.sh
```

If you are using a browser on your laptop instead of a browser on the lab host, run headless mode:

```bash
./get_oci_oauth_token.sh --headless
```

Expected result:

```text
OAuth2 access token written for SQL*Plus.
```

Sign in as:

```text
emma
```

This replaces the token file with Emma’s OAuth2 token.

## Step 18: Verify Emma

Run Emma’s verification script:

```bash
./06_verify_as_emma.sh
```

Expected token preflight:

```text
Token subject: emma
Token groups : EMPLOYEES
```

The script decodes the token before connecting. It requires:

```text
sub=emma
```

and group:

```text
EMPLOYEES
```

## Step 19: Verify Security Boundary

The security-boundary script runs multiple tests. Before each OCI IAM test, make sure the token on disk belongs to the requested user.

Run:

```bash
./07_verify_security_boundary.sh
```

If the script asks for a Marvin test, get a Marvin token first:

```bash
./get_oci_oauth_token.sh
```

If the script asks for an Emma test, get an Emma token first:

```bash
./get_oci_oauth_token.sh
```

## Optional: Test SQLPlus Manually

Get a token first:

```bash
./get_oci_oauth_token.sh
```

Connect with SQLPlus:

```bash
sqlplus -L /@hrdb
```

Expected result:

```text
Connected to:
Oracle AI Database 26ai Enterprise Edition
```

Show the authenticated user:

```sql
show user;
```

For Marvin, expected result:

```text
USER is "marvin"
```

Exit SQLPlus:

```sql
exit;
```

## Optional: Use Email-Style Usernames

By default, the lab uses simple usernames:

```text
marvin
```

```text
emma
```

To use email-style usernames, set `OCI_USERNAME_DOMAIN` before running `00_setup_oci_iam.sh`.

Example:

```bash
export OCI_USERNAME_DOMAIN=example.com
```

Then rerun setup:

```bash
./00_setup_oci_iam.sh
```

Load the new environment:

```bash
source ./.oci-iam-data-grants.env
```

## Optional: Use Existing OCI IAM Users

If you do not want the lab to create `marvin` and `emma`, set this before running `00_setup_oci_iam.sh`:

```bash
export CREATE_DEMO_USERS=0
```

Run setup:

```bash
./00_setup_oci_iam.sh
```

Load the environment:

```bash
source ./.oci-iam-data-grants.env
```

Manually add your manager test user to:

```text
EMPLOYEES
```

```text
MANAGERS
```

Manually add your employee test user to:

```text
EMPLOYEES
```

Make sure `HR.EMPLOYEES.USER_NAME` matches `ORA_END_USER_CONTEXT.username`.

## Rerun Safety

| Script | Safe To Rerun? | Notes |
|---|---|---|
| `00_setup_oci_iam.sh` | Yes | Reuses and updates OCI IAM objects. Regenerates client secrets and rewrites `.oci-iam-data-grants.env`. Always source the env file afterward. |
| `01_configure_db_identity_provider.sh` | Yes | Reapplies identity-provider parameters and recreates the DB credential. |
| `02_configure_network.sh` | Yes for this lab VM | Rewrites `listener.ora`, `sqlnet.ora`, and the `hrdb` entry in `tnsnames.ora`. Backup files are created. |
| `03_create_hr_schema.sh` | Destructive to lab HR schema | Drops and recreates `HR`. Do not run if you want to keep lab HR changes. |
| `04_create_data_roles_and_grants.sh` | Yes | Recreates data roles and data grants. |
| `05_verify_as_marvin.sh` | Yes | Requires a Marvin token on disk. |
| `06_verify_as_emma.sh` | Yes | Requires an Emma token on disk. |
| `07_verify_security_boundary.sh` | Yes | Requires the correct user token before each test. |
| `08_cleanup_db.sh` | Destructive | Removes database-side lab objects. |
| `09_cleanup_oci_iam.sh` | Destructive | Removes OCI IAM lab objects. |

## Security Notes

The file `.oci-iam-data-grants.env` contains client secrets.

Check its permissions:

```bash
ls -l .oci-iam-data-grants.env
```

The token file is a bearer credential until it expires:

```text
~/.oci/oci-iam-data-grants/token
```

Do not paste the token contents into chats, tickets, or documentation.

Cleanup scripts remove lab objects, but backup files such as `listener.ora.bak`, `sqlnet.ora.bak`, and `tnsnames.ora.bak` may remain in `$ORACLE_HOME/network/admin`.

## Database Parameter Rollback

`08_cleanup_db.sh` resets the identity provider parameters.

Manual rollback SQL:

```bash
sqlplus / as sysdba
```

Switch to the PDB:

```sql
ALTER SESSION SET CONTAINER = FREEPDB1;
```

Reset the OAuth configuration:

```sql
ALTER SYSTEM RESET IDENTITY_PROVIDER_OAUTH_CONFIG SCOPE=BOTH;
```

Reset the identity provider type:

```sql
ALTER SYSTEM RESET IDENTITY_PROVIDER_TYPE SCOPE=BOTH;
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
OCI_IAM
```

```text
Claims check failed
```

```text
resource application id not matched
```

If Unified Auditing is enabled in your environment, review your local audit policy and audit trail for logon events. This lab does not create or modify Unified Audit policies.

## Clear Local Tokens

Use this when you want to remove the local OAuth2 bearer token before switching users, ending the lab, or sharing the lab host.

```bash
./clear_local_tokens.sh
```

The script removes:

- `~/.oci/oci-iam-data-grants/token`
- the `~/.oci/oci-iam-data-grants` directory, if it is empty after token removal

The script does not remove:

- OCI IAM applications
- OCI IAM users
- OCI IAM groups
- database objects
- database identity-provider configuration
- `.oci-iam-data-grants.env`
- OCI CLI config or API keys

The script cannot unset variables in your parent shell. To clear sensitive exported values from the current terminal, run:

```bash
unset OCI_CLIENT_SECRET OCI_DB_CLIENT_SECRET OCI_REDIRECT_URI OCI_REDIRECT_URIS
```

## Optional: Use A Specific Domain URL

If automatic domain discovery is not allowed by your OCI policies, set `OCI_DOMAIN_URL` before running `00_setup_oci_iam.sh`.

Example:

```bash
export OCI_DOMAIN_URL=https://idcs-xxxxxxxx.identity.oraclecloud.com:443
```

Run setup:

```bash
./00_setup_oci_iam.sh
```

Load the environment:

```bash
source ./.oci-iam-data-grants.env
```

## Custom Claim Fallback

`00_setup_oci_iam.sh` attempts to create this custom access-token claim:

```json
{
  "schemas": [
    "urn:ietf:params:scim:schemas:oracle:idcs:CustomClaim"
  ],
  "name": "group",
  "value": "$user.groups.*.display",
  "expression": true,
  "mode": "always",
  "tokenType": "AT",
  "allScopes": true
}
```

This claim is required. Without it, OCI IAM authentication can succeed, but the database data roles will not activate.

If the script prints a warning about custom claim creation, create the claim manually in OCI IAM.

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `ORA-01017` and alert log says `resource application id not matched` | Database `identity_provider_oauth_config.app_id` does not match token `resource_app_id` | Rerun `00`, source env, rerun `01` |
| `Token is for emma, expected marvin` | Emma token is on disk when running Marvin script | Run `./get_oci_oauth_token.sh` and sign in as Marvin |
| `Token is for marvin, expected emma` | Marvin token is on disk when running Emma script | Run `./get_oci_oauth_token.sh` and sign in as Emma |
| Browser opens `localhost:8080` and shows GlassFish | Old redirect URI still in environment | Unset redirect variables, rerun `00`, source env |
| `ORA-01012: not logged on` from local SYSDBA script | Script connected to wrong local CDB | Set `DB_SID=FREE` or source the env file |
| `tnsping hrdb` fails | Network files were not configured or wrong `ORACLE_HOME` | Rerun `02_configure_network.sh` |
| Data roles do not activate | Token missing `group` claim or group membership | Run `verify_oci_iam_setup.sh`; check custom claim fallback |
| OAuth token exchange fails with `invalid_client` | Client secret/env mismatch | Rerun `00`, source env, retry token helper |

### `ORA-01017` And Alert Log Says `resource application id not matched`

Reload the environment and check these values:

```bash
env | grep -E '^(OCI_DB_APP_ID|OCI_DB_CLIENT_ID)='
```

`OCI_DB_APP_ID` must match the token claim named `resource_app_id`.

Rerun the database identity-provider setup:

```bash
./01_configure_db_identity_provider.sh
```

### Token Is For The Wrong User

If `05_verify_as_marvin.sh` says the token is for Emma, get a new token and sign in as Marvin:

```bash
./get_oci_oauth_token.sh
```

If `06_verify_as_emma.sh` says the token is for Marvin, get a new token and sign in as Emma:

```bash
./get_oci_oauth_token.sh
```

### `localhost:8080` Shows GlassFish

The current scripts use ports `8888`, `8889`, and `8890`. `00_setup_oci_iam.sh` and `get_oci_oauth_token.sh` automatically ignore a stale `OCI_REDIRECT_URI` such as `http://localhost:8080/callback` and reset the lab redirects to the registered `8888-8890` values.

If you still see `8080`, unset the old variables:

```bash
unset OCI_REDIRECT_URI
```

```bash
unset OCI_REDIRECT_URIS
```

Rerun setup:

```bash
./00_setup_oci_iam.sh
```

Load the environment:

```bash
source ./.oci-iam-data-grants.env
```

### Local SYSDBA Connects To The Wrong CDB

The scripts default to `DB_SID=FREE`. Verify:

```bash
env | grep DB_SID
```

Set it explicitly if needed:

```bash
export DB_SID=FREE
```

## Cleanup Database Objects

To remove database-side lab objects:

```bash
./08_cleanup_db.sh
```

Database cleanup removes the lab schema, data roles, grants, context, roles, credential, and identity-provider parameters.

Database cleanup does not remove:

- terminal scrollback
- copied OAuth2 tokens
- `.oci-iam-data-grants.env`
- token files under `~/.oci/oci-iam-data-grants`
- network backup files under `$ORACLE_HOME/network/admin`
- OCI CLI config or API keys

Clear local token material:

```bash
./clear_local_tokens.sh
```

## Cleanup OCI IAM Objects

To remove OCI IAM lab objects:

```bash
./09_cleanup_oci_iam.sh
```

To skip the confirmation prompt:

```bash
./09_cleanup_oci_iam.sh -f
```

Alternative force flag:

```bash
./09_cleanup_oci_iam.sh --DELETE
```

## Reference

Oracle OCI CLI quickstart:

<https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm>
