variable "project_id" {
  description = "ID of the project the pool, provider and deploy service account are created in."
  type        = string
  default     = "yeti-504903"
}

variable "github_owner" {
  description = "GitHub org or user that owns the repo allowed to deploy via Workload Identity Federation."
  type        = string
}

variable "github_repo" {
  description = "GitHub repo (without owner) allowed to deploy via Workload Identity Federation."
  type        = string
}

variable "state_bucket" {
  description = "GCS bucket holding this repo's Terraform state. Must match Taskfile's STATE_BUCKET — the deploy service account is granted write access to it so the pipeline can run terraform apply on ../invoice-sync."
  type        = string
  default     = "yeti-terraform-state-bucket"
}
