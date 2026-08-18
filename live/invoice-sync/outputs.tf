output "service_url" {
  description = "Direct Cloud Run URL. Rejects requests that didn't come through the load balancer, per ingress = INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  value       = module.cloud_run.url
}

output "load_balancer_ip" {
  description = "Public IP of the load balancer fronting the service. This is the address to browse."
  value       = module.lb.external_ip
}

output "deploy_service_account_email" {
  description = "Email of the deploy service account. Set as the DEPLOY_SA_EMAIL GitHub repo variable."
  value       = module.github_wif.service_account_email
}

output "workload_identity_provider" {
  description = "Full resource name of the WIF provider. Set as the WIF_PROVIDER GitHub repo variable."
  value       = module.github_wif.workload_identity_provider
}

output "alert_policy_id" {
  description = "ID of the alert policy watching for failed revisions."
  value       = module.deployment_alert.alert_policy_id
}
