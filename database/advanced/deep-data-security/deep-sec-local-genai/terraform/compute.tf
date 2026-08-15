resource "oci_core_instance" "flask" {
  availability_domain = data.oci_identity_availability_domains.available.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = var.compute_display_name
  shape               = var.compute_shape

  shape_config {
    ocpus         = var.compute_ocpus
    memory_in_gbs = var.compute_memory_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public_app.id
    assign_public_ip = var.assign_public_ip
    display_name     = var.compute_display_name
  }

  source_details {
    source_type = "image"
    source_id   = var.compute_image_ocid
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    # OCI instance metadata is limited to 32 KB. Cloud-init recognizes the
    # decompressed YAML by its gzip header after OCI decodes this value.
    user_data = base64gzip(templatefile("${path.module}/templates/genai-defaults-cloud-init.yaml.tftpl", {
      genai_compartment_ocid = local.genai_compartment_ocid
      genai_model_id         = var.genai_model_id
      jupyter_password       = random_password.lab_admin.result
      region                 = var.region
      adb_service_alias      = "${lower(var.adb_db_name)}_low"
      wallet_par_url         = "https://objectstorage.${var.region}.oraclecloud.com${oci_objectstorage_preauthrequest.lab_wallet_read.access_uri}"
    }))
  }

  freeform_tags = local.common_tags
}
