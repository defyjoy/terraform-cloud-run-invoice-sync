module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id    = var.project_id
  location      = var.region
  repository_id = var.artifact_registry_repo
  description   = "invoice-sync Cloud Run images, built and pushed by the deploy pipeline."
}

module "cloud_run" {
  source = "../../modules/cloud-run"

  project_id   = var.project_id
  service_name = var.service_name
  location     = var.region

  image = "${module.artifact_registry.image_prefix}/invoice-sync:${var.image_tag}"

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
  ]

  # No secrets are used yet — the placeholder Hello World app doesn't read Secret Manager.
  # Add secret IDs here (not a project-wide role) once the real service names ones it needs.
  secret_accessor_secrets = []

  min_instance_count = var.min_instance_count
  max_instance_count = var.max_instance_count

  # Ingress already restricts the path in; this grants the load balancer's anonymous callers
  # invoker access so it can actually reach the service.
  members = ["allUsers"]

  # The deploy service account itself lives in ../github-actions-wif's own state — it has to
  # exist before this stack's pipeline can even authenticate, so it's applied by hand once,
  # ahead of everything here. Its email is deterministic from project_id + deploy_account_id
  # (must match that stack's own deploy_account_id), so there's nothing to copy from its output.
  # This lets it deploy new revisions running as this service's own service account, without
  # granting it iam.serviceAccountUser on the whole project.
  service_account_users = ["serviceAccount:${var.deploy_account_id}@${var.project_id}.iam.gserviceaccount.com"]

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

module "deployment_alert" {
  source = "../../modules/deployment-failure-alert"

  project_id         = var.project_id
  service_name       = module.cloud_run.service_name
  notification_email = var.notification_email
}
