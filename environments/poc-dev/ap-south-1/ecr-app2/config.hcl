# Values only. Logic is in terragrunt.hcl.
locals {
  repositories = {
    "poc-dev/app2/worker" = { team = "backend", image_tag_mutability = "MUTABLE", max_image_count = 5 }
  }
}