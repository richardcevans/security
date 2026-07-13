resource "oci_identity_policy" "participant_tenancy" {
  for_each = var.enable_tenancy_policies ? local.effective_participants : {}

  compartment_id = var.tenancy_ocid
  name           = "${var.name_prefix}-${each.key}-tenancy-policy"
  description    = "Least-privilege tenancy-scope access for DeepSec MCP participant ${each.key}"

  statements = compact([
    "Allow group ${local.participant_group_names[each.key]} to use cloud-shell in tenancy"
  ])

  defined_tags  = var.defined_tags
  freeform_tags = local.participant_freeform_tags[each.key]
}

resource "oci_identity_policy" "participant_compartment" {
  for_each = local.effective_participants

  compartment_id = var.parent_compartment_ocid
  name           = "${var.name_prefix}-${each.key}-compartment-policy"
  description    = "Least-privilege compartment access for DeepSec MCP participant ${each.key}"

  statements = compact([
    "Allow group ${local.participant_group_names[each.key]} to read autonomous-database-family in compartment id ${oci_identity_compartment.participant[each.key].id}",
    "Allow group ${local.participant_group_names[each.key]} to use autonomous-database-family in compartment id ${oci_identity_compartment.participant[each.key].id}",
    "Allow group ${local.participant_group_names[each.key]} to read object-family in compartment id ${oci_identity_compartment.participant[each.key].id}",
    "Allow group ${local.participant_group_names[each.key]} to use object-family in compartment id ${oci_identity_compartment.participant[each.key].id}",
    "Allow group ${local.participant_group_names[each.key]} to manage objects in compartment id ${oci_identity_compartment.participant[each.key].id}",
    var.enable_database_tools_policy ? "Allow group ${local.participant_group_names[each.key]} to read ${var.database_tools_resource_family} in compartment id ${oci_identity_compartment.participant[each.key].id}" : "",
    var.enable_database_tools_policy ? "Allow group ${local.participant_group_names[each.key]} to use ${var.database_tools_resource_family} in compartment id ${oci_identity_compartment.participant[each.key].id}" : "",
    var.enable_generative_ai_policy ? "Allow group ${local.participant_group_names[each.key]} to use generative-ai-family in compartment id ${oci_identity_compartment.participant[each.key].id}" : ""
  ])

  defined_tags  = var.defined_tags
  freeform_tags = local.participant_freeform_tags[each.key]
}
