locals {
  generated_participants = {
    for i in range(var.participant_count) :
    format("%s%05d", var.participant_prefix, var.participant_start_number + i) => {
      display_name = format("%s-%s%05d", var.name_prefix, var.participant_prefix, var.participant_start_number + i)
    }
  }

  effective_participants = length(var.participants) > 0 ? var.participants : local.generated_participants

  database_tools_password_secret_id = var.create_database_tools_vault_secret ? oci_vault_secret.database_tools_password[0].id : var.database_tools_existing_password_secret_id

  database_tools_related_resource_id = coalesce(var.database_tools_related_resource_ocid, var.base_database_ocid, var.base_db_system_ocid)

  generated_database_tools_connection_ids = {
    for key, connection in oci_database_tools_database_tools_connection.participant :
    key => connection.id
  }

  effective_database_tools_connection_ids = length(local.generated_database_tools_connection_ids) > 0 ? local.generated_database_tools_connection_ids : var.database_tools_connection_ids

  participant_group_names = {
    for key, value in local.effective_participants :
    key => "${var.participant_group_name_prefix}-${key}"
  }

  common_freeform_tags = merge(
    var.freeform_tags,
    {
      workshop    = "deepsec-mcp"
      reservation = var.reservation_id
      ttl         = var.ttl
    }
  )

  participant_freeform_tags = {
    for key, value in local.effective_participants :
    key => merge(local.common_freeform_tags, {
      participant = key
    })
  }
}
