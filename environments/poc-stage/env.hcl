locals {
  environment = "poc-stage"
  region      = "ap-south-1"
  project     = "pipeline-poc"

  # Mandatory tags applied to every resource in this environment.
  common_tags = {
    Environment = "poc-stage"
    Project     = "pipeline-poc"
    Owner       = "devops-team"
    CreatedBy   = "terragrunt"
  }
}