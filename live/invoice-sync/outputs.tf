output "service_url" {
  description = "Direct Cloud Run URL. Rejects requests that didn't come through the load balancer, per ingress = INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  value       = module.cloud_run.url
}

output "load_balancer_ip" {
  description = "Public IP of the load balancer fronting the service. This is the address to browse."
  value       = module.lb.external_ip
}

output "alert_policy_id" {
  description = "ID of the alert policy watching for failed revisions."
  value       = module.deployment_alert.alert_policy_id
}
