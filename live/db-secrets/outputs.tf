output "db_password_secret_id" {
  description = "ID of the created db-password secret."
  value       = module.db_password.secret_id
}

output "db_password_kms_key_id" {
  description = "Resource ID of the CMEK key encrypting the db-password secret's payloads."
  value       = module.db_password.kms_key_id
}
