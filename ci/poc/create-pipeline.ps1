# Creates or updates the POC pipeline pipeline-poc-iac (V2, QUEUED).
# Run it with AWS credentials for the POC account (ap-south-1) after the GitHub connection is AVAILABLE.
#
#   .\ci\poc\create-pipeline.ps1 -ConnectionArn arn:aws:codeconnections:ap-south-1:730335384723:connection/xxxx -Repository <github-user>/pipeline-poc
#   .\ci\poc\create-pipeline.ps1 -ConnectionArn <arn> -Repository <github-user>/pipeline-poc -BootstrapDev $false   # after PocDev's first success
#
# -BootstrapDev / -BootstrapStage set BOOTSTRAP=true on that stage's Resolve action: the very first
# run of an environment plans ALL units. Switch each one off once its stage has one successful CommitBaseline.
param(
  [Parameter(Mandatory = $true)][string]$ConnectionArn,
  [Parameter(Mandatory = $true)][string]$Repository,   # <github-user>/<repo>, exact case
  [bool]$BootstrapDev = $true,     # set to $false after PocDev has one successful CommitBaseline
  [bool]$BootstrapStage = $true,   # set to $false after PocStage has one successful CommitBaseline
  [string]$Account = '730335384723',
  [string]$Region = 'ap-south-1',
  [string]$TerraformVersion = '1.17.2',
  [string]$TerragruntVersion = '1.2.3',
  [switch]$DryRun   # only write the JSON definition, do not call AWS
)
$ErrorActionPreference = 'Stop'
$p = 'pipeline-poc'; $pipeline = "$p-iac"

function EV($h) {
  $list = foreach ($k in $h.Keys) { @{ name = $k; value = [string]$h[$k]; type = 'PLAINTEXT' } }
  return (ConvertTo-Json -InputObject @($list) -Compress -Depth 5)
}
function Build($name, $project, $inputs, $outputs, $ns, $order, $vars) {
  $cfg = @{ ProjectName = $project; PrimarySource = 'SourceOutput'; EnvironmentVariables = (EV $vars) }
  $a = @{
    name = $name; runOrder = $order
    actionTypeId = @{ category = 'Build'; owner = 'AWS'; provider = 'CodeBuild'; version = '1' }
    configuration = $cfg
    inputArtifacts = @($inputs | ForEach-Object { @{ name = $_ } })
    outputArtifacts = @($outputs | ForEach-Object { @{ name = $_ } })
  }
  if ($ns) { $a.namespace = $ns }
  return $a
}
function EnvStage($stage, $suffix, $envName, $roleName, $bootstrap) {
  $envPath = "environments/$envName"
  $common = @{ ENV_PATH = $envPath; PIPELINE_NAME = $pipeline; PIPELINE_STAGE_NAME = $stage; PIPELINE_EXECUTION_ID = '#{codepipeline.PipelineExecutionId}' }
  $tools = @{ TERRAFORM_VERSION = $TerraformVersion; TERRAGRUNT_VERSION = $TerragruntVersion }
  $target = @{ TARGET_ROLE_ARN = "arn:aws:iam::${Account}:role/$roleName"; TARGET_ACCOUNT_ID = $Account }
  $expected = @{ EXPECTED_MANIFEST_SHA256 = "#{Plan$suffix.MANIFEST_SHA256}"; EXPECTED_PLAN_RESULT_SHA256 = "#{Plan$suffix.PLAN_RESULT_SHA256}"; PLAN_ARTIFACT_NAME = "PlanOutput$suffix" }

  $resolveVars = $common + $tools + @{ SOURCE_COMMIT = '#{SourceVariables.CommitId}' }
  if ($bootstrap) { $resolveVars.BOOTSTRAP = 'true' }
  $planVars = $common + $tools + $target + @{ MANIFEST_ARTIFACT_NAME = "ManifestOutput$suffix" }
  $applyVars = $common + $tools + $target + $expected + @{ APPLY_MODE = 'changes' }
  $commitVars = $common + $expected

  $approval = @{
    name = 'Approve'; runOrder = 3
    actionTypeId = @{ category = 'Approval'; owner = 'AWS'; provider = 'Manual'; version = '1' }
    configuration = @{ CustomData = "Env $envName. Units: #{Resolve$suffix.UNIT_COUNT}, removed: #{Resolve$suffix.DESTROY_COUNT}, apply required: #{Plan$suffix.APPLY_REQUIRED}, destroy required: #{Plan$suffix.DESTROY_REQUIRED}. Manifest: #{Plan$suffix.MANIFEST_SHA256}" }
  }
  $destroyVars = $applyVars.Clone(); $destroyVars.APPLY_MODE = 'destroy'
  $approveDestroy = @{
    name = 'ApproveDestroy'; runOrder = 5
    actionTypeId = @{ category = 'Approval'; owner = 'AWS'; provider = 'Manual'; version = '1' }
    configuration = @{ CustomData = "DESTROY gate for $envName. Destroy required: #{Plan$suffix.DESTROY_REQUIRED} (if false, approve: nothing will be destroyed). Manifest: #{Plan$suffix.MANIFEST_SHA256}" }
  }
  return @{
    name = $stage
    actions = @(
      (Build 'Resolve' "$p-resolve" @('SourceOutput') @("ManifestOutput$suffix") "Resolve$suffix" 1 $resolveVars),
      (Build 'Plan' "$p-plan" @('SourceOutput', "ManifestOutput$suffix") @("PlanOutput$suffix") "Plan$suffix" 2 $planVars),
      $approval,
      (Build 'Apply' "$p-apply" @('SourceOutput', "PlanOutput$suffix") @() $null 4 $applyVars),
      $approveDestroy,
      (Build 'ApplyDestroy' "$p-apply" @('SourceOutput', "PlanOutput$suffix") @() $null 6 $destroyVars),
      (Build 'CommitBaseline' "$p-commit" @('SourceOutput', "PlanOutput$suffix") @() $null 7 $commitVars)
    )
  }
}

