# DeepSec MCP Oracle Corporate Base DB System Terraform Starter

Estimated Time: 5 minutes

### Objectives

Use this page to review the Base Database System Terraform package inputs, provisioning model, and validation steps.

This package provisions Database Tools MCP Server support resources for an existing Oracle Base Database System.

It is designed for Oracle corporate tenancy testing where the database already exists and where the stack should not create workshop IAM users, groups, or new databases.

## Target Database

Default target DB System OCID:

```text
ocid1.dbsystem.oc1.iad.replace
```

Default target database OCID:

```text
ocid1.database.oc1.iad.replace
```

Default Easy Connect string:

```text
replace-host.example.com:1521/replace-service.example.com
```

The DB System OCID identifies the infrastructure. Database Tools still needs the database connect string, a database user, a password stored in Vault, and a reachable network path.

## What This Package Provisions

- participant compartments
- per-participant Object Storage buckets for MCP Server storage
- optional Vault/key/secret for Database Tools credentials
- optional per-participant Database Tools connections that point to the existing Base Database
- optional per-participant MCP Servers
- optional participant policies referencing existing corporate groups; disabled by default

## What This Package Does Not Provision

- IAM users
- IAM groups
- identity-domain users
- new Autonomous Databases
- new Base Database Systems
- database schemas, users, grants, or seed data inside the existing database

## Required Inputs for MCP Creation

- `base_db_connection_string`
- `database_tools_connection_user_name`
- `database_tools_connection_password`, when this stack creates the Vault secret
- `database_tools_existing_password_secret_id`, when using an existing Vault secret instead
- `database_tools_private_endpoint_ocid`, if Database Tools needs a private network path to the DB System listener
- `identity_domain_ocid`, when creating MCP Servers

## Recommended First Apply

Start with the defaults:

```hcl
create_database_tools_vault_secret      = false
create_database_tools_connections       = false
create_mcp_servers                      = false
enable_participant_compartment_policies = false
enable_tenancy_policies                 = false
```

This creates only participant compartments and Object Storage buckets.

## Database Tools and MCP Apply

After you confirm network reachability and credentials:

```hcl
create_database_tools_vault_secret = true
create_database_tools_connections  = true
create_mcp_servers                 = true
identity_domain_ocid               = "ocid1.domain.oc1..replace"
database_tools_connection_user_name = "WORKSHOP_USER"
database_tools_connection_password  = "replace-with-real-password"
```

If the database listener is private, set:

```hcl
database_tools_private_endpoint_ocid = "ocid1.databasetoolsprivateendpoint.oc1..replace"
```

## Existing Secret Alternative

If the database password already exists in OCI Vault:

```hcl
create_database_tools_vault_secret       = false
database_tools_existing_password_secret_id = "ocid1.vaultsecret.oc1..replace"
create_database_tools_connections        = true
```

## Related Resource

The stack defaults the Database Tools related resource to:

```hcl
database_tools_related_resource_entity_type = "DATABASE"
database_tools_related_resource_ocid        = null
```

With `database_tools_related_resource_ocid = null`, Terraform uses `base_database_ocid`, then falls back to `base_db_system_ocid`. If the service requires DB System association instead, set:

```hcl
database_tools_related_resource_entity_type = "DB_SYSTEM"
database_tools_related_resource_ocid        = "ocid1.dbsystem.oc1.iad.replace"
```

## Participants

By default, the stack generates participant keys such as `U12345`. It does not generate or output `U12345a` or `U12345b` users. Use the optional `participants` map only when you need explicit participant display names.

The variable type is:

```hcl
map(object({ display_name = optional(string) }))
```

## Policies

Participant group policies are disabled by default. Set `enable_participant_compartment_policies = true` only if you have an existing OCI group naming pattern and permission to create policies for it.

Tenancy-scope policies are disabled by default because many Resource Manager principals can manage resources in the sandbox parent compartment but not in the tenancy root compartment.

Database Tools and Generative AI policy statements are disabled by default. Enable them only after confirming the exact policy resource types for the tenancy and region.

## Validate

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
```

## Important Notes

- Do not commit real passwords, client secrets, wallet files, or private keys.
- Use a least-privilege database user rather than `ADMIN` for workshop access.
- Keep one participant per compartment.
- Use tags for teardown: workshop, participant, reservation, ttl.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
