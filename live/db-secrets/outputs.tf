output "db_password_secret_id" {
  description = "ID of the created db-password secret."
  value       = module.db_password.secret_id
}
