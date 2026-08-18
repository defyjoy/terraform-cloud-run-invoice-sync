output "connector_id" {
  description = "Full resource ID of the Serverless VPC Access connector, for Cloud Run's vpc_access.connector."
  value       = google_vpc_access_connector.this.id
}

output "network_name" {
  description = "Name of the created VPC."
  value       = google_compute_network.this.name
}

output "network_self_link" {
  description = "Self link of the created VPC."
  value       = google_compute_network.this.self_link
}
