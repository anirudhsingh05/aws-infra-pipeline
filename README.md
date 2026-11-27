# pipeline-poc

Proof of concept for a change-aware Terragrunt deployment pipeline (AWS CodePipeline and CodeBuild, source in GitHub).

Only the units that changed since the last successful deployment of an environment are planned and applied. The baseline is read from CodePipeline's own execution history, so nothing is stored in SSM or DynamoDB.

## Layout

| Path | Purpose |
|---|---|
| `environments/poc-dev`, `environments/poc-stage` | Two environments, each with its own state bucket |
| `environments/<env>/ap-south-1/ecr-base` | Unit 1: base ECR repository |
| `environments/<env>/ap-south-1/ecr-app1` | Unit 2: app ECR repository, depends on `ecr-base` |
| `modules/ecr` | The Terraform module used by both units |
| `ci/buildspecs/` | Resolve, Plan, Apply and CommitBaseline buildspecs |
| `ci/poc/` | Scripts to create the GitHub connection, set repository access and create the pipeline |
| `docs/change-aware-deployment/POC.md` | POC runbook: resources created and cleanup |


(test3b: unrelated docs commit after a rejected change)
