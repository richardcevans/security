# DBMS_CLOUD uses an OCI auth token to read the private Iceberg objects. Create
# a deployment-scoped token for the LiveLabs user and remove it with the Stack.
data "oci_identity_user" "livelabs_user" {
  user_id = var.ociUserOcid
}

resource "oci_identity_auth_token" "order_history" {
  user_id     = var.ociUserOcid
  description = "Deep Data Security ${var.resId} DBMS_CLOUD"
}
