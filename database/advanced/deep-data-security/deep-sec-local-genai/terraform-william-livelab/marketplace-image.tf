# Accept the Marketplace terms and create the subscription before Compute uses
# the published image. The listing, version, and image are declared as the
# standard LiveLabs Marketplace variables in variables.tf.
resource "oci_core_app_catalog_listing_resource_version_agreement" "deep_sec_marketplace_image" {
  listing_id               = var.mp_listing_id
  listing_resource_version = var.mp_listing_resource_version
}

resource "oci_core_app_catalog_subscription" "deep_sec_marketplace_image" {
  compartment_id           = var.ociCompartmentOcid
  eula_link                = oci_core_app_catalog_listing_resource_version_agreement.deep_sec_marketplace_image.eula_link
  listing_id               = oci_core_app_catalog_listing_resource_version_agreement.deep_sec_marketplace_image.listing_id
  listing_resource_version = oci_core_app_catalog_listing_resource_version_agreement.deep_sec_marketplace_image.listing_resource_version
  oracle_terms_of_use_link = oci_core_app_catalog_listing_resource_version_agreement.deep_sec_marketplace_image.oracle_terms_of_use_link
  signature                = oci_core_app_catalog_listing_resource_version_agreement.deep_sec_marketplace_image.signature
  time_retrieved           = oci_core_app_catalog_listing_resource_version_agreement.deep_sec_marketplace_image.time_retrieved

  # Marketplace subscriptions can take several minutes to become available
  # to Compute after the listing terms are accepted.
  timeouts {
    create = "20m"
  }
}
