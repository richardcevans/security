resource "oci_identity_compartment" "participant" {
  for_each = local.effective_participants

  compartment_id = var.parent_compartment_ocid
  name           = "${var.name_prefix}-${each.key}"
  description    = "LiveLabs DeepSec MCP sandbox compartment for participant ${each.key}"
  enable_delete  = true

  defined_tags  = var.defined_tags
  freeform_tags = local.participant_freeform_tags[each.key]
}
