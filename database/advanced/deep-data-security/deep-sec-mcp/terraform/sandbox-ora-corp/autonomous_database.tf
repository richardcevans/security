resource "oci_database_autonomous_database" "participant" {
  for_each = local.effective_participants

  compartment_id = oci_identity_compartment.participant[each.key].id
  db_name        = each.value.db_name
  display_name   = coalesce(each.value.display_name, "${var.name_prefix}-${each.key}-adb")
  db_workload    = var.adb_workload

  admin_password = var.adb_admin_password

  is_free_tier                = var.adb_is_free_tier
  is_mtls_connection_required = var.adb_is_mtls_connection_required
  license_model               = var.adb_is_free_tier ? null : "LICENSE_INCLUDED"
  compute_model               = var.adb_is_free_tier ? null : var.adb_compute_model
  compute_count               = var.adb_is_free_tier ? null : var.adb_compute_count
  data_storage_size_in_tbs    = var.adb_is_free_tier ? null : var.adb_data_storage_size_in_tbs
  is_auto_scaling_enabled     = var.adb_is_free_tier ? null : false

  defined_tags  = var.defined_tags
  freeform_tags = local.participant_freeform_tags[each.key]

  lifecycle {
    ignore_changes = [
      admin_password
    ]
  }
}
