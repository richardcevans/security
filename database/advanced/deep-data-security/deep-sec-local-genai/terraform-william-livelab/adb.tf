resource "oci_database_autonomous_database" "lab" {
  compartment_id = var.ociCompartmentOcid
  db_name        = local.adb_db_name
  display_name   = "Deep-Sec-${var.resId}"
  db_version     = "23ai"
  db_workload    = "OLTP"
  admin_password = random_string.lab_admin_password.result

  compute_model            = "ECPU"
  compute_count            = 2
  data_storage_size_in_tbs = 1
  license_model            = "BRING_YOUR_OWN_LICENSE"
  is_auto_scaling_enabled  = true
  # GreenButton uses TLS without an ADB wallet. TODO: replace this temporary
  # open ACL with the application server private IP/CIDR before broad use.
  is_mtls_connection_required = false
  whitelisted_ips             = ["0.0.0.0/0"]

  freeform_tags = local.common_tags

}
