output "service_name" {
  description = "Name of the created service."
  value       = module.cloud_run.service_name
}

output "service_id" {
  description = "Fully qualified service ID (projects/{project}/locations/{location}/services/{name})."
  value       = module.cloud_run.service_id
}

output "url" {
  description = "URL the service is reachable at."
  value       = module.cloud_run.service_uri
}

output "location" {
  description = "Location the service was created in."
  value       = module.cloud_run.location
}

output "project_id" {
  description = "Project the service was created in."
  value       = module.cloud_run.project_id
}

output "service_account_id" {
  description = "ID and email of the service account the revision runs as."
  value       = module.cloud_run.service_account_id
}

output "latest_ready_revision" {
  description = "Name of the latest revision that is serving traffic."
  value       = module.cloud_run.latest_ready_revision
}
