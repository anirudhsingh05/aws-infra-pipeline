# Values only. Logic is in terragrunt.hcl.
locals {
  repositories = {
    "poc-dev/base-images" = { team = "platform", image_tag_mutability = "MUTABLE", max_image_count = 5 }
  }
}