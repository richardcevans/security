resource "oci_database_tools_database_tools_mcp_server" "participant" {
  for_each = var.create_mcp_servers ? local.effective_database_tools_connection_ids : {}

  compartment_id               = oci_identity_compartment.participant[each.key].id
  database_tools_connection_id = each.value
  display_name                 = "${var.name_prefix}-${each.key}-mcp"
  domain_id                    = var.identity_domain_ocid
  type                         = var.mcp_server_type

  access_token_expiry_in_seconds  = var.mcp_access_token_expiry_in_seconds
  refresh_token_expiry_in_seconds = var.mcp_refresh_token_expiry_in_seconds
  runtime_identity                = var.mcp_server_runtime_identity

  storage {
    type = var.mcp_server_storage_type

    bucket {
      namespace = data.oci_objectstorage_namespace.this.namespace
      bucket    = oci_objectstorage_bucket.participant[each.key].name
    }
  }

  defined_tags  = var.defined_tags
  freeform_tags = local.participant_freeform_tags[each.key]
}
