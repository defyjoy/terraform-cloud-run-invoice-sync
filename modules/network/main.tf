module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 18.1"

  project_id   = var.project_id
  network_name = var.name
  routing_mode = "REGIONAL"

  subnets = [
    {
      subnet_name           = "${var.name}-connector-${var.region}"
      subnet_ip             = var.connector_cidr
      subnet_region         = var.region
      subnet_private_access = "true"
      subnet_flow_logs      = "false"
      description           = "Dedicated subnet for the Serverless VPC Access connector"
    },
  ]
}

# Serverless VPC Access is still beta-only in the provider, hence the submodule name and the
# google-beta provider requirement (see versions.tf).
module "serverless_connector" {
  source  = "terraform-google-modules/network/google//modules/vpc-serverless-connector-beta"
  version = "~> 18.1"

  project_id = var.project_id

  vpc_connectors = [
    {
      name          = "${var.name}-connector"
      region        = var.region
      subnet_name   = module.vpc.subnets_names[0]
      machine_type  = var.connector_machine_type
      min_instances = var.connector_min_instances
      max_instances = var.connector_max_instances
    },
  ]
}

resource "google_compute_firewall" "allow_internal" {
  project = var.project_id
  name    = "${var.name}-allow-internal"
  network = module.vpc.network_name

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.connector_cidr]
}
