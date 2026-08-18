module "network" {
  source = "../../modules/network"

  project_id     = var.project_id
  region         = var.region
  name           = var.name
  connector_cidr = var.connector_cidr
}
