terraform {
  # OCI Resource Manager (Cloud Stacks) accepts its supported CLI version,
  # rather than a Terraform version range.
  required_version = "1.5.7"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.0.0, < 9.0.0"
    }
  }
}
