data "oci_objectstorage_namespace" "current" {
  compartment_id = var.compartment_ocid
}

resource "oci_objectstorage_bucket" "wallet" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.current.namespace
  name           = var.wallet_bucket_name
  access_type    = "NoPublicAccess"

  freeform_tags = local.common_tags
}

# OCI returns wallet bytes as base64. local_file preserves the ZIP exactly;
# content_base64 is deliberately used instead of treating the wallet as text.
resource "local_file" "lab_wallet_zip" {
  filename             = "${path.module}/.deep-sec-generated-wallet.zip"
  content_base64       = oci_database_autonomous_database_wallet.lab.content
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "oci_objectstorage_object" "lab_wallet" {
  bucket    = oci_objectstorage_bucket.wallet.name
  namespace = data.oci_objectstorage_namespace.current.namespace
  object    = var.wallet_object_name
  # `source` must remain unknown during plan. The OCI provider otherwise
  # stats this generated file before local_file has created it. local_file.id
  # becomes known only after the wallet has been written during apply.
  source       = local_file.lab_wallet_zip.id != "" ? local_file.lab_wallet_zip.filename : null
  content_type = "application/zip"

  lifecycle {
    replace_triggered_by = [local_file.lab_wallet_zip]
  }
}

# Anchor the URL lifetime at the Stack's first successful apply. The PAR is
# ObjectRead-only and is not emitted as a Stack output.
resource "time_static" "wallet_par_expiration_anchor" {}

resource "oci_objectstorage_preauthrequest" "lab_wallet_read" {
  bucket       = oci_objectstorage_bucket.wallet.name
  namespace    = data.oci_objectstorage_namespace.current.namespace
  name         = "deep-sec-wallet-bootstrap-read"
  access_type  = "ObjectRead"
  object_name  = oci_objectstorage_object.lab_wallet.object
  time_expires = timeadd(time_static.wallet_par_expiration_anchor.rfc3339, "${var.wallet_par_ttl_hours}h")
}
