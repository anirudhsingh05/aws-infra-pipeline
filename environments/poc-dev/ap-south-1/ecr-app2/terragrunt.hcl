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

# Real dependency: consumes ecr-app1's outputs. Mocks are allowed ONLY for init and
# validate, so a mock value can never end up in a saved plan.
dependency "app1" {
  config_path = "../ecr-app1"

  mock_outputs_allowed_terraform_commands = ["init", "validate"]
  mock_outputs = {
    repository_names = { "mock" = "mock-repo" }
  }
}

locals {
  config = read_terragrunt_config("${get_terragrunt_dir()}/config.hcl").locals
}

inputs = {
  repositories = {
    for k, r in local.config.repositories : k => merge(r, {
      tags = { UpstreamRepo = values(dependency.app1.outputs.repository_names)[0] }
    })
  }
  tags = include.env.locals.common_tags
}