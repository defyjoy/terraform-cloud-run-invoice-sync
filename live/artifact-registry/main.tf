module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id    = var.project_id
  location      = var.region
  repository_id = var.repository_id
  description   = "invoice-sync Cloud Run images, built and pushed by the deploy pipeline."
}
