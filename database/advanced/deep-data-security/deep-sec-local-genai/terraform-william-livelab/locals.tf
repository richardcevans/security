locals {
  stack_resource_prefix     = "deep-sec-${var.resId}"
  wallet_bucket_name        = "Bucket-${var.resId}-files"
  adb_db_name               = "ATP${var.resId}"
  genai_region              = trimspace(var.ociGenAiRegion) != "" ? var.ociGenAiRegion : var.ociRegionIdentifier
  adb_low_profile_index     = index(oci_database_autonomous_database.lab.connection_strings[0].profiles.*.consumer_group, "LOW")
  adb_tls_connection_string = oci_database_autonomous_database.lab.connection_strings[0].profiles[local.adb_low_profile_index].value
  # These are the object paths materialized from the checked-in Iceberg bundle.
  # Keep this explicit: only the ZIP is distributed with the LiveLabs package,
  # so fileset() cannot enumerate its contents during Terraform evaluation.
  order_history_bundle_upload_objects = {
    "${local.order_history_target_prefix}/default/order_history/data/00000-0-ccf6774e-15fa-4b3b-b7be-9724a1706ba0.parquet"                    = true
    "${local.order_history_target_prefix}/default/order_history/metadata/00000-bc1c3928-73a6-4f31-823a-6c1de5a23be7.metadata.json"            = true
    "${local.order_history_target_prefix}/default/order_history/metadata/00001-bf556b46-af5f-4cd7-b899-d161e3a63361.metadata.json"            = true
    "${local.order_history_target_prefix}/default/order_history/metadata/ccf6774e-15fa-4b3b-b7be-9724a1706ba0-m0.avro"                        = true
    "${local.order_history_target_prefix}/default/order_history/metadata/snap-720290762785620607-0-ccf6774e-15fa-4b3b-b7be-9724a1706ba0.avro" = true
  }
  order_history_bundle_file                     = "${path.module}/artifacts/order_history_iceberg_bundle.zip"
  order_history_bundle_object                   = "${local.order_history_target_prefix}/.delivery-bundle.zip"
  order_history_bundle_data_object              = "${local.order_history_target_prefix}/default/order_history/data/00000-0-ccf6774e-15fa-4b3b-b7be-9724a1706ba0.parquet"
  order_history_bundle_metadata_object          = "${local.order_history_target_prefix}/default/order_history/metadata/00001-bf556b46-af5f-4cd7-b899-d161e3a63361.metadata.json"
  order_history_target_prefix                   = trim(trimspace(var.order_history_bucket_prefix), "/")
  order_history_bundle_bucket_name              = "Bucket-${var.resId}-iceberg"
  order_history_target_bucket                   = local.order_history_bundle_bucket_name
  order_history_effective_bucket                = local.order_history_target_bucket
  order_history_effective_namespace             = data.oci_objectstorage_namespace.current.namespace
  order_history_effective_prefix                = "${local.order_history_target_prefix}/"
  order_history_effective_metadata_url          = "https://objectstorage.${var.ociRegionIdentifier}.oraclecloud.com/n/${data.oci_objectstorage_namespace.current.namespace}/b/${local.order_history_target_bucket}/o/${local.order_history_bundle_metadata_object}"
  order_history_effective_read_par_url          = "https://objectstorage.${var.ociRegionIdentifier}.oraclecloud.com${oci_objectstorage_preauthrequest.order_history_read.access_uri}"
  order_history_effective_metadata_read_par_url = "https://objectstorage.${var.ociRegionIdentifier}.oraclecloud.com${oci_objectstorage_preauthrequest.order_history_metadata_read.access_uri}"
  order_history_bundle_archive_url              = "https://objectstorage.${var.ociRegionIdentifier}.oraclecloud.com${oci_objectstorage_preauthrequest.order_history_bundle_archive_read[0].access_uri}"
  order_history_bundle_write_par_urls = {
    for object_name in keys(local.order_history_bundle_upload_objects) :
    object_name => "https://objectstorage.${var.ociRegionIdentifier}.oraclecloud.com${oci_objectstorage_preauthrequest.order_history_bundle_object_write[object_name].access_uri}"
  }
  order_history_bundle_read_par_urls = {
    for object_name in keys(local.order_history_bundle_upload_objects) :
    object_name => "https://objectstorage.${var.ociRegionIdentifier}.oraclecloud.com${oci_objectstorage_preauthrequest.order_history_bundle_object_read[object_name].access_uri}"
  }
  order_history_bundle_archive_sha256 = filesha256(local.order_history_bundle_file)

  common_tags = {
    lab        = "deep-sec"
    managed_by = "terraform"
    deployment = var.resId
  }
}
