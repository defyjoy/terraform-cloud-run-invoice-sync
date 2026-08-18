output "service_account_email" {
  description = "Email of the deploy service account. Set as the DEPLOY_SA_EMAIL GitHub repo variable, and as deploy_service_account_email in ../invoice-sync's tfvars."
  value       = module.github_wif.service_account_email
}

output "workload_identity_provider" {
  description = "Full resource name of the WIF provider. Set as the WIF_PROVIDER GitHub repo variable."
  value       = module.github_wif.workload_identity_provider
}
