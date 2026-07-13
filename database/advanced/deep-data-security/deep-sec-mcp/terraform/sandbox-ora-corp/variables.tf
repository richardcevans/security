variable "tenancy_ocid" {
  description = "OCI tenancy OCID."
  type        = string
}

variable "region" {
  description = "OCI region identifier, for example us-ashburn-1."
  type        = string
}

variable "parent_compartment_ocid" {
  description = "Parent compartment where participant compartments and policies are created."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for all workshop resources."
  type        = string
  default     = "deepsec-mcp-ora-corp"
}

variable "reservation_id" {
  description = "LiveLabs reservation or event identifier used for tags and teardown."
  type        = string
  default     = "tbd"
}

variable "ttl" {
  description = "Teardown target date or marker."
  type        = string
  default     = "tbd"
}

variable "participant_group_name_prefix" {
  description = "Prefix for pre-created participant groups. Effective group name is <prefix>-<participant_key>."
  type        = string
  default     = "ll-deepsec-mcp"
}

variable "participant_count" {
  description = "Number of generated participants to create when participants is empty."
  type        = number
  default     = 1

  validation {
    condition     = var.participant_count >= 1 && var.participant_count <= 500
    error_message = "participant_count must be between 1 and 500."
  }
}

variable "participant_prefix" {
  description = "Prefix for generated participant keys, for example U creates U12345."
  type        = string
  default     = "U"
}

variable "participant_start_number" {
  description = "Starting number for generated participant keys."
  type        = number
  default     = 12345
}

variable "participants" {
  description = "Optional explicit participant map. Leave empty to generate participants from participant_count, participant_prefix, and participant_start_number."
  type = map(object({
    db_name      = string
    display_name = optional(string)
  }))
  default = {}
}

variable "adb_admin_password" {
  description = "Admin password for participant Autonomous Databases. Prefer a generated secret per participant in production."
  type        = string
  sensitive   = true
}

variable "adb_workload" {
  description = "Autonomous Database workload API value. OLTP corresponds to Autonomous Transaction Processing."
  type        = string
  default     = "OLTP"

  validation {
    condition     = contains(["OLTP", "DW", "AJD", "APEX"], var.adb_workload)
    error_message = "adb_workload must be OLTP, DW, AJD, or APEX."
  }
}

variable "adb_is_free_tier" {
  description = "Whether to create Always Free Autonomous Database instances."
  type        = bool
  default     = false
}

variable "adb_is_mtls_connection_required" {
  description = "Require mutual TLS for Autonomous Database connections. Set false to allow TLS connections used by Database Tools."
  type        = bool
  default     = false
}

variable "adb_compute_model" {
  description = "Autonomous Database compute model."
  type        = string
  default     = "ECPU"

  validation {
    condition     = contains(["ECPU", "OCPU"], var.adb_compute_model)
    error_message = "adb_compute_model must be ECPU or OCPU."
  }
}

variable "adb_compute_count" {
  description = "Autonomous Database compute count."
  type        = number
  default     = 1
}

variable "adb_data_storage_size_in_tbs" {
  description = "Autonomous Database storage in TB."
  type        = number
  default     = 1
}

variable "database_tools_resource_family" {
  description = "OCI policy resource family for Database Tools. Validate exact name with LiveLabs/OCI."
  type        = string
  default     = "database-tools-family"
}

variable "create_database_tools_vault_secret" {
  description = "Create one OCI Vault, key, and password secret for Database Tools connections. Uses database_tools_connection_password or adb_admin_password as the secret value."
  type        = bool
  default     = false
}

variable "database_tools_vault_type" {
  description = "OCI Vault type for the optional Database Tools password secret."
  type        = string
  default     = "DEFAULT"

  validation {
    condition     = contains(["DEFAULT", "VIRTUAL_PRIVATE"], var.database_tools_vault_type)
    error_message = "database_tools_vault_type must be DEFAULT or VIRTUAL_PRIVATE."
  }
}

variable "database_tools_existing_password_secret_id" {
  description = "Existing Vault secret OCID containing the Database Tools connection password. Used when create_database_tools_vault_secret is false."
  type        = string
  default     = null
}

variable "create_database_tools_connections" {
  description = "Create Database Tools connections for each participant from the provisioned Autonomous Databases."
  type        = bool
  default     = false
}

variable "database_tools_connection_type" {
  description = "Database Tools connection type."
  type        = string
  default     = "ORACLE_DATABASE"

  validation {
    condition     = contains(["ORACLE_DATABASE"], var.database_tools_connection_type)
    error_message = "database_tools_connection_type must be ORACLE_DATABASE."
  }
}

variable "database_tools_connection_user_name" {
  description = "Database user name for Database Tools connections. ADMIN is acceptable for smoke tests; use a least-privilege user for production workshops."
  type        = string
  default     = "ADMIN"
}

variable "database_tools_connection_password" {
  description = "Optional password for Database Tools connection secret creation. When null, adb_admin_password is reused."
  type        = string
  sensitive   = true
  default     = null
}

variable "enable_tenancy_policies" {
  description = "Create tenancy-scope participant policies. Leave false unless the Resource Manager principal can manage policies in the tenancy root compartment."
  type        = bool
  default     = false
}

variable "enable_database_tools_policy" {
  description = "Add Database Tools policy statements after the exact Database Tools policy resource family is confirmed for the tenancy."
  type        = bool
  default     = false
}

variable "enable_participant_compartment_policies" {
  description = "Create participant group policies. Leave false for corporate tenancies where you use existing user permissions and cannot create workshop users or groups."
  type        = bool
  default     = false
}

variable "identity_domain_ocid" {
  description = "Identity domain OCID used by Database Tools MCP Servers. Required when create_mcp_servers is true."
  type        = string
  default     = null
}

variable "create_mcp_servers" {
  description = "Create Database Tools MCP Servers from supplied Database Tools connection OCIDs."
  type        = bool
  default     = false
}

variable "database_tools_connection_ids" {
  description = "Map of participant key to pre-created Database Tools connection OCID."
  type        = map(string)
  default     = {}
}

variable "mcp_server_type" {
  description = "Database Tools MCP Server type. Validate with OCI provider/API if this default changes."
  type        = string
  default     = "DEFAULT"

  validation {
    condition     = contains(["DEFAULT"], var.mcp_server_type)
    error_message = "mcp_server_type must be DEFAULT unless OCI provider/API support is confirmed for another value."
  }
}

variable "mcp_server_storage_type" {
  description = "Database Tools MCP Server storage type."
  type        = string
  default     = "OBJECT_STORAGE"

  validation {
    condition     = contains(["OBJECT_STORAGE"], var.mcp_server_storage_type)
    error_message = "mcp_server_storage_type must be OBJECT_STORAGE."
  }
}

variable "mcp_server_runtime_identity" {
  description = "Optional MCP Server runtime identity, for example RESOURCE_PRINCIPAL. Leave null to use service default."
  type        = string
  default     = null
}

variable "mcp_access_token_expiry_in_seconds" {
  description = "Optional MCP access token expiration."
  type        = number
  default     = null
}

variable "mcp_refresh_token_expiry_in_seconds" {
  description = "Optional MCP refresh token expiration."
  type        = number
  default     = null
}

variable "enable_generative_ai_policy" {
  description = "Set true if the simple AI app uses OCI Generative AI."
  type        = bool
  default     = false
}

variable "defined_tags" {
  description = "Optional defined tags."
  type        = map(string)
  default     = {}
}

variable "freeform_tags" {
  description = "Optional freeform tags applied to resources."
  type        = map(string)
  default     = {}
}
