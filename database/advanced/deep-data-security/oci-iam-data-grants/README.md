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

After that, the lab setup script can create the OCI IAM domain objects:

```bash
./00_setup_oci_iam.sh
source ./.oci-iam-data-grants.env
```

If you use a non-default OCI CLI profile or config file, export these first:

```bash
export OCI_CONFIG_FILE=/home/oracle/.oci/config
export OCI_PROFILE=DEFAULT
```

## Required Lab Variables

For the normal lab path, you do not collect these manually. Run `./00_setup_oci_iam.sh`; it creates the OCI IAM applications, groups, optional demo users, custom group claim, and writes `.oci-iam-data-grants.env`.

### Where to Find Each Value

| Variable | Where it comes from | Notes |
|---|---|---|
| `OCI_DB_APP_ID` | Created by `00_setup_oci_iam.sh` as the DB resource app client/application ID | Used as `app_id` in `identity_provider_oauth_config`. |
| `OCI_DOMAIN_URL` | Discovered from `~/.oci/config` tenancy, or set manually | Domain URL looks like `https://idcs-...identity.oraclecloud.com:443`. |
| `OCI_DB_CLIENT_ID` | Created by `00_setup_oci_iam.sh` on the DB app | Stored in `OCI_IAM_DOMAIN_DB_CRED$` so the DB can retrieve signing metadata. |
| `OCI_DB_CLIENT_SECRET` | Created by `00_setup_oci_iam.sh` on the DB app | Treat it like a password. The env file is written mode `600`. |
| `OCI_CLIENT_ID` | Created by `00_setup_oci_iam.sh` as the interactive client app ID | Used in `tnsnames.ora` as `OCI_CLIENT_ID`. |
| `OCI_AUDIENCE` | Created by `00_setup_oci_iam.sh`, default `OracleDB` | Used in `tnsnames.ora` as `OCI_AUDIENCE`. |
| `OCI_SCOPE` | Created by `00_setup_oci_iam.sh`, default `OracleDBDB_ACCESS_SCOPE` | Used in `tnsnames.ora` as `OCI_SCOPE`. |
| `OCI_USERNAME_DOMAIN` | Optional lab user naming convention | Empty by default, so lab users are `marvin` and `emma`. Set it to `example.com` for `marvin@example.com` / `emma@example.com`. |
| `PDB_NAME` | Your Oracle database environment | The net service name or PDB service used for SQL*Plus connections, for example `pdb1`. |

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
