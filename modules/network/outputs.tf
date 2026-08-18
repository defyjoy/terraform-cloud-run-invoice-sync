output "connector_id" {
  description = "Full resource ID of the Serverless VPC Access connector, for Cloud Run's vpc_access.connector."
  value       = tolist(module.serverless_connector.connector_ids)[0]
}

output "network_name" {
  description = "Name of the created VPC."
  value       = module.vpc.network_name
}

output "network_self_link" {
  description = "Self link of the created VPC."
  value       = module.vpc.network_self_link
}
