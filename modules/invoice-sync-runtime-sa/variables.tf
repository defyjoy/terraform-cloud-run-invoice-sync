variable "project_id" {
  description = "ID of the project the service account is created in."
  type        = string
}

variable "account_id" {
  description = "Account ID (local part of the email) of the service account. Must match the deterministic name ../invoice-sync's create_service_account = true actually generates (\"<service_name>-<region>-sa\", truncated to 27 chars) — this module grants roles to that account, it doesn't create it."
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
