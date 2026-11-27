terraform {
  source = "${get_repo_root()}/modules/ecr"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path           = find_in_parent_folders("env.hcl")
  expose         = true
  merge_strategy = "no_merge"
}

include "account" {
  path           = find_in_parent_folders("account.hcl")
  expose         = true
  merge_strategy = "no_merge"
}

# Ordering only (no outputs consumed): apply ecr-base first.
dependencies {
  paths = ["../ecr-base"]
}

locals {
  config = read_terragrunt_config("${get_terragrunt_dir()}/config.hcl").locals
}

inputs = {
  repositories = local.config.repositories
  tags         = include.env.locals.common_tags
}