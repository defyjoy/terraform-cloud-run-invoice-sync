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

  # Only traffic that has passed through the load balancer (or is already inside the VPC) is
  # let in — *.run.app direct access is refused, so module.lb is the only public entry point.
  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  vpc_access = {
    egress = var.vpc_egress
    network_interfaces = {
      network    = var.network_name
      subnetwork = var.subnetwork_name
    }
  }

  create_service_account = true
  service_account_project_roles = [
    "roles/logging.logWriter",
    "roles/cloudtrace.agent",
    "roles/secretmanager.secretAccessor",
  ]

  min_instance_count = var.min_instance_count
  max_instance_count = var.max_instance_count

  # Ingress already restricts the path in; this grants the load balancer's anonymous callers
  # invoker access so it can actually reach the service.
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
}

# The deploy service account itself lives in ../github-actions-wif's own state — it has to
# exist before this stack's pipeline can even authenticate, so it's applied by hand once,
# ahead of everything here. var.deploy_service_account_email comes from that stack's output.

# Lets the deploy service account act as the Cloud Run runtime service account when deploying
# new revisions, without granting it broader iam.serviceAccountUser on the whole project.
resource "google_service_account_iam_member" "deploy_can_act_as_runtime" {
  service_account_id = module.cloud_run.service_account_id
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.deploy_service_account_email}"
}

module "deployment_alert" {
  source = "../../modules/deployment-failure-alert"

  project_id         = var.project_id
  service_name       = module.cloud_run.service_name
  notification_email = var.notification_email
}
