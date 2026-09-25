output "adb_admin_password" {
  value       = [random_string.lab_admin_password.result]
  description = "Password for the ADB ADMIN user, JupyterLab, and Marvin."
  sensitive   = true
}

output "adb_name" {
  value       = [oci_database_autonomous_database.lab.db_name]
  description = "Autonomous Database name."
}

output "adb_connection_low" {
  value       = [local.adb_tls_connection_string]
  description = "ADB LOW TLS connection descriptor."
}

output "adb_console_url" {
  value       = ["https://cloud.oracle.com/db/adbs/${oci_database_autonomous_database.lab.id}?region=${var.ociRegionIdentifier}&cloudshell=true&bdcstate=minimized"]
  description = "Autonomous Database Console URL."
}

output "instance_public_ip" {
  value       = [oci_core_instance.flask.public_ip]
  description = "Application-server public IP address."
}

output "instance_private_ip" {
  value       = [oci_core_instance.flask.private_ip]
  description = "Application-server private IP address."
}

output "flask_url" {
  value       = ["http://${oci_core_instance.flask.public_ip}:7777/"]
  description = "Customer Sales application URL."
}

output "admin_console_url" {
  value       = ["http://${oci_core_instance.flask.public_ip}:7778/"]
  description = "Deep Sec Administrator Console URL."
}

output "jupyter_url" {
  value       = ["http://${oci_core_instance.flask.public_ip}:8888/"]
  description = "JupyterLab URL."
}

output "ssh_command" {
  value       = ["ssh opc@${oci_core_instance.flask.public_ip}"]
  description = "SSH command template for the application server."
}

output "wallet_bucket_name" {
  value       = [oci_objectstorage_bucket.wallet.name]
  description = "Private application-artifact bucket."
}

output "order_history_bucket_name" {
  value       = [local.order_history_target_bucket]
  description = "Dedicated bucket containing the Order History Iceberg data."
}

output "order_history_bucket_namespace" {
  value       = [data.oci_objectstorage_namespace.current.namespace]
  description = "Object Storage namespace for the Order History bucket."
}

output "genai_configuration" {
  value = [{
    region           = local.genai_region
    compartment_ocid = var.ociCompartmentOcid
    model_id         = var.genai_model_id
  }]
  description = "Generative AI configuration written to the application server."
}

output "vcn_ocid" {
  value       = [var.ociVcnOcid]
  description = "LiveLabs-provided VCN OCID."
}

output "public_subnet_ocid" {
  value       = [var.ociPublicSubnetOcid]
  description = "LiveLabs-provided public subnet OCID."
}
