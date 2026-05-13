# OCI IAM Data Grants Lab

This lab shows identity-aware database access with OCI IAM OAuth2 and Oracle Deep Data Security. The full walkthrough is in [oci-iam-data-grants.md](./oci-iam-data-grants.md).

## Install OCI CLI

The verification flow uses `TOKEN_AUTH=OCI_INTERACTIVE`, so the database client needs OCI CLI configuration on the machine where you run `sqlplus /@hrdb`.

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

If you use a non-default profile or config file, export these before running `02_configure_network.sh`:

```bash
export OCI_CONFIG_FILE=/home/oracle/.oci/config
export OCI_PROFILE=DEFAULT
```

The generated `hrdb` TNS entry will include those values when present.

## Required Lab Variables

Before running the database setup scripts, collect these values from OCI IAM and your database environment.

### Where to Find Each Value

| Variable | Where it comes from | Notes |
|---|---|---|
| `OCI_DB_APP_ID` | OCI Console -> Identity & Security -> Domains -> your domain -> Integrated applications -> your database confidential application | Use the database application identifier/client application value that appears in the token as `resource_app_id`. This is the value configured as `app_id` in `identity_provider_oauth_config`. |
| `OCI_DOMAIN_URL` | OCI Console -> Identity & Security -> Domains -> your domain -> Overview | Copy the Domain URL. It looks like `https://idcs-...identity.oraclecloud.com:443`. This must match the token issuer/domain. |
| `OCI_DB_CLIENT_ID` | OCI Console -> Domains -> your domain -> Integrated applications -> your database confidential application -> OAuth configuration | Copy the OAuth Client ID for the database confidential application. The database stores this in `OCI_IAM_DOMAIN_DB_CRED$` so it can retrieve signing metadata. |
| `OCI_DB_CLIENT_SECRET` | Same OAuth configuration page as `OCI_DB_CLIENT_ID` | Use Show secret / Copy secret. Treat it like a password. |
| `OCI_USERNAME_DOMAIN` | Your lab user naming convention | Use the domain suffix that makes the sample rows match `ORA_END_USER_CONTEXT.username`, for example `example.com` if Marvin logs in as `marvin@example.com`. |
| `PDB_NAME` | Your Oracle database environment | The net service name or PDB service used for SQL*Plus connections, for example `pdb1`. |

```bash
export OCI_DB_APP_ID=<your-oci-iam-database-application-id>
export OCI_DOMAIN_URL=<your-oci-iam-domain-url>
export OCI_DB_CLIENT_ID=<database-app-oauth-client-id>
export OCI_DB_CLIENT_SECRET=<database-app-oauth-client-secret>
export OCI_USERNAME_DOMAIN=<domain-used-in-lab-usernames>
export PDB_NAME=<your-pdb-name>
```

## Script Order

```bash
./01_configure_db_identity_provider.sh
./02_configure_network.sh
./03_create_hr_schema.sh
./04_create_data_roles_and_grants.sh
./05_verify_as_marvin.sh
./06_verify_as_emma.sh
./07_verify_security_boundary.sh
```

Cleanup:

```bash
./08_cleanup.sh
```

## Reference

Oracle OCI CLI quickstart: <https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm>
