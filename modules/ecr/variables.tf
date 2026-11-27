# ---------------------------------------------------------------------------
# ecr: create N ECR repositories from a map (for_each).
#
# Each entry in `repositories` is one complete ECR repository. The map key IS
# the repository name, in the form "<env>/<app_name>" (e.g. "dev/service1"), so
# one registry can hold repos for several environments side by side.
# Add a key -> one more repo. Remove a key -> that repo is destroyed. Do NOT
# rename a key in place (destroy + recreate).
#
# An explicit name can still be forced per entry with `repository_name`.
#
# Tagging: mandatory root tags come from `tags` (set in env.hcl) and ALWAYS
# win. Per-repo `tags` (e.g. team segregation) are merged underneath and cannot
# override a root tag. A per-repo `Name` tag is added automatically.
# ---------------------------------------------------------------------------

variable "repositories" {
  description = <<-EOT
    Map of ECR repositories keyed by repository name ("<env>/<app_name>").

    Per entry:
      repository_name         (string)        - explicit repo name, or "" => use the map key
      image_tag_mutability    (string)        - "MUTABLE" or "IMMUTABLE". Default "IMMUTABLE".
      scan_on_push            (bool)          - scan images on push. Default true.
      force_delete            (bool)          - delete repo even if it has images. Default false.
      encryption_type         (string)        - "AES256" or "KMS". Default "AES256".
      kms_key                 (string)        - KMS key ARN/ID when encryption_type = "KMS". "" => AWS-managed.
      lifecycle_policy        (string)        - raw JSON lifecycle policy, or "" to use the defaults below.
      max_image_count         (number)        - keep only the newest N images overall (default policy). Default 20.
      untagged_expire_days    (number)        - expire untagged images after N days (default policy). Default 7.
      team                    (string)        - owning team (e.g. "data", "backend", "frontend"). When set,
                                                emitted as a "Team" tag. "" => no Team tag.
      pull_account_ids        (list(string))  - AWS account IDs allowed to PULL images (read-only). Default [].
      push_account_ids        (list(string))  - AWS account IDs allowed to PUSH and pull images (any
                                                principal in the account). Default [].
      push_principal_arns     (list(string))  - IAM role/user ARNs allowed to PUSH and pull images (only
                                                these principals). Matched on aws:PrincipalArn, so the
                                                role does not have to exist yet. Default [].
      repository_policy       (string)        - raw JSON repository policy, or "". When set it REPLACES
                                                the policy generated from the lists above.
      tags                    (map(string))   - extra per-repo tags. Merged UNDER the mandatory root
                                                tags, so they cannot override them.
  EOT
  type = map(object({
    repository_name      = optional(string, "")
    image_tag_mutability = optional(string, "IMMUTABLE")
    scan_on_push         = optional(bool, true)
    force_delete         = optional(bool, false)
    encryption_type      = optional(string, "AES256")
    kms_key              = optional(string, "")
    lifecycle_policy     = optional(string, "")
    max_image_count      = optional(number, 20)
    untagged_expire_days = optional(number, 7)
    team                 = optional(string, "")
    pull_account_ids     = optional(list(string), [])
    push_account_ids     = optional(list(string), [])
    push_principal_arns  = optional(list(string), [])
    repository_policy    = optional(string, "")
    tags                 = optional(map(string), {})
  }))
  default = {}

  # Cross-account IDs must be 12-digit AWS account IDs.
  validation {
    condition = alltrue(flatten([
      for r in values(var.repositories) :
      [for id in concat(r.pull_account_ids, r.push_account_ids) : can(regex("^[0-9]{12}$", id))]
    ]))
    error_message = "pull_account_ids and push_account_ids must contain 12-digit AWS account IDs."
  }

  validation {
    condition = alltrue(flatten([
      for r in values(var.repositories) :
      [for arn in r.push_principal_arns : can(regex("^arn:aws:iam::[0-9]{12}:(role|user)/[A-Za-z0-9+=,.@_/-]+$", arn))]
    ]))
    error_message = "push_principal_arns must contain IAM role or user ARNs, e.g. arn:aws:iam::123456789012:role/example-push-role."
  }

  # Fail fast on invalid enum values rather than surfacing an obscure AWS API error.
  validation {
    condition = alltrue([
      for r in values(var.repositories) :
      contains(["MUTABLE", "IMMUTABLE"], r.image_tag_mutability)
    ])
    error_message = "Each repository's image_tag_mutability must be either \"MUTABLE\" or \"IMMUTABLE\"."
  }

  validation {
    condition = alltrue([
      for r in values(var.repositories) :
      contains(["AES256", "KMS"], r.encryption_type)
    ])
    error_message = "Each repository's encryption_type must be either \"AES256\" or \"KMS\"."
  }

  validation {
    condition = alltrue([
      for r in values(var.repositories) :
      r.encryption_type == "KMS" || r.kms_key == ""
    ])
    error_message = "kms_key may only be set when encryption_type is \"KMS\"."
  }

  validation {
    condition = alltrue([
      for r in values(var.repositories) :
      r.max_image_count >= 1 && r.untagged_expire_days >= 1
    ])
    error_message = "max_image_count and untagged_expire_days must both be >= 1."
  }

  # The FINAL repository name (repository_name if set, otherwise the map key)
  # must satisfy ECR's naming rules: lowercase alphanumerics with ._-/ separators.
  validation {
    condition = alltrue([
      for k, r in var.repositories :
      can(regex("^(?:[a-z0-9]+(?:[._-][a-z0-9]+)*/)*[a-z0-9]+(?:[._-][a-z0-9]+)*$", r.repository_name != "" ? r.repository_name : k))
    ])
    error_message = "Each repository name (the map key, or repository_name if set) must be a valid ECR name: lowercase, with only ._-/ as separators."
  }
}

variable "tags" {
  description = <<-EOT
    Mandatory root/common tags from env.hcl, applied to every repository.
    These ALWAYS take precedence: per-repo tags in `repositories[*].tags` are
    merged underneath and cannot override any key set here.
  EOT
  type        = map(string)
  default     = {}
}
