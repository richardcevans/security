check "autonomous_database_ownership" {
  assert {
    condition = (
      var.create_autonomous_database &&
      var.autonomous_database_id == null &&
      var.compartment_ocid != null &&
      var.autonomous_database_name != null &&
      var.adb_admin_password != null
      ) || (
      !var.create_autonomous_database &&
      var.autonomous_database_id != null &&
      var.autonomous_database_name != null
    )
    error_message = "Set create_autonomous_database=true with compartment_ocid, autonomous_database_name, and adb_admin_password; or set it false with autonomous_database_id and autonomous_database_name."
  }
}

check "bucket_compartment" {
  assert {
    condition     = !var.create_demo_bucket || var.compartment_ocid != null
    error_message = "compartment_ocid is required when create_demo_bucket is true."
  }
}

resource "oci_database_autonomous_database" "lab" {
  count = var.create_autonomous_database ? 1 : 0

  compartment_id = var.compartment_ocid
  db_name        = var.autonomous_database_name
  display_name   = coalesce(var.autonomous_database_display_name, var.autonomous_database_name)
  db_version     = var.database_version
  db_workload    = var.adb_workload
  admin_password = var.adb_admin_password

  is_free_tier                = var.is_free_tier
  is_mtls_connection_required = var.is_mtls_connection_required
  license_model               = var.is_free_tier ? null : var.license_model
  compute_model               = var.is_free_tier ? null : var.compute_model
  compute_count               = var.is_free_tier ? null : var.compute_count
  data_storage_size_in_tbs    = var.is_free_tier ? null : var.data_storage_size_in_tbs
  is_auto_scaling_enabled     = var.is_free_tier ? null : false

  freeform_tags = local.common_tags

  lifecycle {
    ignore_changes = [admin_password]
  }
}
