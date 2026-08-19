output "secret_id" {
  description = "ID of the created secret."
  value       = google_secret_manager_secret.this.secret_id
}
