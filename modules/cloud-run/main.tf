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

      startup_probe = var.startup_probe == null ? null : {
        failure_threshold     = var.startup_probe.failure_threshold
        initial_delay_seconds = var.startup_probe.initial_delay_seconds
        timeout_seconds       = var.startup_probe.timeout_seconds
        period_seconds        = var.startup_probe.period_seconds
        http_get = {
          path = var.startup_probe.path
          port = tostring(var.port)
        }
      }

      liveness_probe = var.liveness_probe == null ? null : {
        failure_threshold     = var.liveness_probe.failure_threshold
        initial_delay_seconds = var.liveness_probe.initial_delay_seconds
        timeout_seconds       = var.liveness_probe.timeout_seconds
        period_seconds        = var.liveness_probe.period_seconds
        http_get = {
          path = var.liveness_probe.path
          port = tostring(var.port)
        }
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

resource "google_service_account_iam_member" "service_account_users" {
  for_each = toset(var.service_account_users)

  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.cloud_run.service_account_id.email}"
  role               = "roles/iam.serviceAccountUser"
  member             = each.value
}

resource "google_secret_manager_secret_iam_member" "runtime_secret_access" {
  for_each = toset(var.secret_accessor_secrets)

  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = module.cloud_run.service_account_id.member
}
