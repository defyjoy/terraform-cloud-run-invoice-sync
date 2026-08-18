variable "project_id" {
  description = "ID of the project the pool, provider and deploy service account are created in."
  type        = string
}

variable "github_owner" {
  description = "GitHub org or user that owns the repo allowed to deploy via Workload Identity Federation."
  type        = string
}

variable "github_repo" {
  description = "GitHub repo (without owner) allowed to deploy via Workload Identity Federation."
  type        = string
}

variable "github_ref" {
  description = "Git ref allowed to deploy via Workload Identity Federation, e.g. \"refs/heads/main\". Must match the branch deploy.yml actually triggers on."
  type        = string
}

variable "state_bucket" {
  description = "GCS bucket holding this repo's Terraform state. Must match Taskfile's STATE_BUCKET — the deploy service account is granted write access to it so the pipeline can run terraform apply on ../invoice-sync."
  type        = string
}

variable "deploy_account_id" {
  description = "Account ID (local part of the email) for the deploy service account. Must match ../invoice-sync-runtime-sa's own deploy_account_id and ../invoice-sync's own runtime_service_account_id assumptions — other stacks construct this account's email themselves instead of reading it from this stack's output."
  type        = string
}
