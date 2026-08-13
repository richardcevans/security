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
    display_name     = "${var.compute_display_name}-vnic"
  }

  source_details {
    source_type = "image"
    source_id   = var.compute_image_ocid
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/templates/genai-defaults-cloud-init.yaml.tftpl", {
      genai_compartment_ocid = local.genai_compartment_ocid
      genai_model_id         = var.genai_model_id
      region                 = var.region
    }))
  }

  freeform_tags = local.common_tags
}
