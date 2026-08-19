variable "project_id" {
  description = "ID of the project the secret is created in."
  type        = string
}

variable "secret_id" {
  description = "ID of the secret (not the secret value — no version is created by this module; add one out-of-band, e.g. via gcloud secrets versions add, so the value never lands in Terraform state)."
  type        = string
}

variable "admin_members" {
  description = "Fully qualified members (e.g. \"serviceAccount:...\") granted roles/secretmanager.admin on this secret only (not project-wide) — lets them manage IAM policy on this one secret, e.g. to grant a runtime service account roles/secretmanager.secretAccessor on it, without needing any Secret Manager permission at the project level."
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels applied to the secret."
  type        = map(string)
  default     = {}
}
