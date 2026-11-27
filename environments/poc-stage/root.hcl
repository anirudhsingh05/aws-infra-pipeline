locals {
  env_config = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  aws_region = local.env_config.locals.region
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  # Credentials are assumed BEFORE Terragrunt runs (buildspec sts assume-role),
  # so the provider uses the ambient credentials.
  contents = <<EOF
provider "aws" {
  region = "${local.aws_region}"
}
EOF
}

remote_state {
  backend = "s3"
  generate = {
    path      = "state.tf"
    if_exists = "overwrite_terragrunt"
  }

  # The bucket is created by hand for the POC. One bucket per environment.
  config = {
    bucket       = "pipeline-poc-stage-tfstate-730335384723"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = "${local.aws_region}"
    encrypt      = true
    use_lockfile = true

    disable_bucket_update = true
  }
}