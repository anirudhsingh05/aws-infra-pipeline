# POC runbook (account 730335384723, ap-south-1)

Everything created for the POC is prefixed `pipeline-poc` and tagged `Project=pipeline-poc`. The account is shared with other teams, so nothing else is touched.

## Resources

| Type | Name |
|---|---|
| State buckets | `pipeline-poc-dev-tfstate-730335384723`, `pipeline-poc-stage-tfstate-730335384723` (versioned, SSE, no public access) |
| Artifact bucket | `pipeline-poc-artifacts-730335384723` |
| CodeBuild roles | `pipeline-poc-cb-meta` (Resolve, Commit), `pipeline-poc-cb-plan`, `pipeline-poc-cb-apply` |
| Target roles | `pipeline-poc-tf-admin-dev`, `pipeline-poc-tf-admin-stage` (ECR on `poc-dev/*` or `poc-stage/*` only, plus their state bucket) |
| CodePipeline role | `pipeline-poc-codepipeline` |
| CodeBuild projects | `pipeline-poc-resolve`, `-plan`, `-apply`, `-commit` (buildspecs under `ci/buildspecs/`) |
| Source connection | `pipeline-poc-github` (GitHub App connection to a personal repository) |
| Pipeline | `pipeline-poc-iac` (V2, QUEUED), stages `PocDev` and `PocStage` |

## Repo layout used by the POC

- `environments/poc-dev` and `environments/poc-stage`: own `root.hcl` (own state bucket), `env.hcl`, `account.hcl`.
- Units per environment: `ecr-base`, `ecr-app1` (ordering dependency on `ecr-base`).
- `ci/buildspecs/*.yaml`: Resolve, Plan, Apply, CommitBaseline.

## Cleanup

Delete the pipeline, the four CodeBuild projects, the five IAM roles, the three buckets (empty them first) and the connection. Destroy the ECR repos through the pipeline or `terragrunt destroy` first.
