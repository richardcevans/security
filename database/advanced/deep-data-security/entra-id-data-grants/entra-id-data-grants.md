# Identity-Aware Database Access with Microsoft Entra ID and Oracle Deep Data Security

## Introduction

This lab configures Oracle AI Database 26ai to accept Microsoft Entra ID tokens,
then uses Oracle Deep Data Security data roles and data grants to enforce
different row and column access for Marvin and Emma.

Marvin and Emma run the same SQL against the same HR table. Marvin is a manager
and sees himself plus direct reports. Emma is an employee and sees only herself.
The database enforces the difference from Entra ID app-role claims.

> **Warning:** Run this lab only in an isolated demo, sandbox, or non-production environment. The steps can create or modify identity applications, users, groups, database identity-provider settings, network files, data roles, data grants, audit policies, and other security configuration. Do not run the lab against production tenancies, tenants, databases, applications, or directories, and do not overwrite existing policies or configuration. Follow your organization's change control, approval, and security procedures before adapting any step outside a lab environment.

The detailed security notes, manual portal fallback, rollback commands, and
extended troubleshooting have been moved to
[`entra-id-data-grants-reference.md`](./entra-id-data-grants-reference.md).

Estimated Time: 60 minutes

### Objectives

In this lab, you will:

- Configure Microsoft Entra ID applications and app roles for database access.
- Configure Oracle AI Database 26ai to validate Entra ID tokens.
- Create Deep Data Security data roles and data grants.
- Verify that Marvin and Emma see different data through the same SQL.

## What This Lab Does

- Creates or reuses Microsoft Entra ID app registrations and enterprise apps.
- Creates Entra app roles `EMPLOYEES` and `MANAGERS`.
- Optionally assigns Marvin and Emma to the app roles.
- Configures Oracle AI Database 26ai for Entra ID token authentication.
- Configures a TCPS `hrdb` connection for browser-based login.
- Creates an HR schema with sample employee data.
- Creates Deep Data Security data roles and data grants.
- Verifies Marvin and Emma see different data from the same SQL.

### Prerequisites

- You are running on the DBSec-Lab VM as OS user `oracle`.
- Oracle AI Database 26ai Free is installed and running.
- You can run `sqlplus / as sysdba` locally.
- You can administer the Microsoft Entra tenant used for the lab.
- Azure CLI is installed, or you can install it.
- Marvin and Emma exist in Entra ID, or your Entra admin can create them.
- Browser login is available from the lab desktop or NoVNC session.

## Important Defaults

| Setting | Default |
| --- | --- |
| CDB SID | `FREE` |
| PDB | `FREEPDB1` |
| TNS alias | `hrdb` |
| Machine instance ID | generated once in `~/.dbsec-labs/instances/dbsec-lab-machine.instance` |
| DB resource app | `Oracle Database 26ai - FREEPDB1 - <machine-instance-id>` |
| Browser client app | `Oracle Client Interactive - FREEPDB1 - <machine-instance-id>` |
| Application ID URI | `https://<DOMAIN_NAME>/FREEPDB1-<machine-instance-id>` |
| OAuth scope | `session:scope:connect` |
| Marvin UPN | `marvin@<DOMAIN_NAME>` |
| Emma UPN | `emma@<DOMAIN_NAME>` |
| Marvin role assignments | `EMPLOYEES`, `MANAGERS` |
| Emma role assignments | `EMPLOYEES` |

Optional overrides:

```bash
<copy>
export DB_SID=FREE
export PDB_NAME=FREEPDB1
export DOMAIN_NAME=example.onmicrosoft.com
export ENTRA_LAB_INSTANCE_ID=my-dbsec-lab
export MARVIN_UPN=marvin@example.onmicrosoft.com
export EMMA_UPN=emma@example.onmicrosoft.com
export CREATE_APP_ROLE_ASSIGNMENTS=1
</copy>
```

