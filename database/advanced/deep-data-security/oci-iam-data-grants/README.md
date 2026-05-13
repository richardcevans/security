# OCI IAM Data Grants Lab

This lab shows identity-aware database access with OCI IAM OAuth2 and Oracle Deep Data Security. The full walkthrough is in [oci-iam-data-grants.md](./oci-iam-data-grants.md).

## Quick Start

The only OCI-side setup you should have to do manually is configure OCI CLI:

```bash
oci setup config
```

Then run the lab setup:

```bash
./00_setup_oci_iam.sh
source ./.oci-iam-data-grants.env
./verify_oci_iam_setup.sh
./01_configure_db_identity_provider.sh
./02_configure_network.sh
./03_create_hr_schema.sh
./04_create_data_roles_and_grants.sh
./set_oci_iam_passwords.sh
./get_oci_oauth_token.sh   # sign in as Marvin
./05_verify_as_marvin.sh
./get_oci_oauth_token.sh   # sign in as Emma
./06_verify_as_emma.sh
./07_verify_security_boundary.sh
```

`00_setup_oci_iam.sh` discovers the OCI IAM Domain URL automatically. It prefers the `Default` identity domain. To use a different domain name:

```bash
export OCI_DOMAIN_NAME='My Domain'
./00_setup_oci_iam.sh
source ./.oci-iam-data-grants.env
```

## Install OCI CLI

OCI CLI is used by `00_setup_oci_iam.sh` to create the lab's OCI IAM objects. Runtime database login uses an OCI IAM OAuth2 access token from authorization-code flow, written by `get_oci_oauth_token.sh`.

## OAuth2 Browser Login Helper

`sqlplus /@hrdb` reads an OAuth2 token file; it does not open the browser itself. Use the helper first:

```bash
./get_oci_oauth_token.sh
sqlplus /@hrdb
```

The helper prints the OCI IAM authorization URL, listens on an available localhost redirect URI, exchanges the returned authorization code for an OAuth2 access token, and writes:

```text
~/.oci/oci-iam-data-grants/token
```

By default, the helper does not launch the browser process itself; this keeps NoVNC terminal input stable. Open the printed URL in the NoVNC browser. To let the helper try to open the browser automatically:

```bash
OCI_OPEN_BROWSER=1 ./get_oci_oauth_token.sh
```

The setup script registers these localhost callback URIs on the OCI IAM client app and the helper uses whichever port is free:

```text
http://localhost:8888/callback
http://localhost:8889/callback
http://localhost:8890/callback
```

If the callback cannot be captured automatically, the helper lets you paste either the final redirected URL or just the `code` value.

### Oracle Linux 9

```bash
sudo dnf -y install oraclelinux-developer-release-el9
sudo dnf install python39-oci-cli
```

### Oracle Linux 8

```bash
sudo dnf -y install oraclelinux-developer-release-el8
sudo dnf install python36-oci-cli
```

### Oracle Linux 7

```bash
sudo yum install python36-oci-cli
```

### Linux and Unix Installer

Use this when your platform does not have a packaged OCI CLI:

```bash
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
```

For a silent install that accepts defaults:

```bash
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)" -- --accept-all-defaults
```

### macOS

```bash
brew update
brew install oci-cli
```

### Windows PowerShell

Run PowerShell as Administrator, then:

```powershell
Set-ExecutionPolicy RemoteSigned
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.ps1 -OutFile install.ps1
./install.ps1 -AcceptAllDefaults
```

### Verify and Configure

```bash
oci --version
oci setup config
```

`oci setup config` creates `~/.oci/config` and an API key pair. Upload the generated public key to your OCI user in the Console.

After that, the lab setup script can create the OCI IAM domain objects. It selects the `Default` identity domain unless you set `OCI_DOMAIN_NAME`:

```bash
./00_setup_oci_iam.sh
source ./.oci-iam-data-grants.env
```

If you use a non-default OCI CLI profile or config file, export these first:

```bash
export OCI_CONFIG_FILE=/home/oracle/.oci/config
export OCI_PROFILE=DEFAULT
```

## OCI IAM Setup Details

`00_setup_oci_iam.sh` creates or reuses these OCI IAM objects:

- DB resource app: `Oracle DB`
- OAuth client app: `Oracle Confidential Client`
- DB audience: `OracleDB`
- DB scope: `DB_ACCESS_SCOPE`
- Fully qualified scope: `OracleDBDB_ACCESS_SCOPE`
- Groups: `EMPLOYEES`, `MANAGERS`
- Demo users by default: `marvin`, `emma`
- Group assignments: `marvin` in `EMPLOYEES` and `MANAGERS`; `emma` in `EMPLOYEES`
- Custom access-token claim named `group` with value `$user.groups.*.display`
- Environment file: `.oci-iam-data-grants.env`

If identity-domain discovery is not allowed by your policies, provide the domain URL explicitly:

```bash
export OCI_DOMAIN_URL=https://idcs-xxxxxxxx.identity.oraclecloud.com:443
./00_setup_oci_iam.sh
source ./.oci-iam-data-grants.env
```

