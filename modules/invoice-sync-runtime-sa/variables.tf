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

variable "sa_admin_members" {
  description = "Fully qualified members (e.g. \"serviceAccount:...\") granted roles/iam.serviceAccountAdmin on this service account only (not project-wide) — lets them manage IAM policy (e.g. grant themselves actAs) on this one SA without resourcemanager.projects.setIamPolicy or iam.serviceAccounts.setIamPolicy at the project level."
  type        = list(string)
  default     = []
}
