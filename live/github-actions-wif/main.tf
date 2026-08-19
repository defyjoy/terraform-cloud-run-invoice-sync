module "github_wif" {
  source = "../../modules/github-actions-wif"

  project_id        = var.project_id
  github_owner      = var.github_owner
  github_repo       = var.github_repo
  github_ref        = var.github_ref
  deploy_account_id = var.deploy_account_id

  state_bucket = var.state_bucket
}
