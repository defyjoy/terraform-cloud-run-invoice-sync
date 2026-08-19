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

variable "kms_key_rotation_period" {
  description = "How often the CMEK key itself advances to a new key version, e.g. \"7776000s\" (90 days). Google schedules this automatically from creation time; older key versions are retained (not destroyed), so existing secret versions stay decryptable."
  type        = string
  default     = "7776000s"
}

variable "rotation_period" {
  description = "How often Secret Manager publishes a rotation-reminder notification to Pub/Sub, e.g. \"7776000s\" (90 days). This does not rotate the secret value itself — Secret Manager has no way to generate a new one — it only reminds whoever owns the value to do so out-of-band. Null disables rotation notifications entirely (no topic is created)."
  type        = string
  default     = null
}
