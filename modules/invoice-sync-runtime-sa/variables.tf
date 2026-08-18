variable "project_id" {
  description = "ID of the project the service account is created in."
  type        = string
}

variable "account_id" {
  description = "Account ID (local part of the email) for the service account. Must match the deterministic name modules/cloud-run's create_service_account = true would have generated (\"<service_name>-<region>-sa\", truncated to 27 chars), since live/invoice-sync references it by that same deterministic email."
  type        = string
}

variable "service_name" {
  description = "Name of the Cloud Run service this account runs as, used only in its display name."
  type        = string
}

variable "project_roles" {
  description = "Project-level IAM roles granted to the service account, e.g. [\"roles/logging.logWriter\"]."
  type        = list(string)
  default     = []
}

variable "actas_members" {
  description = "Fully qualified members (e.g. \"serviceAccount:...\") granted roles/iam.serviceAccountUser on this service account."
  type        = list(string)
  default     = []
}
