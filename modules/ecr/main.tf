############################################################################
# ecr: self-contained multi-repository module (for_each).
#
# Per map key creates: an ECR repository, an optional lifecycle policy
# (module default or caller-supplied JSON), and an optional repository
# (resource) policy. Every resource is keyed by the repository name.
############################################################################

locals {
  # Resolve the concrete repository name per key.
  # The key IS the repository name (e.g. "dev/service1"); ECR allows "/" as a
  # namespace separator. An explicit repository_name bypasses this.
  repo_names = {
    for k, r in var.repositories :
    k => r.repository_name != "" ? r.repository_name : k
  }

  # Default lifecycle policy applied when the caller does not supply one.
  #
  # Two rules, evaluated by rulePriority (lowest first). This is the predictable,
  # production-standard shape; per AWS a `tagStatus = "any"` rule must have the
  # highest rulePriority and be evaluated last:
  #   rule 1 - expire UNTAGGED images older than N days (clean up CI churn)
  #   rule 2 - keep only the newest N images overall (any tag status)
  #
  # Note: ECR has no way to exempt specific tags from the count cap, so promoted
  # release images are retained by recency like everything else. Raise
  # max_image_count (or supply a custom lifecycle_policy) if you need a deeper
  # history. A tagged/tagPatternList rule was deliberately NOT used because it
  # interacts ambiguously with the required last-place `any` rule.
  default_lifecycle_policies = {
    for k, r in var.repositories : k => jsonencode({
      rules = [
        {
          rulePriority = 1
          description  = "Expire untagged images older than ${r.untagged_expire_days} days"
          selection = {
            tagStatus   = "untagged"
            countType   = "sinceImagePushed"
            countUnit   = "days"
            countNumber = r.untagged_expire_days
          }
          action = { type = "expire" }
        },
        {
          rulePriority = 2
          description  = "Keep only the newest ${r.max_image_count} images"
          selection = {
            tagStatus   = "any"
            countType   = "imageCountMoreThan"
            countNumber = r.max_image_count
          }
          action = { type = "expire" }
        }
      ]
    })
  }

  # Final lifecycle policy JSON per key (caller-supplied wins).
  lifecycle_policies = {
    for k, r in var.repositories :
    k => r.lifecycle_policy != "" ? r.lifecycle_policy : local.default_lifecycle_policies[k]
  }

  # ECR actions for cross-account access. Push always includes pull.
  pull_actions = [
    "ecr:BatchCheckLayerAvailability",
    "ecr:BatchGetImage",
    "ecr:GetDownloadUrlForLayer",
  ]
  push_actions = [
    "ecr:CompleteLayerUpload",
    "ecr:DescribeImages", # push-ecr checks whether the tag already exists
    "ecr:InitiateLayerUpload",
    "ecr:PutImage",
    "ecr:UploadLayerPart",
  ]

  # Repos that get a GENERATED policy: at least one account or principal
  # listed and no explicit repository_policy (an explicit one always wins).
  generated_policy_repos = {
    for k, r in var.repositories : k => r
    if r.repository_policy == "" && (length(r.pull_account_ids) > 0 || length(r.push_account_ids) > 0 || length(r.push_principal_arns) > 0)
  }

  # Final policy JSON per repo: explicit JSON, or the generated one.
  repo_policies = merge(
    { for k, r in var.repositories : k => r.repository_policy if r.repository_policy != "" },
    { for k, r in local.generated_policy_repos : k => data.aws_iam_policy_document.cross_account[k].json },
  )
}

############################################
# Generated cross-account policy (pull and/or push)
############################################
data "aws_iam_policy_document" "cross_account" {
  for_each = local.generated_policy_repos

  dynamic "statement" {
    for_each = length(each.value.pull_account_ids) > 0 ? [1] : []
    content {
      sid     = "AllowPull"
      effect  = "Allow"
      actions = local.pull_actions

      principals {
        type        = "AWS"
        identifiers = [for id in each.value.pull_account_ids : "arn:aws:iam::${id}:root"]
      }
    }
  }

  dynamic "statement" {
    for_each = length(each.value.push_account_ids) > 0 ? [1] : []
    content {
      sid     = "AllowPush"
      effect  = "Allow"
      actions = concat(local.pull_actions, local.push_actions)

      principals {
        type        = "AWS"
        identifiers = [for id in each.value.push_account_ids : "arn:aws:iam::${id}:root"]
      }
    }
  }

  # Push limited to named roles/users. The principal is their account and the
  # condition pins the exact ARN. Naming the role as the principal directly
  # would fail while the role does not exist, and break if it is recreated.
  dynamic "statement" {
    for_each = length(each.value.push_principal_arns) > 0 ? [1] : []
    content {
      sid     = "AllowPushFromPrincipals"
      effect  = "Allow"
      actions = concat(local.pull_actions, local.push_actions)

      principals {
        type        = "AWS"
        identifiers = distinct([for arn in each.value.push_principal_arns : "arn:aws:iam::${split(":", arn)[4]}:root"])
      }

      condition {
        test     = "ArnEquals"
        variable = "aws:PrincipalArn"
        values   = each.value.push_principal_arns
      }
    }
  }
}

############################################
# ECR repository (one per key)
############################################
resource "aws_ecr_repository" "this" {
  for_each = var.repositories

  name                 = local.repo_names[each.key]
  image_tag_mutability = each.value.image_tag_mutability
  force_delete         = each.value.force_delete

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push
  }

  encryption_configuration {
    encryption_type = each.value.encryption_type
    # kms_key only valid when encryption_type = "KMS"; null falls back to the
    # AWS-managed ECR key.
    kms_key = each.value.encryption_type == "KMS" && each.value.kms_key != "" ? each.value.kms_key : null
  }

  # Tag precedence (lowest -> highest):
  #   1. Team             - owning team from the repo entry (if set).
  #   2. each.value.tags  - optional extra per-repo tags from config.hcl.
  #   3. var.tags         - mandatory root/common tags from env.hcl. These
  #                         ALWAYS win; per-repo tags cannot override them.
  #   4. Name             - module-managed, always last.
  tags = merge(
    each.value.team != "" ? { Team = each.value.team } : {},
    each.value.tags,
    var.tags,
    { Name = local.repo_names[each.key] },
  )
}

############################################
# Lifecycle policy (one per key — always set; default or caller JSON)
############################################
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = var.repositories

  repository = aws_ecr_repository.this[each.key].name
  policy     = local.lifecycle_policies[each.key]
}

############################################
# Repository (resource) policy (only when supplied)
############################################
resource "aws_ecr_repository_policy" "this" {
  for_each = local.repo_policies

  repository = aws_ecr_repository.this[each.key].name
  policy     = each.value
}

# test2: comment-only change to the module
