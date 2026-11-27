locals {
  environment = "poc-dev"
  region      = "ap-south-1"
  project     = "pipeline-poc"

  # Mandatory tags applied to every resource in this environment.
  common_tags = {
    Environment = "poc-dev"
    Project     = "pipeline-poc"
    Owner       = "devops-team"
    CreatedBy   = "terragrunt"
  }
}