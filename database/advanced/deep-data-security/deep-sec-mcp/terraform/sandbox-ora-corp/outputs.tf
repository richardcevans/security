output "participant_compartments" {
  description = "Participant compartment OCIDs."
  value = {
    for key, compartment in oci_identity_compartment.participant :
    key => compartment.id
  }
}

output "participant_buckets" {
  description = "Participant Object Storage bucket names."
  value = {
    for key, bucket in oci_objectstorage_bucket.participant :
    key => bucket.name
  }
}

output "participant_autonomous_databases" {
  description = "Participant Autonomous Database OCIDs."
  value = {
    for key, adb in oci_database_autonomous_database.participant :
    key => adb.id
  }
}

output "mcp_server_cli_inputs" {
  description = "Inputs needed by scripts/create-mcp-server.sh after Database Tools connections exist."
  value = {
    for key, value in local.effective_participants :
    key => {
      compartment_id = oci_identity_compartment.participant[key].id
      bucket_name    = oci_objectstorage_bucket.participant[key].name
      adb_id         = oci_database_autonomous_database.participant[key].id
    }
  }
}

output "participant_mcp_servers" {
  description = "Participant MCP Server OCIDs when create_mcp_servers is true."
  value = {
    for key, server in oci_database_tools_database_tools_mcp_server.participant :
    key => {
      id            = server.id
      display_name  = server.display_name
      endpoints     = server.endpoints
      domain_app_id = server.domain_app_id
    }
  }
}

output "participant_database_tools_connections" {
  description = "Participant Database Tools connection OCIDs when create_database_tools_connections is true."
  value = {
    for key, connection in oci_database_tools_database_tools_connection.participant :
    key => {
      id               = connection.id
      display_name     = connection.display_name
      runtime_endpoint = connection.runtime_endpoint
      state            = connection.state
    }
  }
}

output "database_tools_password_secret_id" {
  description = "Vault secret OCID used for Database Tools connection passwords when available."
  value       = local.database_tools_password_secret_id
  sensitive   = true
}
