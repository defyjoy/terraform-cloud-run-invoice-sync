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
      machine_type  = "e2-micro"
      min_instances = 2
      max_instances = 3
    },
  ]
}

# Cloud Run's vpc_access.egress is set to ALL_TRAFFIC (see ../invoice-sync), so all of the
# service's internet-bound egress — not just RFC1918 destinations — routes through this VPC.
# NAT is what actually gets that traffic to the internet from a connector subnet with no
# external IPs, and its log_config is the audit trail of what the service talks to externally,
# which PRIVATE_RANGES_ONLY egress (bypassing the VPC entirely for internet destinations) gave
# no visibility into at all.
module "router" {
  source  = "terraform-google-modules/cloud-router/google"
  version = "~> 9.0"

  name       = "${var.name}-router"
  project_id = var.project_id
  region     = var.region
  network    = module.vpc.network_name

  nats = [
    {
      name                               = "${var.name}-nat"
      nat_ip_allocate_option             = "AUTO_ONLY"
      source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

      log_config = {
        enable = true
        filter = "ALL"
      }
    },
  ]
}

module "firewall_rules" {
  source  = "terraform-google-modules/network/google//modules/firewall-rules"
  version = "~> 18.1"

  project_id   = var.project_id
  network_name = module.vpc.network_name

  ingress_rules = [
    {
      name          = "${var.name}-allow-internal"
      description   = "Allow all traffic between ranges inside the VPC"
      priority      = 1000
      source_ranges = [var.connector_cidr]
      allow = [
        { protocol = "tcp" },
        { protocol = "udp" },
        { protocol = "icmp" },
      ]
    },
  ]
}
