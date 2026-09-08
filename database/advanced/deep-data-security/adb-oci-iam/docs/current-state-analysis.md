# Current-state analysis: `adb-oci-iam`

## Scope and baseline

This Phase 0 analysis covers every source file in `adb-oci-iam` as inspected on
2026-07-20.  Images and the published ZIP are distribution assets; they create
no resources.  No OCI, database, or Identity Domain command was run for this
analysis.

The lab is a Cloud Shell-oriented, numbered Bash workflow for direct OCI IAM
OAuth access-token login to an Autonomous AI Database (ADB).  It does not have
Terraform, a Resource Manager stack, an application runtime, Select AI,
Generative AI, MCP, Object Storage, or an external table.

The primary flow is:

```text
00_setup_adb.sh
  -> .adb-oci-iam.env + wallet + OCI IAM resources + ADB
  -> 01_enable_oci_iam.sh
  -> 02_create_hr_schema.sh
  -> 03_create_data_roles_and_grants.sh
  -> verify_db_setup.sh
  -> 04_get_iam_oauth_token.sh
  -> 05_verify_as_marvin.sh | 06_verify_as_emma.sh
  -> 07_cleanup_adb_lab.sh
```

`adb-oci-iam.md` documents that flow.  `check_oci_iam_login_readiness.sh`,
`set_oci_iam_passwords.sh`, and `decode_token.sh` are supporting diagnostics
or operator utilities.  Shared libraries are `lib_adb.sh`,
`lib_oci_profile.sh`, `lib_lab_instance.sh`, and `lib_token_check.sh`.

## Repository and dependency map

| Component | Depends on | Produces or verifies |
| --- | --- | --- |
| `00_setup_adb.sh` | OCI CLI, Python 3, unzip, OCI CLI profile, Identity Domain access | ADB or reuse decision, wallet, OAuth apps, groups, optional users and `.adb-oci-iam.env` |
| `01_enable_oci_iam.sh` | environment file, wallet, SQL*Plus | OCI IAM external authentication and database credential |
| `02_create_hr_schema.sh` | environment file, SQL*Plus | `HR` schema and `HR.EMPLOYEES` sample data |
| `03_create_data_roles_and_grants.sh` | environment file, SQL*Plus | data roles, end-user context, package, data grants |
| `04_get_iam_oauth_token.sh` | environment file, wallet, Python 3, browser or pasted callback | OAuth access token and wallet OAuth settings |
| `05_verify_as_marvin.sh` | environment file, token, SQL*Plus | manager/employee-role result set |
| `06_verify_as_emma.sh` | environment file, token, SQL*Plus | employee-role result set |
| `verify_db_setup.sh` | environment file, SQL*Plus | ADB identity settings, credential, HR row count, data roles |
| `07_cleanup_adb_lab.sh` | environment file as needed, SQL*Plus and OCI CLI for selected actions | optional deletion of lab objects/resources/local artifacts |

`lib_adb.sh` centralizes required ADB environment checks, wallet checks, safe
command display, and the ADMIN SQL*Plus connection.  `lib_oci_profile.sh`
selects the OCI CLI profile and wraps OCI calls.  `lib_lab_instance.sh`
persists a machine-scoped instance identifier used in names.  `lib_token_check.sh`
decodes enough JWT claims to reject a token for the wrong persona or missing
group before SQL*Plus connects.

## Resources created or reused

| Layer | Created or reused by current lab | Ownership observation |
| --- | --- | --- |
| ADB | Autonomous AI Database Serverless, named from `DB_NAME`; matching available ADB can be reused | Current reuse is name/prefix based, not an explicit ownership manifest. |
| ADB wallet | Generated ZIP and extracted wallet directory | Local secret material; generated for both created and reused ADB. |
| Identity Domain apps | OAuth resource application and public OAuth client; resource app has database scope and a group claim | App names include the instance ID on create, but the reuse path changes names and cleanup can search by name fragment. |
| Identity Domain groups | `EMPLOYEES`, `MANAGERS` by default | Existing matching groups are reused. |
| Identity Domain users | `marvin`, `emma` by default, controlled by `CREATE_DEMO_USERS` | Existing matching users are reused; cleanup must not assume they are lab-owned. |
| Group memberships | Marvin: employees and managers; Emma: employees | Existing memberships are retained. |
| Local token cache | `${OCI_TOKEN_DIR}/token`, defaulting to `$HOME/.oci/adb-oci-iam` | Contains a bearer token and is deleted only on an explicit cleanup option. |

