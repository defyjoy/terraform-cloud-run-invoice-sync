module "cloud_run" {
  source = "../../modules/cloud-run"

  project_id   = var.project_id
  service_name = var.service_name
  location     = var.region

  image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_registry_repo}/invoice-sync:${var.image_tag}"

  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  startup_probe = {
    path = "/readyz"
  }

  env_vars = {
    EXPECTED_DB_PASSWORD = var.expected_db_password
  }

  vpc_access = {
    egress    = var.vpc_egress
    connector = "projects/${var.project_id}/locations/${var.region}/connectors/${var.vpc_connector_name}"
  }

  create_service_account        = true
  service_account_project_roles = var.runtime_service_account_project_roles

  service_account_users = ["serviceAccount:${var.deploy_account_id}@${var.project_id}.iam.gserviceaccount.com"]

  secret_accessor_secrets = [var.db_password_secret_id]

  env_secret_vars = {
    DB_PASSWORD = {
      secret  = var.db_password_secret_id
      version = "latest"
    }
  }

  min_instance_count = var.min_instance_count
  max_instance_count = var.max_instance_count

  members = ["allUsers"]

  deletion_protection = var.deletion_protection

  labels = {
    service = "invoice-sync"
  }
}

module "lb" {
  source = "../../modules/serverless-lb"

  project_id = var.project_id
  name       = var.lb_name
  region     = var.region

  cloud_run_service_name = module.cloud_run.service_name

  ssl     = var.lb_ssl
  domains = var.lb_domains
}

module "deployment_alert" {
  source = "../../modules/deployment-failure-alert"

  project_id         = var.project_id
  service_name       = var.service_name
  notification_email = var.notification_email
}
