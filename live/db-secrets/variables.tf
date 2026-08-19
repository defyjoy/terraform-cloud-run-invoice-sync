variable "project_id" {
  description = "ID of the project the secret is created in."
  type        = string
}

variable "db_password_secret_id" {
  description = "ID of the db-password secret. Must match ../invoice-sync's own secret_accessor_secrets/env_secret_vars entry for it — that stack references this secret by name, it doesn't create it."
  type        = string
}
