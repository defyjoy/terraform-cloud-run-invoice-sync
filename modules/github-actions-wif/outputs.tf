output "service_account_email" {
  description = "Email of the deploy service account GitHub Actions impersonates."
  value       = module.deploy_service_account.email
}

output "workload_identity_provider" {
  description = "Full resource name of the provider, for google-github-actions/auth's workload_identity_provider input."
  value       = google_iam_workload_identity_pool_provider.github.name
}
