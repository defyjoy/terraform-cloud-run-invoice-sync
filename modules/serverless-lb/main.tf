# The lb-http module wires a backend service to whatever groups it's given but doesn't create
# NEGs itself, so the serverless NEG pointing at the Cloud Run service is created here.
resource "google_compute_region_network_endpoint_group" "this" {
  project               = var.project_id
  name                  = "${var.name}-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = var.cloud_run_service_name
  }
}

module "lb" {
  source  = "GoogleCloudPlatform/lb-http/google//modules/serverless_negs"
  version = "~> 14.0"

  name    = var.name
  project = var.project_id

  ssl                             = var.ssl
  managed_ssl_certificate_domains = var.domains
  https_redirect                  = var.ssl

  labels = var.labels

  backends = {
    default = {
      description = null
      enable_cdn  = var.enable_cdn

      groups = [
        {
          group = google_compute_region_network_endpoint_group.this.id
        },
      ]

      iap_config = {
        enable = false
      }
      log_config = {
        enable = false
      }
    }
  }
}
