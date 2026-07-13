resource "oci_kms_vault" "database_tools" {
  count = var.create_database_tools_vault_secret ? 1 : 0

  compartment_id = var.parent_compartment_ocid
  display_name   = "${var.name_prefix}-dbtools-vault"
  vault_type     = var.database_tools_vault_type

  defined_tags  = var.defined_tags
  freeform_tags = local.common_freeform_tags
}

resource "oci_kms_key" "database_tools" {
  count = var.create_database_tools_vault_secret ? 1 : 0

  compartment_id      = var.parent_compartment_ocid
  display_name        = "${var.name_prefix}-dbtools-key"
  management_endpoint = oci_kms_vault.database_tools[0].management_endpoint

  key_shape {
    algorithm = "AES"
    length    = 32
  }

  defined_tags  = var.defined_tags
  freeform_tags = local.common_freeform_tags
}

resource "oci_vault_secret" "database_tools_password" {
  count = var.create_database_tools_vault_secret ? 1 : 0

  compartment_id = var.parent_compartment_ocid
  secret_name    = "${var.name_prefix}-dbtools-password"
  vault_id       = oci_kms_vault.database_tools[0].id
  key_id         = oci_kms_key.database_tools[0].id
  description    = "Password used by DeepSec MCP Database Tools connections."

  secret_content {
    content_type = "BASE64"
    content      = base64encode(var.database_tools_connection_password)
    name         = "current"
    stage        = "CURRENT"
  }

  defined_tags  = var.defined_tags
  freeform_tags = local.common_freeform_tags
}
