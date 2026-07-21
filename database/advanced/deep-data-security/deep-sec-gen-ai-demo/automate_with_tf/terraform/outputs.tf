output "autonomous_database_id" {
  description = "OCID of the Terraform-managed or user-supplied ADB-S."
  value       = var.create_autonomous_database ? oci_database_autonomous_database.lab[0].id : var.autonomous_database_id
}

output "autonomous_database_ownership" {
  description = "Whether Terraform manages lifecycle of the ADB-S."
  value       = var.create_autonomous_database ? "terraform-managed" : "user-supplied"
}

output "autonomous_database_name" {
  description = "Name of the Terraform-managed ADB-S; null for a user-supplied database."
  value       = var.create_autonomous_database ? oci_database_autonomous_database.lab[0].db_name : var.autonomous_database_name
}

output "demo_bucket_name" {
  value       = var.create_demo_bucket ? oci_objectstorage_bucket.demo[0].name : null
  description = "Private bucket for synthetic bonus data."
}

output "object_storage_namespace" {
  value       = var.create_demo_bucket ? data.oci_objectstorage_namespace.current.namespace : null
  description = "Object Storage namespace for the private demo bucket."
}