No bucket, object, Vault secret, dynamic group, OCI policy, network resource,
container runtime, Resource Manager stack, Select AI profile, MCP server, or
Generative AI resource exists today.

## Database objects created

| Script | Objects or configuration |
| --- | --- |
| `01_enable_oci_iam.sh` | OCI IAM external authentication configuration through `DBMS_CLOUD_ADMIN`; credential `OCI_IAM_DOMAIN_DB_CRED$` |
| `02_create_hr_schema.sh` | user `HR` (no authentication); table `HR.EMPLOYEES`; seven sample rows |
| `03_create_data_roles_and_grants.sh` | roles `EMPLOYEE_CONTEXT_ADMIN`, `DIRECT_LOGON_ROLE`; data roles `HRAPP_EMPLOYEES`, `HRAPP_MANAGERS`; end-user context `HR.EMP_CTX`; package `HR.CTX_PKG`; data grants `HR.HRAPP_EMPLOYEES_ACCESS`, `HR.EMPLOYEE_CONTEXT_GRANT`, `HR.HRAPP_MANAGER_ACCESS` |

The current direct-login authorization proof is well scoped: Marvin receives
the employee and manager data roles; Emma receives only the employee data role.
The proof depends on OCI IAM token claims reaching the database's direct OAuth
login path.  It does **not** prove that an application, pooled connection,
managed MCP server, or any other intermediary can establish the same context.

## Environment variables and generated files

The setup environment file persists: `OCI_COMPARTMENT`, `OCI_PROFILE_NAME`,
`ROOT_COMP_ID`, `DB_NAME`, `DB_DISPLAY_NAME`, `DB_VERSION`,
`ADB_IS_FREE_TIER`, `ADB_LICENSE_MODEL`, `ADB_MAINTENANCE_SCHEDULE_TYPE`,
`ADB_OCID`, `ADB_SERVICE`, `ADMIN_PWD`, `WALLET_PWD`, `WALLET_DIR`,
`TNS_ADMIN`, `OCI_TOKEN_DIR`, `TENANCY_OCID`, `OCI_DOMAIN_URL`,
`OCI_DB_APP_ID`, `OCI_DB_CLIENT_ID`, `OCI_DB_CLIENT_SECRET`,
`OCI_CLIENT_APP_ID`, `OCI_AUDIENCE`, `OCI_SCOPE`, `OCI_REDIRECT_URI`,
`OCI_REDIRECT_URIS`, `ADB_OCI_IAM_LAB_INSTANCE_ID`, `OCI_DB_APP_NAME`,
`OCI_CLIENT_APP_NAME`, `OCI_IAM_EMPLOYEE_GROUP`, `OCI_IAM_MANAGER_GROUP`,
`EMPLOYEES_OCID`, `MANAGERS_OCID`, `OCI_USERNAME_DOMAIN`, `MARVIN_USERNAME`,
`EMMA_USERNAME`, `MARVIN_ID`, `EMMA_ID`, and `CREATE_DEMO_USERS`.

Inputs not necessarily persisted include `OCI_PROFILE`, `OCI_CLI_PROFILE`,
`OCI_TENANCY`, `DB_NAME_REUSE_PREFIX`, `OCI_OPEN_BROWSER`, `OCI_HEADLESS`,
`OCI_OAUTH_TIMEOUT_SECONDS`, and `DBSEC_LAB_STATE_DIR`.

Generated local files/directories are `.adb-oci-iam.env` (mode 0600),
`.adb-oci-iam.instance`, `.oci-iam-setup/`, the wallet directory and wallet
ZIP, `sqlnet.ora.bak-oauth`, `sqlnet.ora.bak-wallet-dir`, and the OAuth token
directory.  The checked-in `.gitignore` omits the environment file and ZIPs,
but does not currently ignore `.adb-oci-iam.instance` or `.oci-iam-setup/`.

