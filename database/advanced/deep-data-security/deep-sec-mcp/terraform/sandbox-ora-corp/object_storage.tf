resource "oci_objectstorage_bucket" "participant" {
  for_each = local.effective_participants

  compartment_id = oci_identity_compartment.participant[each.key].id
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = "${var.name_prefix}-${each.key}-mcp"
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"

  defined_tags  = var.defined_tags
  freeform_tags = local.participant_freeform_tags[each.key]
}
