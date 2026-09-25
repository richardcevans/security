data "oci_identity_availability_domains" "available" {
  compartment_id = var.ociCompartmentOcid
}

resource "oci_core_instance" "flask" {
  # Keep the bucket cleanup resource alive while this VM can still write its
  # generated Iceberg files. Terraform destroys the VM before the cleanup.
  depends_on = [
    terraform_data.wallet_bucket_cleanup,
    # The Stack-created bucket, archive, and object PARs must be ready before
    # cloud-init materializes the table graph.
    oci_objectstorage_preauthrequest.order_history_bundle_archive_read,
    oci_objectstorage_preauthrequest.order_history_bundle_object_write,
    # A Marketplace image cannot be launched until this tenancy has accepted
    # the listing terms and the resulting subscription has propagated.
    oci_core_app_catalog_subscription.deep_sec_marketplace_image,
  ]

  availability_domain = data.oci_identity_availability_domains.available.availability_domains[0].name
  compartment_id      = var.ociCompartmentOcid
  display_name        = "workshop-${var.resId}"
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_in_gbs
  }

  create_vnic_details {
    subnet_id        = var.ociPublicSubnetOcid
    assign_public_ip = true
    display_name     = "workshop-${var.resId}"
  }

  source_details {
    source_type = "image"
    source_id   = var.instance_image_id
  }

  metadata = {
    ssh_authorized_keys = var.resUserPublicKey
    # OCI instance metadata is limited to 32 KB. Cloud-init recognizes the
    # decompressed YAML by its gzip header after OCI decodes this value.
    user_data = base64gzip(templatefile("${path.module}/templates/genai-defaults-cloud-init.yaml.tftpl", {
      genai_compartment_ocid    = var.ociCompartmentOcid
      genai_model_id            = var.genai_model_id
      genai_region              = local.genai_region
      jupyter_password          = random_string.lab_admin_password.result
      region                    = var.ociRegionIdentifier
      adb_db_name               = local.adb_db_name
      adb_tls_connection_string = local.adb_tls_connection_string
      # The wallet installer remains in the shared cloud-init template but is
      # deliberately not called by GreenButton.
      adb_service_alias                   = ""
      adb_actual_service_alias            = ""
      wallet_par_url                      = ""
      application_par_url                 = var.application_bundle_par_url
      bootstrap_status_write_par_url      = "https://objectstorage.${var.ociRegionIdentifier}.oraclecloud.com${oci_objectstorage_preauthrequest.bootstrap_status_write.access_uri}"
      order_history_read_par_url          = local.order_history_effective_read_par_url
      order_history_metadata_read_par_url = local.order_history_effective_metadata_read_par_url
      order_history_bucket                = local.order_history_effective_bucket
      order_history_namespace             = local.order_history_effective_namespace
      order_history_prefix                = local.order_history_effective_prefix
      # The bundled delivery path uses object-specific PARs, not Customer
      # Secret Keys. Keep these template inputs empty for its legacy helpers.
      order_history_access_key = ""
      order_history_secret_key = ""
      # DBMS_CLOUD requires an OCI username and auth token. Both are created
      # from the standard LiveLabs user identity and base64-encoded so cloud-
      # init can safely write token characters to its environment file.
      order_history_oci_username_b64      = base64encode(data.oci_identity_user.livelabs_user.name)
      order_history_oci_auth_token_b64    = base64encode(oci_identity_auth_token.order_history.token)
      order_history_metadata_url          = local.order_history_effective_metadata_url
      order_history_bundle_archive_url    = local.order_history_bundle_archive_url
      order_history_bundle_write_par_urls = jsonencode(local.order_history_bundle_write_par_urls)
      # systemd EnvironmentFile syntax needs the JSON's inner quotes escaped;
      # single-quoting the whole JSON leaves literal quotes in os.environ.
      order_history_object_read_par_urls  = replace(jsonencode(local.order_history_bundle_read_par_urls), "\"", "\\\"")
      order_history_bundle_archive_sha256 = local.order_history_bundle_archive_sha256
      order_history_export_prefix         = local.order_history_target_prefix
    }))
  }

  freeform_tags = local.common_tags

  # user_data is only processed on the first boot. Recreate the VM when the
  # bootstrap status generation changes so a failed deployment can recover.
  lifecycle {
    replace_triggered_by = [random_id.bootstrap_status_suffix]
  }
}
