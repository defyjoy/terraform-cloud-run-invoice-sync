resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = var.name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Serverless VPC Access connectors require a dedicated /28 subnet that nothing else uses.
resource "google_compute_subnetwork" "connector" {
  project                  = var.project_id
  name                     = "${var.name}-connector-${var.region}"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.connector_cidr
  private_ip_google_access = true
}

resource "google_vpc_access_connector" "this" {
  project = var.project_id
  name    = "${var.name}-connector"
  region  = var.region

  subnet {
    name = google_compute_subnetwork.connector.name
  }

  machine_type  = var.connector_machine_type
  min_instances = var.connector_min_instances
  max_instances = var.connector_max_instances
}

resource "google_compute_firewall" "allow_internal" {
  project = var.project_id
  name    = "${var.name}-allow-internal"
  network = google_compute_network.this.id

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
