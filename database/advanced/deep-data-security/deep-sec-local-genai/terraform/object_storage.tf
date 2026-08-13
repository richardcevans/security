data "oci_objectstorage_namespace" "current" {
  compartment_id = var.compartment_ocid
}

resource "oci_objectstorage_bucket" "wallet" {
  count          = var.create_wallet_bucket ? 1 : 0
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.current.namespace
  name           = var.wallet_bucket_name
  access_type    = "NoPublicAccess"

  freeform_tags = local.common_tags
}
