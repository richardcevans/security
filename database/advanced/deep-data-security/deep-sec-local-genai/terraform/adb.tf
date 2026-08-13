resource "oci_database_autonomous_database" "lab" {
  compartment_id = var.compartment_ocid
  db_name        = var.adb_db_name
  display_name   = var.adb_display_name
  db_version     = "26ai"
  db_workload    = "OLTP"
  admin_password = var.adb_admin_password

  compute_model               = "ECPU"
  compute_count               = var.adb_compute_count
  data_storage_size_in_tbs    = var.adb_storage_tbs
  license_model               = var.adb_license_model
  is_auto_scaling_enabled     = true
  is_mtls_connection_required = true

  freeform_tags = local.common_tags

  lifecycle {
    ignore_changes = [admin_password]
  }
}