$source = @{
  name = 'Source'
  actions = @(@{
      name = 'Source'; runOrder = 1; namespace = 'SourceVariables'
      actionTypeId = @{ category = 'Source'; owner = 'AWS'; provider = 'CodeStarSourceConnection'; version = '1' }
      outputArtifacts = @(@{ name = 'SourceOutput' })
      configuration = @{ ConnectionArn = $ConnectionArn; FullRepositoryId = $Repository; BranchName = 'main'; OutputArtifactFormat = 'CODEBUILD_CLONE_REF'; DetectChanges = 'true' }
    })
}

$definition = @{
  pipeline = @{
    name = $pipeline
    roleArn = "arn:aws:iam::${Account}:role/$p-codepipeline"
    artifactStore = @{ type = 'S3'; location = "$p-artifacts-$Account" }
    pipelineType = 'V2'
    executionMode = 'QUEUED'
    stages = @($source, (EnvStage 'PocDev' 'Dev' 'poc-dev' "$p-tf-admin-dev" $BootstrapDev), (EnvStage 'PocStage' 'Stage' 'poc-stage' "$p-tf-admin-stage" $BootstrapStage))
  }
}
$file = Join-Path $env:TEMP 'pipeline-poc-iac.json'
[IO.File]::WriteAllText($file, ($definition | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))

if ($DryRun) { Write-Host "Dry run. Definition written to $file"; return }
$existing = aws codepipeline list-pipelines --region $Region --query "pipelines[?name=='$pipeline'].name | [0]" --output text
if ($existing -eq $pipeline) {
  aws codepipeline update-pipeline --region $Region --cli-input-json ("file://" + ($file -replace '\\', '/')) --query 'pipeline.name' --output text
} else {
  aws codepipeline create-pipeline --region $Region --cli-input-json ("file://" + ($file -replace '\\', '/')) --query 'pipeline.name' --output text
}
Write-Host "Definition written to $file"
