locals {
  common_tags = {
    "lab"        = "deep-sec-gen-ai-demo"
    "managed-by" = "terraform"
    "prefix"     = var.name_prefix
  }
}
