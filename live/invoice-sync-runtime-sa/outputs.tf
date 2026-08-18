output "email" {
  description = "Email of the runtime service account."
  value       = module.runtime_sa.email
}
