variable "project_id" {
  description = "ID of the project the service account is created in."
  type        = string
}

variable "account_id" {
  description = "Account ID (local part of the email). Must match the deterministic name ../invoice-sync's create_service_account = true actually generates (\"<service_name>-<region>-sa\") — this stack grants roles to that account, it doesn't create it."
  type        = string
}

variable "project_roles" {
  description = "Project-level IAM roles granted to the service account."
  type        = list(string)
}

variable "deploy_account_id" {
  description = "Account ID (local part of the email) of the GitHub Actions deploy service account created by ../github-actions-wif. Must match that stack's own deploy_account_id."
  type        = string
}
