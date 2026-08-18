output "repository_id" {
  description = "ID of the created repo."
  value       = google_artifact_registry_repository.this.repository_id
}

output "image_prefix" {
  description = "Prefix to build image references from, e.g. \"<prefix>/<image>:<tag>\"."
  value       = "${var.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.this.repository_id}"
}
