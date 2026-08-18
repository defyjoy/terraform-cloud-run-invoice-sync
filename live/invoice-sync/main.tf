module "cloud_run" {
  source = "../../modules/cloud-run"

  project_id   = var.project_id
  service_name = var.service_name
  location     = var.region

  # The repo itself lives in ../artifact-registry's own state — it has to exist before the
  # pipeline's docker push, so it's applied ahead of this stack rather than created here.
  image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_registry_repo}/invoice-sync:${var.image_tag}"

  # Only traffic that has passed through the load balancer (or is already inside the VPC) is
  # let in — *.run.app direct access is refused, so module.lb is the only public entry point.
  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  # ../network's own state creates the connector; referenced by its deterministic name here
  # rather than a remote-state read, same pattern as artifact_registry_repo.
  vpc_access = {
    egress    = var.vpc_egress
    connector = "projects/${var.project_id}/locations/${var.region}/connectors/${var.vpc_connector_name}"
  }

  # ../invoice-sync-runtime-sa's own state creates this account and grants it its project
  # roles plus the deploy SA's actAs — the pipeline's own deploy SA can't be scoped to do
  # either safely (see that stack's main.tf and CLAUDE.md's IAM section), so this stack only
  # references it by its deterministic email, same pattern as the VPC connector.
  create_service_account = false
  service_account        = "${var.runtime_service_account_id}@${var.project_id}.iam.gserviceaccount.com"

  # No secrets are used yet — the placeholder Hello World app doesn't read Secret Manager.
  # Add secret IDs here (not a project-wide role) once the real service names ones it needs.
  secret_accessor_secrets = []

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

module "deployment_alert" {
  source = "../../modules/deployment-failure-alert"

  project_id         = var.project_id
  service_name       = module.cloud_run.service_name
  notification_email = var.notification_email
}
