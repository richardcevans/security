# Terraform baseline

This Phase 3 baseline manages only an Autonomous Database Serverless (ADB-S)
that Terraform creates itself. It can accept a user-supplied ADB-S OCID but
never imports, modifies, or destroys that database.

## Ownership modes

Choose exactly one mode in a private `terraform.tfvars` file:

- `create_autonomous_database = true`: Terraform creates and owns an ADB-S.
- `create_autonomous_database = false` with `autonomous_database_id`: Terraform
  only exposes the supplied OCID to later shell configuration phases.

The default is intentionally incomplete, so plan and apply fail until the
student makes an explicit ownership decision.

Do not put `adb_admin_password` in a committed variables file. Use
`TF_VAR_adb_admin_password` for a Terraform-managed database. Terraform state
can contain this sensitive value; use encrypted remote state before classroom
or Resource Manager use.

## Commands

```bash
../bin/labctl infra init
../bin/labctl infra validate
../bin/labctl infra plan -var-file=terraform.tfvars
```

`apply` requires explicit `--yes` and has not been run by this scaffold. A
Terraform destroy can affect only a database created in this Terraform state;
the user-supplied mode has no Terraform resource to destroy.

The OCI provider is pinned to `8.22.0`, matching the locked provider version
in the repository's existing Deep Data Security Terraform work. The uploaded
GenAI infrastructure sample informed Resource Manager conventions only; its
GenAI clusters, models, endpoints, and object upload provisioner are not used.
