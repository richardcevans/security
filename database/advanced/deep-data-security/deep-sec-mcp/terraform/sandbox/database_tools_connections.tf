resource "oci_database_tools_database_tools_connection" "participant" {
  for_each = var.create_database_tools_connections && local.database_tools_password_secret_id != null ? local.effective_participants : {}

  compartment_id    = oci_identity_compartment.participant[each.key].id
  display_name      = "${var.name_prefix}-${each.key}-dbtools-connection"
  type              = var.database_tools_connection_type
  connection_string = oci_database_autonomous_database.participant[each.key].connection_strings[0].high
  user_name         = var.database_tools_connection_user_name

  user_password {
    secret_id  = local.database_tools_password_secret_id
    value_type = "SECRETID"
  }

  related_resource {
    entity_type = "AUTONOMOUS_DATABASE"
    identifier  = oci_database_autonomous_database.participant[each.key].id
  }

  defined_tags  = var.defined_tags
  freeform_tags = local.participant_freeform_tags[each.key]
}
