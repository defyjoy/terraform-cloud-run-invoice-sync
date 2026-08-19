resource "google_compute_region_network_endpoint_group" "this" {
  project               = var.project_id
  name                  = "${var.name}-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = var.cloud_run_service_name
  }
}

resource "google_compute_global_address" "this" {
  project    = var.project_id
  name       = "${var.name}-address"
  ip_version = "IPV4"
  labels     = var.labels
}

locals {
  use_self_signed_cert = var.ssl && length(var.domains) == 0
}

resource "tls_private_key" "self_signed" {
  count = local.use_self_signed_cert ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "self_signed" {
  count = local.use_self_signed_cert ? 1 : 0

  private_key_pem = tls_private_key.self_signed[0].private_key_pem

  subject {
    common_name  = "${var.name}.invalid"
    organization = "Self-signed placeholder — no domain configured yet"
  }

  ip_addresses = [google_compute_global_address.this.address]

  validity_period_hours = 8760
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "google_compute_ssl_policy" "this" {
  count = var.ssl ? 1 : 0

  name            = "${var.name}-ssl-policy"
  profile         = "RESTRICTED"
  min_tls_version = "TLS_1_2"
}

module "lb" {
  source  = "GoogleCloudPlatform/lb-http/google//modules/serverless_negs"
  version = "~> 14.0"

  name    = var.name
  project = var.project_id

  create_address = false
  address        = google_compute_global_address.this.address

  ssl                             = var.ssl
  managed_ssl_certificate_domains = var.domains
  create_ssl_certificate          = local.use_self_signed_cert
  private_key                     = local.use_self_signed_cert ? tls_private_key.self_signed[0].private_key_pem : null
  certificate                     = local.use_self_signed_cert ? tls_self_signed_cert.self_signed[0].cert_pem : null
  ssl_policy                      = var.ssl ? google_compute_ssl_policy.this[0].self_link : null
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
        enable      = true
        sample_rate = 1.0
      }
    }
  }
}