Set `CREATE_APP_ROLE_ASSIGNMENTS=0` if your Entra administrator wants to assign
users to app roles manually.

By default, `02_setup_entra_id.sh` generates a machine-scoped
`ENTRA_LAB_INSTANCE_ID` the first time it runs and saves it in
`~/.dbsec-labs/instances/dbsec-lab-machine.instance`. Other DBSec-Lab labs use
the same machine ID, so one VM reuses one Entra DB app and one Entra client app
for `FREEPDB1` instead of creating lab-specific duplicates. Set
`ENTRA_LAB_INSTANCE_ID` before Task 2 only if you want a predictable app-name
suffix.

## Task 0: Download The Lab Files

1. Open a terminal as OS user `oracle`, move to your Deep Data Security labs directory,
   download the ZIP, and unzip it.

    ```bash
    <copy>
    mkdir -vp $DBSEC_LABS/deep-data-security
    cd $DBSEC_LABS/deep-data-security
    wget -O entra-id-data-grants.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/aSXtPT18-67-gR7BdvSd5VtxmxemrI5KpRkoMYoN6S22aUhRnrB5O12ZaoXbjgLE/n/oradbclouducm/b/dbsec_public/o/entra-id-data-grants.zip
    unzip -o entra-id-data-grants.zip
    cd entra-id-data-grants
    ls
    </copy>
    ```

Use `unzip -o` when refreshing the lab files. Do not use `unzip -f` for lab
updates because it will not add new files.

Important files:

| File | Purpose |
| --- | --- |
| `02_setup_entra_id.sh` | Creates or reuses Entra apps, roles, permissions, and assignments |
| `02_verify_entra_id_setup.sh` | Verifies Entra app objects and role setup |
| `03_preflight.sh` | Checks local database, listener tools, and browser readiness |
| `04_configure_db_identity_provider.sh` | Configures database Entra ID parameters |
| `05_configure_network.sh` | Configures TCPS listener, wallet, `sqlnet.ora`, and `tnsnames.ora` |
| `06_create_hr_schema.sh` | Creates the HR schema and employee rows |
| `07_create_data_roles_and_grants.sh` | Creates data roles, data grants, and end user context |
| `08_verify_db_setup.sh` | Verifies database-side setup |
| `09_verify_as_marvin.sh` | Verifies Marvin manager access |
| `10_verify_as_emma.sh` | Verifies Emma employee access |
| `11_cleanup.sh` | Cleans up database objects and network changes |
| `11_cleanup_entra_id.sh` | Deletes lab-created Entra app registrations and enterprise apps |

## Task 1: Install Azure CLI And Sign In

1. Install Azure CLI. Azure CLI is required for `02_setup_entra_id.sh`.

    Install Azure CLI without updating any other configured repositories:

    ```bash
    <copy>
    OS_MAJOR=$(rpm -E %{rhel})
    case "$OS_MAJOR" in
      8)
        MS_REPO_RHEL_VERSION="8"
        MS_KEY_URL="https://packages.microsoft.com/keys/microsoft.asc"
        ;;
      9)
        MS_REPO_RHEL_VERSION="9.0"
        MS_KEY_URL="https://packages.microsoft.com/keys/microsoft.asc"
        ;;
      10)
        MS_REPO_RHEL_VERSION="10"
        MS_KEY_URL="https://packages.microsoft.com/keys/microsoft-2025.asc"
        ;;
      *)
        echo "Unsupported Oracle Linux/RHEL-compatible major version: $OS_MAJOR"
        exit 1
        ;;
    esac
    sudo rpm --import "$MS_KEY_URL"
    curl -fL -o /tmp/packages-microsoft-prod.rpm "https://packages.microsoft.com/config/rhel/${MS_REPO_RHEL_VERSION}/packages-microsoft-prod.rpm"
    sudo rpm -Uvh --replacepkgs /tmp/packages-microsoft-prod.rpm
    sudo dnf clean metadata
    sudo dnf makecache --disablerepo='*' --enablerepo='packages-microsoft-com-prod'
    sudo dnf install -y azure-cli --nobest --disablerepo='*' --enablerepo='packages-microsoft-com-prod'
    az version
    </copy>
    ```

