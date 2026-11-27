# Values only. Logic is in terragrunt.hcl.
locals {
  repositories = {
    "poc-stage/app1/api" = { team = "backend", image_tag_mutability = "MUTABLE", max_image_count = 5 }
  }
}