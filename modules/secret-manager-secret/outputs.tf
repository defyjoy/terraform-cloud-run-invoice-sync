output "secret_id" {
  description = "ID of the created secret."
  value       = google_secret_manager_secret.this.secret_id
}

output "kms_key_id" {
  description = "Resource ID of the CMEK key encrypting this secret's payloads."
  value       = google_kms_crypto_key.this.id
}
