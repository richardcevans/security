locals {
  home_ip_cidr = "${var.allowed_ingress_home_ip_address}/32"

  common_tags = {
    lab        = "deepsec9"
    managed_by = "terraform"
  }
}
