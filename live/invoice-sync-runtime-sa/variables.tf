variable "project_id" {
  description = "ID of the project the service account is created in."
  type        = string
}

variable "account_id" {
  description = "Account ID (local part of the email). Must match the deterministic name modules/cloud-run's create_service_account = true would have generated (\"<service_name>-<region>-sa\") — ../invoice-sync references this account by that same deterministic email."
  type        = string
}

variable "service_name" {
  description = "Name of the Cloud Run service this account runs as. Must match ../invoice-sync's own service_name."
  type        = string
}

variable "project_roles" {
  description = "Project-level IAM roles granted to the service account. Must match ../invoice-sync's own service_account_project_roles expectations."
  type        = list(string)
}

variable "deploy_account_id" {
  description = "Account ID (local part of the email) of the GitHub Actions deploy service account created by ../github-actions-wif. Must match that stack's own deploy_account_id."
  type        = string
}
