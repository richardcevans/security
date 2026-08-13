locals {
  genai_compartment_ocid = var.genai_policy_compartment_ocid != "" ? var.genai_policy_compartment_ocid : var.compartment_ocid
}

resource "oci_identity_dynamic_group" "compute" {
  count          = var.create_genai_iam ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = var.genai_dynamic_group_name
  description    = "DeepSec9 Flask compute instance"
  matching_rule  = "ALL {instance.id = '${oci_core_instance.flask.id}'}"
}

resource "oci_identity_policy" "compute_genai" {
  count          = var.create_genai_iam ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = var.genai_policy_name
  description    = "Allow the DeepSec9 compute instance to invoke chat"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.compute[0].name} to use generative-ai-chat in compartment id ${local.genai_compartment_ocid}"
  ]
}
