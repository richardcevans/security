# Values below are injected by the LiveLabs platform. Do not replace them
# with tenancy-specific values in this package.
variable "ociTenancyOcid" {
  type    = string
  default = ""
}

variable "ociUserOcid" {
  type    = string
  default = ""
}

variable "ociUserPassword" {
  type      = string
  default   = ""
  sensitive = true
}

variable "ociCompartmentOcid" {
  type    = string
  default = ""
}

variable "ociRegionIdentifier" {
  type    = string
  default = ""
}

variable "resId" {
  type    = string
  default = ""
}

# LiveLabs supplies these networking values for workshops that create Compute.
variable "ociPublicSubnetOcid" {
  type    = string
  default = ""
}

variable "ociPrivateSubnetOcid" {
  type    = string
  default = ""
}

variable "ociVcnOcid" {
  type    = string
  default = ""
}

variable "resUserPublicKey" {
  type    = string
  default = ""
}

# LiveLabs supplies this value for workshops that call OCI Generative AI.
variable "ociGenAiRegion" {
  type    = string
  default = ""
}

variable "liveStackURL" {
  type    = string
  default = ""
}

variable "application_bundle_par_url" {
  type        = string
  description = "Exact-object HTTPS read PAR for the canonical shared Deep Sec application ZIP. Re-upload the same Object Storage object when application code changes; keep this URL stable."
  sensitive   = true

  validation {
    condition     = can(regex("^https://objectstorage[.][A-Za-z0-9-]+[.]oraclecloud[.]com/.+", trimspace(var.application_bundle_par_url)))
    error_message = "Provide the HTTPS Object Storage PAR URL for deep-data-security-flask-app.zip."
  }

}

variable "mp_listing_id" {
  type        = string
  description = "Marketplace App Catalog listing OCID for the Deep Data Security image."
  default     = "ocid1.appcataloglisting.oc1..aaaaaaaaczjoa6swtlfcx3hmvw2wj4xpebjnrsh5w3eh46ytvxi4nyeiy32q"
}

variable "mp_listing_resource_version" {
  type        = string
  description = "Marketplace listing resource version for the Deep Data Security image."
  default     = "1.0"
}

variable "instance_image_id" {
  type        = string
  description = "Published Marketplace image OCID for the Deep Data Security application server."
  default     = "ocid1.image.oc1..aaaaaaaavbeftztulje3ichsodstyzotjh52ligh2gygucukva7fpj5qkj3q"
}

variable "instance_shape" {
  type        = string
  description = "Compute shape compatible with the Deep Data Security Marketplace image."
  default     = "VM.Standard.E5.Flex"
}

variable "instance_ocpus" {
  type        = number
  description = "OCPU count for the Flex compute shape."
  default     = 1
}

variable "instance_memory_in_gbs" {
  type        = number
  description = "Memory in GB for the Flex compute shape."
  default     = 16
}

variable "order_history_bucket_prefix" {
  type        = string
  description = "Object Storage prefix for the pre-created Order History table."
  default     = "order_history_iceberg"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._/-]*[A-Za-z0-9]$", trimspace(var.order_history_bucket_prefix)))
    error_message = "order_history_bucket_prefix must contain letters, numbers, dots, underscores, hyphens, and slashes, and must not start or end with a slash."
  }
}

variable "wallet_par_ttl_hours" {
  type        = number
  description = "Hours that bootstrap pre-authenticated requests remain valid."
  default     = 96

  validation {
    condition     = var.wallet_par_ttl_hours >= 1 && var.wallet_par_ttl_hours <= 17520
    error_message = "wallet_par_ttl_hours must be between 1 and 17520."
  }
}

variable "genai_model_id" {
  type        = string
  description = "On-demand OCI Generative AI chat model available in ociGenAiRegion."
  default     = "google.gemini-2.5-flash"
}
