module "cloud_run" {
  source  = "GoogleCloudPlatform/cloud-run/google//modules/v2"
  version = "~> 0.32"

  project_id   = var.project_id
  service_name = var.service_name
  location     = var.location

  containers = [
    {
      container_name    = var.container_name
      container_image   = var.image
      container_command = var.container_command
      container_args    = var.container_args
      env_vars          = var.env_vars
      env_secret_vars   = var.env_secret_vars

      ports = {
        container_port = var.port
      }

      resources = {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        cpu_idle = var.cpu_idle
      }
    }
  ]

  max_instance_request_concurrency = var.max_instance_request_concurrency
  timeout                          = var.timeout

  template_scaling = {
    min_instance_count = var.min_instance_count
    max_instance_count = var.max_instance_count
  }

  ingress    = var.ingress
  vpc_access = var.vpc_access

  create_service_account        = var.create_service_account
  service_account               = var.service_account
  service_account_project_roles = var.service_account_project_roles

  members = var.members

  cloud_run_deletion_protection = var.deletion_protection

  service_labels = var.labels
}

# Lets external identities (e.g. a CI/CD deploy service account) deploy new revisions running
# as the service's own service account, without granting them iam.serviceAccountUser on the
# whole project.
resource "google_service_account_iam_member" "service_account_users" {
  for_each = toset(var.service_account_users)

  # module.cloud_run.service_account_id is {id, email, member} despite its name — it's not
  # itself a usable resource ID.
  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.cloud_run.service_account_id.email}"
  role               = "roles/iam.serviceAccountUser"
  member             = each.value
}
