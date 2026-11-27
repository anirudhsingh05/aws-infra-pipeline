# Limits the CodeBuild roles' UseConnection permission to one connection and one repository.
# Needed for Full clone: the CodeBuild service role must be allowed to use the connection.
#
#   .\ci\poc\set-repo-access.ps1 -ConnectionArn <arn> -Repository <github-user>/pipeline-poc
param(
  [Parameter(Mandatory = $true)][string]$ConnectionArn,
  [Parameter(Mandatory = $true)][string]$Repository,
  [string]$Region = 'ap-south-1',
  [string]$Account = '730335384723'
)
$ErrorActionPreference = 'Stop'
$p = 'pipeline-poc'
$tmp = Join-Path $env:TEMP 'pipeline-poc-rolepolicy.json'
foreach ($r in @("$p-cb-meta", "$p-cb-plan", "$p-cb-apply")) {
  $cur = aws iam get-role-policy --role-name $r --policy-name inline --query PolicyDocument --output json | ConvertFrom-Json
  $stmts = @()
  foreach ($s in $cur.Statement) {
    $actions = @($s.Action)
    if ($actions -contains 'codeconnections:UseConnection') {
      $s = [ordered]@{
        Effect = 'Allow'
        Action = @('codeconnections:UseConnection', 'codestar-connections:UseConnection')
        Resource = $ConnectionArn
        Condition = @{ StringEquals = @{ 'codeconnections:FullRepositoryId' = $Repository } }
      }
    }
    $stmts += $s
  }
  $doc = @{ Version = '2012-10-17'; Statement = $stmts } | ConvertTo-Json -Depth 12
  [IO.File]::WriteAllText($tmp, $doc, (New-Object Text.UTF8Encoding($false)))
  aws iam put-role-policy --role-name $r --policy-name inline --policy-document ("file://" + ($tmp -replace '\\', '/'))
  Write-Host "updated $r"
}
Remove-Item $tmp -Force
