output "external_ip" {
  description = "Public IPv4 address of the load balancer's forwarding rule."
  value       = module.lb.external_ip
}

output "url_map" {
  description = "Self link of the URL map."
  value       = module.lb.url_map
}

output "neg_id" {
  description = "ID of the serverless NEG backing the load balancer."
  value       = google_compute_region_network_endpoint_group.this.id
}
