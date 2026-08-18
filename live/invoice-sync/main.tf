resource "google_artifact_registry_repository" "invoice_sync" {
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_registry_repo
  format        = "DOCKER"
  description   = "invoice-sync Cloud Run images, built and pushed by the deploy pipeline."
}

module "cloud_run" {
  source = "../../modules/cloud-run"

  project_id   = var.project_id
  service_name = var.service_name
  location     = var.region

  image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.invoice_sync.repository_id}/invoice-sync:${var.image_tag}"

  create_service_account = true
  service_account_project_roles = [
    "roles/logging.logWriter",
    "roles/cloudtrace.agent",
    "roles/secretmanager.secretAccessor",
  ]

  min_instance_count = var.min_instance_count
  max_instance_count = var.max_instance_count

  deletion_protection = var.deletion_protection

  labels = {
    service = "invoice-sync"
  }
}

module "github_wif" {
  source = "../../modules/github-actions-wif"

  project_id   = var.project_id
  github_owner = var.github_owner
  github_repo  = var.github_repo
}

# Lets the deploy service account act as the Cloud Run runtime service account when deploying
# new revisions, without granting it broader iam.serviceAccountUser on the whole project.
resource "google_service_account_iam_member" "deploy_can_act_as_runtime" {
  service_account_id = module.cloud_run.service_account_id
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${module.github_wif.service_account_email}"
}

# The pipeline runs terraform init/apply itself, so its deploy service account needs write
# access to the shared state bucket (owned by the google-cloud-terraform repo, not this one).
resource "google_storage_bucket_iam_member" "deploy_can_write_state" {
  bucket = var.state_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${module.github_wif.service_account_email}"
}

module "deployment_alert" {
  source = "../../modules/deployment-failure-alert"

  project_id         = var.project_id
  service_name       = module.cloud_run.service_name
  notification_email = var.notification_email
}