By default, the lab uses simple usernames:

```text
marvin
emma
```

To use email-style usernames instead:

```bash
export OCI_USERNAME_DOMAIN=example.com
./00_setup_oci_iam.sh
source ./.oci-iam-data-grants.env
```

If you already have users and do not want the script to create Marvin and Emma:

```bash
export CREATE_DEMO_USERS=0
./00_setup_oci_iam.sh
source ./.oci-iam-data-grants.env
```

Then manually add your test users to the created groups:

| User | Groups |
|---|---|
| manager user | `EMPLOYEES`, `MANAGERS` |
| employee user | `EMPLOYEES` |

Make sure `HR.EMPLOYEES.USER_NAME` matches `ORA_END_USER_CONTEXT.username`.

To set or reset passwords for the demo users from the command line:

```bash
./set_oci_iam_passwords.sh
```

To set one user:

```bash
./set_oci_iam_passwords.sh --user marvin
```

The script prompts securely by default. You can pass `--password`, but that may leave the password in shell history.

## Custom Claim Fallback

Some tenancies do not allow `oci raw-request` to create identity-domain custom claims. If `00_setup_oci_iam.sh` prints a warning, create this custom access-token claim in OCI IAM:

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

This claim is required because database data roles map to OCI IAM group display names:

```sql
CREATE OR REPLACE DATA ROLE hrapp_employees
  MAPPED TO 'IAM_OAUTH_GROUP=EMPLOYEES';

CREATE OR REPLACE DATA ROLE hrapp_managers
  MAPPED TO 'IAM_OAUTH_GROUP=MANAGERS';
```

Without the `group` claim in the OAuth2 access token, authentication can succeed while data roles do not activate.

## Required Lab Variables

For the normal lab path, you do not collect these manually. Run `./00_setup_oci_iam.sh`; it creates the OCI IAM applications, groups, optional demo users, custom group claim, and writes `.oci-iam-data-grants.env`.

### Where to Find Each Value

| Variable | Where it comes from | Notes |
|---|---|---|
| `OCI_DB_APP_ID` | Created by `00_setup_oci_iam.sh` as the DB resource app client/application ID | Used as `app_id` in `identity_provider_oauth_config`. |
| `OCI_DOMAIN_URL` | Discovered from `~/.oci/config` tenancy, preferring the `Default` domain | Domain URL looks like `https://idcs-...identity.oraclecloud.com:443`. Set `OCI_DOMAIN_NAME` to choose another domain by display name. |
| `OCI_DB_CLIENT_ID` | Created by `00_setup_oci_iam.sh` on the DB app | Stored in `OCI_IAM_DOMAIN_DB_CRED$` so the DB can retrieve signing metadata. |
| `OCI_DB_CLIENT_SECRET` | Created by `00_setup_oci_iam.sh` on the DB app | Treat it like a password. The env file is written mode `600`. |
| `OCI_CLIENT_ID` | Created by `00_setup_oci_iam.sh` as the interactive client app ID | Used in `tnsnames.ora` as `OCI_CLIENT_ID`. |
| `OCI_CLIENT_SECRET` | Created by `00_setup_oci_iam.sh` on the interactive client app | Used by `get_oci_oauth_token.sh` to exchange an authorization code for an OAuth2 access token. |
| `OCI_AUDIENCE` | Created by `00_setup_oci_iam.sh`, default `OracleDB` | Used in `tnsnames.ora` as `OCI_AUDIENCE`. |
| `OCI_SCOPE` | Created by `00_setup_oci_iam.sh`, default `OracleDBDB_ACCESS_SCOPE` | Used in `tnsnames.ora` as `OCI_SCOPE`. |
| `OCI_REDIRECT_URI` | Created by `00_setup_oci_iam.sh`, default `http://localhost:8888/callback` | Used in the OAuth2 authorization-code flow. |
| `OCI_USERNAME_DOMAIN` | Optional lab user naming convention | Empty by default, so lab users are `marvin` and `emma`. Set it to `example.com` for `marvin@example.com` / `emma@example.com`. |
| `PDB_NAME` | Your Oracle database environment | The PDB service used for SQL*Plus connections. This lab defaults to `FREEPDB1`. |

```bash
source ./.oci-iam-data-grants.env
```

## Script Order

```bash
./00_setup_oci_iam.sh
source ./.oci-iam-data-grants.env
./01_configure_db_identity_provider.sh
./02_configure_network.sh
./03_create_hr_schema.sh
./04_create_data_roles_and_grants.sh
./set_oci_iam_passwords.sh
./get_oci_oauth_token.sh
./05_verify_as_marvin.sh
./get_oci_oauth_token.sh
./06_verify_as_emma.sh
./07_verify_security_boundary.sh
```

Cleanup:

```bash
./08_cleanup_db.sh
./09_cleanup_oci_iam.sh
```

To skip the OCI IAM cleanup confirmation prompt:

```bash
./09_cleanup_oci_iam.sh -f
# or
./09_cleanup_oci_iam.sh --DELETE
```

## Reference

Oracle OCI CLI quickstart: <https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm>
