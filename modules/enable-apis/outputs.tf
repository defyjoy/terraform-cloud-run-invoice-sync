output "project_id" {
  description = "Project the services were enabled on."
  value       = var.project_id
}

output "enabled_services" {
  description = "Services enabled by this module."
  value       = [for s in google_project_service.this : s.service]
}

output "services" {
  description = "The google_project_service resources, keyed by service name. Depend on this to order resources after API enablement."
  value       = google_project_service.this
}
