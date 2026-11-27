# All outputs are maps keyed by the repository key used in `repositories`.

output "repository_arns" {
  description = "Map of repo key => repository ARN."
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}

output "repository_names" {
  description = "Map of repo key => repository name."
  value       = { for k, r in aws_ecr_repository.this : k => r.name }
}

output "repository_urls" {
  description = "Map of repo key => repository URL (push/pull target)."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "registry_ids" {
  description = "Map of repo key => registry (account) ID hosting the repo."
  value       = { for k, r in aws_ecr_repository.this : k => r.registry_id }
}
