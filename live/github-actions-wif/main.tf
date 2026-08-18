# Deploy identity for GitHub Actions, kept in its own state and applied by hand — it has to
# exist before the pipeline can authenticate at all, so it can't be part of the stack (see
# ../invoice-sync) the pipeline itself manages.
module "github_wif" {
  source = "../../modules/github-actions-wif"

  project_id   = var.project_id
  github_owner = var.github_owner
  github_repo  = var.github_repo
}

# The pipeline runs terraform init/apply itself, so its deploy service account needs write
# access to the shared state bucket (owned by the google-cloud-terraform repo, not this one).
resource "google_storage_bucket_iam_member" "deploy_can_write_state" {
  bucket = var.state_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${module.github_wif.service_account_email}"
}
