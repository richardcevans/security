# DeepSec MCP Oracle Corporate Sandbox Terraform Starter

Estimated Time: 5 minutes

### Objectives

Use this page to review the corporate Terraform package inputs, provisioning model, and validation steps.

This package is a starter for LiveLabs sandbox provisioning for:

`DB Security - Deep Data Security with Autonomous Database and MCP Server Tools`

It is designed for Oracle corporate tenancy testing where you cannot create workshop IAM users. Each generated participant key gets isolated infrastructure, but this variant does not create or output restricted/privileged identity-domain users.

## Recommended Provisioning Model

Use two automation layers:

1. **LiveLabs/bootstrap layer**
   - Creates or owns the parent sandbox compartment.
   - Uses existing corporate identity and permissions.
   - Creates identity-domain app registrations, OAuth clients, app roles, and secrets.
   - Grants admin/provisioner policies.
   - Runs this Terraform package.

2. **Participant resource layer**
   - Creates one participant compartment per user.
   - Creates one ADB-S or Autonomous AI Database per participant.
   - Creates one Object Storage bucket per participant.
   - Creates least-privilege participant policies.
   - Seeds sample schema and Deep Data Security objects.
   - Creates Database Tools connection and MCP Server, if supported by the selected automation path.

## What This Package Provisions

This starter provisions the resources that are safe and Terraform-managed:

- participant compartments
- per-participant Object Storage buckets
- per-participant Autonomous Database instances
- optional per-participant policies referencing existing groups; disabled by default for corporate tenancy testing
- per-participant Database Tools MCP Servers when Database Tools connection OCIDs are supplied
- Resource Manager form metadata in `schema.yaml`, including a parent compartment picker and static option lists

## What Requires LiveLabs/OCI Confirmation

The following pieces are intentionally not hard-coded as Terraform resources until LiveLabs confirms provider support and naming:

- identity-domain groups or app roles
- OAuth client/app registration for each participant
- OCI Database Tools connection creation, because the final credential and secret handling pattern is environment-specific

Use `database_tools_connection_ids` to create MCP Servers from pre-created Database Tools connections. Use `scripts/create-mcp-server.sh` only as a fallback or troubleshooting hook.

## Why Not Give Users Manage Permissions?

Participants should not receive broad `manage` permissions. LiveLabs automation should create IAM, identity-domain, Database Tools, and database resources. Participants should mostly receive `read` and `use` permissions in their assigned compartment.

## Install Terraform on Ubuntu

Follow HashiCorp's current Ubuntu install instructions or use the package approved by LiveLabs. After installing:

```bash
terraform version
```

## Prepare Inputs

Copy the example tfvars file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit:

- `tenancy_ocid`
- `region`
- `parent_compartment_ocid`
- `participant_group_name_prefix`
- `participant_count`, `participant_prefix`, and `participant_start_number`
- `adb_admin_password`
- `adb_workload`, using OCI API values such as `OLTP` for Autonomous Transaction Processing or `DW` for Autonomous Data Warehouse
- `create_database_tools_vault_secret`, `create_database_tools_connections`, and `create_mcp_servers`, only for the second-pass Database Tools/MCP provisioning test
- `identity_domain_ocid`, selected from the Resource Manager identity-domain dropdown when `create_mcp_servers` is true
- `database_tools_connection_ids`, after Database Tools connections exist and only when `create_mcp_servers` is true

By default, the stack generates participant keys such as `U12345`. It does not generate or output `U12345a` or `U12345b` users. Use the optional `participants` map only when you need explicit participant names or database names.

Participant group policies are disabled by default. Set `enable_participant_compartment_policies = true` only if you have an existing OCI group naming pattern and permission to create policies for it.

Tenancy-scope participant policies are disabled by default because many Resource Manager principals can manage resources in the sandbox parent compartment but not in the tenancy root compartment. Set `enable_tenancy_policies = true` only when the apply principal can manage policies at the tenancy level.

Database Tools and Generative AI policy statements are also disabled by default so the first apply can create the core sandbox resources without depending on service-specific policy resource names. Enable `enable_database_tools_policy` and `enable_generative_ai_policy` after confirming the exact policy resource types for the tenancy and region.

## Second-Pass MCP Provisioning

After the base resources are created and the Autonomous Databases are available, you can test deeper pre-provisioning with these settings:

```hcl
create_database_tools_vault_secret = true
create_database_tools_connections  = true
create_mcp_servers                 = true
identity_domain_ocid               = "ocid1.domain.oc1..replace"
```

This creates one Vault/key/secret for the Database Tools password, one Database Tools connection per participant, and one MCP server per participant. For a smoke test the Database Tools connection can reuse the ADB admin password; for a production workshop, replace this with a least-privilege database user and an externally managed Vault secret.

If an external job generator writes a `var.env` or `.tfvars` file, include this line when you want generated participants:

```hcl
participants = {}
```

The variable type is `map(object({ db_name = string, display_name = optional(string) }))`. An explicit override must use Terraform map syntax, not JSON strings.

## Validate

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
```

## Package as Zip

From the `terraform/sandbox` directory:

```bash
zip -r deep-sec-mcp-sandbox-terraform.zip .
```

## Important Notes

- Do not commit real passwords, client secrets, wallet files, or private keys.
- Keep one participant per compartment.
- Use tags for teardown: workshop, participant, reservation, ttl.
- Use existing corporate identity artifacts. This variant does not create workshop identity-domain users or groups.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026
