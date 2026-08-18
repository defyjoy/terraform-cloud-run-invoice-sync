variable "project_id" {
  description = "ID of the project everything is created in."
  type        = string
  default     = "yeti-504903"
}

variable "region" {
  description = "Region for Cloud Run, Artifact Registry and the google provider."
  type        = string
  default     = "us-central1"
}

variable "service_name" {
  description = "Name of the Cloud Run service."
  type        = string
  default     = "invoice-sync"
}

variable "artifact_registry_repo" {
  description = "ID of the Artifact Registry Docker repo images are pushed to."
  type        = string
  default     = "invoice-sync"
}

variable "image_tag" {
  description = "Tag of the invoice-sync image to deploy, e.g. a git SHA. No default — the pipeline always passes this explicitly."
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

variable "notification_email" {
  description = "Address notified when a Cloud Run revision fails to become ready."
  type        = string
}

variable "state_bucket" {
  description = "GCS bucket holding this stack's Terraform state. Must match Taskfile's STATE_BUCKET — the deploy service account is granted write access to it so the pipeline can run terraform apply."
  type        = string
  default     = "yeti-terraform-state-bucket"
}

variable "min_instance_count" {
  description = "Minimum number of instances kept running. 0 allows scale-to-zero."
  type        = number
  default     = 0
}

variable "max_instance_count" {
  description = "Maximum number of instances the service can scale out to."
  type        = number
  default     = 2
}

variable "deletion_protection" {
  description = "Block terraform destroy on the service."
  type        = bool
  default     = true
}
