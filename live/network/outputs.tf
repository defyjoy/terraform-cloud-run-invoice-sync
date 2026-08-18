output "connector_id" {
  description = "Full resource ID of the Serverless VPC Access connector."
  value       = module.network.connector_id
}

output "network_name" {
  description = "Name of the created VPC."
  value       = module.network.network_name
}
