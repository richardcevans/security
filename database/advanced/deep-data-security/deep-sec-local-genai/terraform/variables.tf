variable "tenancy_ocid" {
  type        = string
  description = "OCI tenancy OCID. Required for provider authentication and optional IAM resources."
}

variable "compartment_ocid" {
  type        = string
  description = "Compartment that receives ADB, compute, and the optional private wallet bucket."
}

variable "region" {
  type        = string
  description = "OCI region for all resources. The supplied custom image is in Ashburn."
  default     = "us-ashburn-1"
}

variable "oci_profile" {
  type        = string
  description = "OCI CLI profile used by the Terraform provider. terraform.sh sets this from OCI_PROFILE or OCI_CLI_PROFILE."
  default     = ""
}

variable "adb_db_name" {
  type        = string
  description = "Autonomous Database name; use uppercase letters, digits, $, or #."
  default     = "DEEPSEC9"
}

variable "adb_display_name" {
  type        = string
  description = "Autonomous Database display name."
  default     = "deepsec9"
}

variable "adb_admin_password" {
  type        = string
  description = "ADMIN password for the Terraform-managed ADB. Set TF_VAR_adb_admin_password; do not commit it."
  sensitive   = true
}

variable "adb_compute_count" {
  type        = number
  description = "ECPU count for Autonomous Database Serverless."
  default     = 2
}

variable "adb_storage_tbs" {
  type        = number
  description = "ADB storage in TB. OCI Terraform API uses TB rather than the Cloud Shell GB option."
  default     = 1
}

variable "adb_license_model" {
  type        = string
  description = "ADB license model."
  default     = "BRING_YOUR_OWN_LICENSE"
}

variable "compute_image_ocid" {
  type        = string
  description = "Custom-image OCID for the Flask compute instance. Override when using a different tenancy or region."
  default     = "ocid1.image.oc1.iad.aaaaaaaaniph7qkksa5gbo2orm44hhhqs4wd7fasrobaxofhzjazgm65rima"
}

variable "vcn_cidr" {
  type        = string
  description = "CIDR block for the disposable lab VCN."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR block for the public Flask application subnet. Must be inside vcn_cidr."
  default     = "10.0.1.0/24"
}

variable "vcn_dns_label" {
  type        = string
  description = "DNS label for the disposable lab VCN."
  default     = "deepsec9"
}

variable "allowed_ingress_home_ip_address" {
  type        = string
  description = "Your public home IPv4 address. Terraform adds /32 and permits this one address into the disposable lab VCN."

  validation {
    condition     = can(cidrhost("${var.allowed_ingress_home_ip_address}/32", 0))
    error_message = "Enter one valid IPv4 address, for example 203.0.113.10, without a CIDR suffix."
  }
}

variable "allowed_ingress_description" {
  type        = string
  description = "Description attached to the trusted ingress security rule."
  default     = "My Home IP"
}

variable "compute_shape" {
  type        = string
  description = "Compute shape compatible with the supplied custom image."
  default     = "VM.Standard.E5.Flex"
}

variable "compute_ocpus" {
  type        = number
  description = "OCPU count for a Flex compute shape."
  default     = 1
}

variable "compute_memory_in_gbs" {
  type        = number
  description = "Memory in GB for a Flex compute shape."
  default     = 16
}

variable "compute_display_name" {
  type        = string
  description = "Display name for the Flask compute instance."
  default     = "deep-sec-app-server"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key injected into the compute instance."
}

variable "assign_public_ip" {
  type        = bool
  description = "Assign a public IP to the compute instance. Set false when using a bastion or private access path."
  default     = true
}

variable "create_wallet_bucket" {
  type        = bool
  description = "Create a private Object Storage bucket for short-lived wallet PAR publishing."
  default     = true
}

variable "wallet_bucket_name" {
  type        = string
  description = "Private wallet bucket name."
  default     = "deepsec9-wallet"
}

variable "create_genai_iam" {
  type        = bool
  description = "Create the dynamic group and policy that lets the Vibe coding assistant on the compute instance invoke OCI Generative AI. Requires tenancy IAM permission."
  default     = true
}

variable "genai_policy_compartment_ocid" {
  type        = string
  description = "Compartment where the compute instance may use Generative AI. Defaults to compartment_ocid when blank."
  default     = ""
}

variable "genai_dynamic_group_name" {
  type        = string
  description = "Dynamic group name when create_genai_iam is true."
  default     = "DEEPSEC9_COMPUTE"
}

variable "genai_policy_name" {
  type        = string
  description = "IAM policy name when create_genai_iam is true."
  default     = "DEEPSEC9_COMPUTE_GENAI"
}

variable "genai_model_id" {
  type        = string
  description = "Default on-demand OCI Generative AI chat model written to the Vibe CLI setup defaults. Override only with a model available in the selected OCI region."
  default     = "google.gemini-2.5-flash"
}