2. Sign in:

    ```bash
    <copy>
    az login
    </copy>
    ```

3. Verify the selected tenant:

    ```bash
    <copy>
    az account show --query "{tenantId:tenantId,name:name,user:user.name}" --output table
    </copy>
    ```

## Task 2: Configure Microsoft Entra ID

1. Create or reuse the Entra DB resource application, browser client application,
   enterprise apps, app roles, scopes, and role assignments.

2. Load the Oracle AI Database 26ai Free environment so the generated Entra app
   names use `FREEPDB1` plus this lab directory's unique instance ID.

    ```bash
    <copy>
    source $DBSEC_ADMIN/setEnv-db23free.sh FREE FREEPDB1
    </copy>
    ```

3. Run the Entra ID setup script:

    ```bash
    <copy>
    ./02_setup_entra_id.sh
    </copy>
    ```

4. Review the generated environment file:

    ```bash
    <copy>
    cat ./.entra-id-data-grants.env
    </copy>
    ```

5. Load the generated environment file:

    ```bash
    <copy>
    source ./.entra-id-data-grants.env
    </copy>
    ```

    The script writes `.entra-id-data-grants.env`. Load it before running later
    tasks.

6. Verify the Entra setup:

    ```bash
    <copy>
    ./02_verify_entra_id_setup.sh
    </copy>
    ```

Expected setup:

| User | App roles |
| --- | --- |
| Marvin | `EMPLOYEES`, `MANAGERS` |
| Emma | `EMPLOYEES` |

If your tenant policies prevent automated app creation or assignment, use the
manual portal fallback in
[`entra-id-data-grants-reference.md`](./entra-id-data-grants-reference.md).

## Task 3: Run Database Preflight

1. Run the preflight checks.

    ```bash
    <copy>
    ./03_preflight.sh
    </copy>
    ```

The preflight confirms the local database, PDB, SQL*Plus, listener utilities,
and browser-related environment are ready for the lab.

## Task 4: Configure The Database Identity Provider

1. Configure the PDB to validate Entra ID tokens.

    ```bash
    <copy>
    ./04_configure_db_identity_provider.sh
    </copy>
    ```

This task sets the database identity provider parameters from
`.entra-id-data-grants.env`. It must be run before browser-based login can work.

## Task 5: Configure TCPS Network Access

1. Configure the local wallet, listener, `sqlnet.ora`, and `tnsnames.ora` entry used
   by browser-based Entra ID authentication.

    ```bash
    <copy>
    ./05_configure_network.sh
    </copy>
    ```

2. Note the `hrdb` TNS alias. Verification scripts connect with:

    ```bash
    <copy>
    sqlplus /@hrdb
    </copy>
    ```

## Task 6: Create The HR Schema

1. Create the schema-only HR owner and sample employee data.

    ```bash
    <copy>
    ./06_create_hr_schema.sh
    </copy>
    ```

`HR` is created with `NO AUTHENTICATION`; end users do not log in as `HR`.
The `user_name` values are set to Entra ID user names such as
`marvin@<DOMAIN_NAME>` and `emma@<DOMAIN_NAME>`.

## Task 7: Create Data Roles And Data Grants

1. Create the Deep Data Security data roles, data grants, and end user context.

    ```bash
    <copy>
    ./07_create_data_roles_and_grants.sh
    </copy>
    ```

The script creates:

- `HRAPP_EMPLOYEES`, mapped to Entra app role `EMPLOYEES`
- `HRAPP_MANAGERS`, mapped to Entra app role `MANAGERS`
- `DIRECT_LOGON_ROLE`, carrying `CREATE SESSION`
- Row and column data grants on `HR.EMPLOYEES`
- End user context used to identify a manager's direct reports

