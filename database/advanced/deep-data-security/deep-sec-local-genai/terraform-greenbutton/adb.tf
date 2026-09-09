resource "oci_database_autonomous_database" "lab" {
  compartment_id = var.compartment_ocid
  db_name        = local.adb_db_name
  display_name   = "${var.adb_display_name}-${local.stack_suffix}"
  db_version     = "26ai"
  db_workload    = "OLTP"
  admin_password = random_password.lab_admin.result

  compute_model            = "ECPU"
  compute_count            = var.adb_compute_count
  data_storage_size_in_tbs = var.adb_storage_tbs
  license_model            = var.adb_license_model
  is_auto_scaling_enabled  = true
  # GreenButton uses TLS without an ADB wallet. TODO: replace this temporary
  # open ACL with the application server private IP/CIDR before broad use.
  is_mtls_connection_required = false
  whitelisted_ips             = ["0.0.0.0/0"]

  freeform_tags = local.common_tags

}

resource "random_id" "adb_name_suffix" {
  byte_length = 4
}
