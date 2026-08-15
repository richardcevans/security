locals {
  home_ip_cidr = "${var.allowed_ingress_home_ip_address}/32"

  common_tags = {
    lab        = "deep-sec"
    managed_by = "terraform"
  }
}
