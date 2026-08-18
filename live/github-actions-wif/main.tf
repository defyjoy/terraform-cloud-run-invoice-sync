# Deploy identity for GitHub Actions, kept in its own state and applied by hand — it has to
# exist before the pipeline can authenticate at all, so it can't be part of the stack (see
# ../invoice-sync) the pipeline itself manages.
module "github_wif" {
  source = "../../modules/github-actions-wif"

  project_id        = var.project_id
  github_owner      = var.github_owner
  github_repo       = var.github_repo
  github_ref        = var.github_ref
  deploy_account_id = var.deploy_account_id

  region                 = var.region
  cloud_run_service_name = var.cloud_run_service_name

  state_bucket = var.state_bucket
}
