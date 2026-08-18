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

  # Must match ../invoice-sync's own region/service_name/artifact_registry_repo — these scope
  # the deploy SA's run.admin and artifactregistry.writer grants to that one service and repo
  # via IAM Conditions, instead of leaving them project-wide.
  region                 = var.region
  cloud_run_service_name = var.cloud_run_service_name
  artifact_registry_repo = var.artifact_registry_repo

  # The pipeline runs terraform init/apply itself, so its deploy service account needs write
  # access to the shared state bucket (owned by the google-cloud-terraform repo, not this one).
  state_bucket = var.state_bucket
}