## Task 8: Verify Database Setup

1. Confirm the identity provider, network alias, HR rows, data roles, and data
   grants are in place.

    ```bash
    <copy>
    ./08_verify_db_setup.sh
    </copy>
    ```

2. Review the expected highlights:

    ```text
    identity_provider_type    AZURE_AD
    HR employee rows          7
    HRAPP_EMPLOYEES           azure_role=EMPLOYEES
    HRAPP_MANAGERS            azure_role=MANAGERS
    ```

## Task 9: Verify Marvin

1. Run the Marvin verification script. When the browser opens, sign in as Marvin.

    ```bash
    <copy>
    ./09_verify_as_marvin.sh
    </copy>
    ```

2. Review the expected Marvin result:

- Token identity is Marvin.
- Active data roles include `HRAPP_EMPLOYEES` and `HRAPP_MANAGERS`.
- Marvin sees 4 rows: Marvin, Emma, Charlie, and Dana.
- Marvin can see his own SSN.
- SSN is hidden for direct reports.

## Task 10: Verify Emma

1. Prepare a separate browser session for Emma. If the browser reuses Marvin's
   session, close browser windows, sign out, or use a private/incognito browser
   session.

2. Run the Emma verification script. When the browser opens, sign in as Emma.

    ```bash
    <copy>
    ./10_verify_as_emma.sh
    </copy>
    ```

3. Review the expected Emma result:

- Token identity is Emma.
- Active data roles include `HRAPP_EMPLOYEES` only.
- Emma sees 1 row: Emma.
- Emma can view her own SSN and salary.
- Emma can update only her phone number.

## Task 11: Clean Up

1. Clean up database objects and restore local network files:

    ```bash
    <copy>
    ./11_cleanup.sh
    </copy>
    ```

2. If the Entra applications were created only for this lab, remove them too:

    ```bash
    <copy>
    ./11_cleanup_entra_id.sh
    </copy>
    ```

## Troubleshooting Summary

Detailed troubleshooting moved to
[`entra-id-data-grants-reference.md`](./entra-id-data-grants-reference.md).
Start with these checks:

    ```bash
    <copy>
    source ./.entra-id-data-grants.env
    ./02_verify_entra_id_setup.sh
    ./08_verify_db_setup.sh
    tnsping hrdb
    </copy>
    ```

Common issues:

| Symptom | Check |
| --- | --- |
| Browser logs in as the wrong user | Close browser windows, sign out, or use private/incognito mode |
| Marvin sees only his own row | Confirm Marvin has `MANAGERS`; rerun browser login |
| Emma has manager access | Remove `MANAGERS` from Emma and use a fresh browser session |
| `sqlplus /@hrdb` cannot resolve | Rerun `./05_configure_network.sh` and check `tnsping hrdb` |
| No data roles activate | Verify Entra app role assignments and database role mappings |

## Reference Material

The following sections were moved to
[`entra-id-data-grants-reference.md`](./entra-id-data-grants-reference.md):

- Do Not Do This
- Security Model
- Threat Model
- Security-Critical Claims
- Least Privilege Design
- Secrets And Session Inventory
- Browser Session Handling
- Security Validation Checklist
- DBA Production Caution
- Network File Backups And Restore
- Manual portal fallback tasks
- Rerun Safety
- Database Parameter Rollback
- Audit And Log Locations
- Troubleshooting
- Key Differences: Entra ID vs. Direct Password

## Learn More

- [Microsoft identity platform documentation](https://learn.microsoft.com/entra/identity-platform/)
- [Oracle Database integration with Microsoft Entra ID](https://docs.oracle.com/en/database/oracle/oracle-database/26/dbseg/)
- [Oracle Deep Data Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/)

You may now [proceed to the next lab](#next).

## Acknowledgements

- **Author** - Richard Evans, Database Security Product Management
