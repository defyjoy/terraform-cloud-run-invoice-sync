variable "project_id" {
  description = "ID of the project the pool, provider and deploy service account are created in."
  type        = string
}

variable "github_owner" {
  description = "GitHub org or user that owns the repo allowed to exchange tokens through this pool."
  type        = string
}

variable "github_repo" {
  description = "GitHub repo (without owner) allowed to exchange tokens through this pool."
  type        = string
}

variable "github_ref" {
  description = "Git ref (e.g. \"refs/heads/main\") allowed to exchange tokens through this pool. Only the ref the deploy workflow actually runs from should be allowed — any other branch or tag in the repo is refused."
  type        = string
}

variable "pool_id" {
  description = "ID of the workload identity pool."
  type        = string
  default     = "github-actions-pool"
}

variable "provider_id" {
  description = "ID of the workload identity pool provider."
  type        = string
  default     = "github-actions-provider"
}

variable "deploy_account_id" {
  description = "Account ID (local part of the email) for the deploy service account."
  type        = string
}

variable "state_bucket" {
  description = "GCS bucket to grant the deploy service account roles/storage.objectAdmin on, so it can run terraform init/apply itself."
  type        = string
}
