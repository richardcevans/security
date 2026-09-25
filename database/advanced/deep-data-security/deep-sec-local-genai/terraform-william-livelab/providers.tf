provider "oci" {
  # All infrastructure and Object Storage calls use the workshop's regular
  # deployment region.
  region = var.ociRegionIdentifier
}
