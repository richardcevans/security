# Resource Manager supplies tenancy authentication; keep only the stack region.
provider "oci" {
  region = var.region
}
