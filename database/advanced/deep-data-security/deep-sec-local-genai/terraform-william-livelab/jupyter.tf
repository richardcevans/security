resource "random_string" "lab_admin_password" {
  length           = 16
  special          = true
  min_special      = 2
  min_numeric      = 2
  override_special = "#"
}
