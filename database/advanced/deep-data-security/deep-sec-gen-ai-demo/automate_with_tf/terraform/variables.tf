variable "tenancy_ocid" {
  type        = string
  description = "OCI tenancy OCID used by the OCI provider."
  nullable    = true
  default     = null
}

variable "compartment_ocid" {
  type        = string
  description = "Compartment OCID for a Terraform-managed ADB-S."
  nullable    = true
  default     = null
}

variable "region" {
  type        = string
  description = "OCI region used by the OCI provider."
  nullable    = true
  default     = null
}

variable "name_prefix" {
  type        = string
  description = "Prefix used only for Terraform-managed lab resource tags."
  default     = "deep-sec-gen-ai-demo"
}

variable "create_autonomous_database" {
  type        = bool
  description = "Create and let Terraform own a new Autonomous Database Serverless instance."
  default     = false
}

variable "autonomous_database_id" {
  type        = string
  description = "OCID of a user-supplied ADB-S. Terraform never manages or destroys this database."
  nullable    = true
  default     = null
}

variable "autonomous_database_name" {
  type        = string
  description = "Database name when Terraform creates the ADB-S."
  nullable    = true
  default     = null
}

variable "autonomous_database_display_name" {
  type        = string
  description = "Display name when Terraform creates the ADB-S."
  nullable    = true
  default     = null
}

variable "adb_admin_password" {
  type        = string
  description = "ADMIN password for a Terraform-managed ADB-S. Set TF_VAR_adb_admin_password; do not commit it."
  nullable    = true
  default     = null
  sensitive   = true
}

variable "database_version" {
  type        = string
  description = "Database version requested for a Terraform-managed ADB-S."
  default     = "26ai"
}

variable "adb_workload" {
  type        = string
  description = "OCI Autonomous Database workload API value."
  default     = "OLTP"

  validation {
    condition     = contains(["OLTP", "DW", "AJD", "APEX"], var.adb_workload)
    error_message = "adb_workload must be OLTP, DW, AJD, or APEX."
  }
}

variable "is_free_tier" {
  type        = bool
  description = "Request an Always Free ADB-S where the selected region supports it."
  default     = true
}

variable "license_model" {
  type        = string
  description = "License model for a paid Terraform-managed ADB-S. Ignored for Always Free."
  default     = "BRING_YOUR_OWN_LICENSE"

  validation {
    condition     = contains(["BRING_YOUR_OWN_LICENSE", "LICENSE_INCLUDED"], var.license_model)
    error_message = "license_model must be BRING_YOUR_OWN_LICENSE or LICENSE_INCLUDED."
  }
}

variable "is_mtls_connection_required" {
  type        = bool
  description = "Require mutual TLS for a Terraform-managed ADB-S."
  default     = true
}

variable "compute_model" {
  type        = string
  description = "Compute model for a paid Terraform-managed ADB-S."
  default     = "ECPU"
}

variable "compute_count" {
  type        = number
  description = "Compute count for a paid Terraform-managed ADB-S."
  default     = 1
}

variable "data_storage_size_in_tbs" {
  type        = number
  description = "Data storage size for a paid Terraform-managed ADB-S."
  default     = 1
}

variable "create_demo_bucket" {
  type        = bool
  description = "Create the private Object Storage bucket used for synthetic bonus data."
  default     = true
}

variable "demo_bucket_name" {
  type        = string
  description = "Name of the private demo bucket when create_demo_bucket is true."
  nullable    = true
  default     = null
}
