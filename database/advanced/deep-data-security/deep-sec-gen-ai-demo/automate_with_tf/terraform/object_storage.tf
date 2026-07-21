data "oci_objectstorage_namespace" "current" {
  compartment_id = var.compartment_ocid
}

resource "oci_objectstorage_bucket" "demo" {
  count          = var.create_demo_bucket ? 1 : 0
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.current.namespace
  name           = coalesce(var.demo_bucket_name, "${var.name_prefix}-bonus-data")
  access_type    = "NoPublicAccess"

  freeform_tags = local.common_tags
}
