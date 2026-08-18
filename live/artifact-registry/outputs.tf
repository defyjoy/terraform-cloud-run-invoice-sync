output "repository_id" {
  description = "ID of the created repo."
  value       = module.artifact_registry.repository_id
}

output "image_prefix" {
  description = "Prefix to build image references from, e.g. \"<prefix>/<image>:<tag>\"."
  value       = module.artifact_registry.image_prefix
}