## Setup-to-cleanup symmetry

| Setup asset | Current cleanup path | Symmetry status |
| --- | --- | --- |
| HR schema, data roles, grants, local roles | `--delete-db-objects` | Covered; intended to tolerate already-absent objects. |
| ADB | `--delete-adb` | Covered only when selected; unsafe to treat as lab-owned after reuse without an ownership record. |
| OAuth apps | `--delete-iam-apps`; broad fallback `--delete-all-lab-apps` | Partial; name-fragment matching can reach beyond one invocation. |
| Groups and users | `--delete-iam-groups`, `--delete-iam-users` | Partial; IDs are saved, but setup can reuse pre-existing groups/users. |
| Group memberships | none | Missing; retained if users/groups are preserved. |
| Wallet, env, setup work, token | `--delete-local-files` | Covered when selected; `.adb-oci-iam.instance` and SQL*Plus backup files remain. |
| Identity-provider configuration / credential | none | Missing; database cleanup does not disable external auth or drop `OCI_IAM_DOMAIN_DB_CRED$`. |

## Proposed ownership boundaries

Terraform should own only declarative OCI infrastructure after provider-schema
validation: a newly requested ADB, Object Storage bucket, application runtime,
networking, dynamic groups, compartment-scoped policies, logging, and optional
Vault resources.  It must record whether the ADB is created by Terraform or
supplied by the student; it must never destroy a supplied ADB.

Shell should retain OCI CLI/Identity Domain work until the provider support is
verified end to end: discovery, OAuth app configuration, claims, users,
groups, membership, wallet retrieval, token exercise, SQL client selection,
database SQL execution, post-provision verification, and local generated state.
Shell must use an explicit resource manifest for resources it creates and must
not infer ownership from names.

Database objects remain SQL-owned.  A future shared database helper may prefer
SQLcl when present and fall back to SQL*Plus, but Phase 0 retains SQL*Plus and
does not alter any command.

## Migration plan preserving commands

1. Add static checks around the numbered script surface and shell syntax.
2. Add `bin/labctl` as wrappers only; each existing numbered command remains
   executable and its current arguments stay valid.
3. Add `.lab/resource-manifest.json` for new script-owned resources, then use
   it for new cleanup paths.  Do not retrofit destructive ownership claims to
   old name-based resources without an explicit adoption step.
4. Add Terraform only for newly declared infrastructure resources; preserve
   current OCI CLI creation/reuse behavior until a migration has live tests.
5. Add resource-manager packaging after local Terraform validation.
6. Build and test the fixed-query application-mediated DDS proof, including
   pool size one and alternating-persona isolation, before any Select AI/MCP/
   Generative AI work.

## Risks and unsupported assumptions

- The default ADMIN and wallet passwords are present in the script and stored
  in the local environment file.  Do not propagate this pattern into new work.
- Reuse is based on names and can select an existing ADB, app, group, or user;
  current cleanup cannot prove ownership for all of them.
- The setup creates/updates Identity Domain configuration before the ADB is
  created, so a later ADB failure can leave identity resources behind.
- `02_create_hr_schema.sh` deliberately drops and recreates `HR`; it is a
  destructive lab action, not a safe update for a shared database.
- The cleanup code does not restore `sqlnet.ora`, remove the instance file, or
  revert OCI IAM database external-authentication configuration.
- The demonstrated identity propagation is direct SQL*Plus OAuth login only.
  There is no verified basis to claim that managed MCP, Select AI, or an
  application connection pool preserves Deep Data Security identity.

## First implementation change

`tests/phase0/check_legacy_command_contract.sh` is a non-mutating regression
check.  It parses every existing shell script with `bash -n`, verifies the
numbered commands and key direct-login contract markers remain present, and
does not contact OCI or a database.  This is intentionally smaller than the
Phase 1 test suite and protects the current lab while wrappers are introduced.
