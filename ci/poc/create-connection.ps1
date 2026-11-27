# Creates a GitHub connection (GitHub App based) named pipeline-poc-github.
# A connection created from the CLI starts as PENDING. Finish it in the console:
#   Developer Tools > Settings > Connections > pipeline-poc-github > Update pending connection
#   > Install a new app (or pick the existing one) > choose your personal account > Connect.
param([string]$Region = 'ap-south-1')
$ErrorActionPreference = 'Stop'
$arn = aws codeconnections create-connection --region $Region --provider-type GitHub --connection-name 'pipeline-poc-github' --tags Key=Project,Value=pipeline-poc --query ConnectionArn --output text
Write-Host "ConnectionArn: $arn"
Write-Host 'Now authorize it in the console (Update pending connection), then wait for status Available.'
