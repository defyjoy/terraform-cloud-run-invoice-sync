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

# Reserved here (instead of letting the lb-http submodule reserve it internally, its default)
# so the IP is known before the self-signed cert below is generated — browsers require a SAN
# matching the address being connected to; without this the cert would carry no SAN at all,
# which Chrome/Firefox reject outright, not just warn on.
resource "google_compute_global_address" "this" {
  project    = var.project_id
  name       = "${var.name}-address"
  ip_version = "IPV4"
  labels     = var.labels
}

# A Google-managed cert (domains != []) needs a domain that already resolves to the LB's IP —
# it can never provision otherwise. Until a real domain exists, ssl = true falls back to a
# self-signed cert so traffic is still encrypted in transit; browsers will show a trust warning
# since nothing signs it, but that's a trust-UX gap, not an encryption gap. Switches to the
# managed cert automatically the moment domains is non-empty.
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

  # Required: browsers validate against SAN, not CN. A cert with no SAN is rejected outright,
  # not merely shown as untrusted — this is what made the previous cert fail in-browser even
  # though the TLS handshake itself succeeded.
  ip_addresses = [google_compute_global_address.this.address]

  validity_period_hours = 8760
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# Pins TLS 1.2+ and drops weak ciphers so the fix doesn't depend on whichever default GCP
# happens to apply. Only needed (and only created) once SSL is actually turned on.
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
      # HIPAA §164.312(b) audit-controls: this LB is the entry point for every request to the
      # service, so its access logs are the only infra-level record of who accessed what.
      log_config = {
        enable      = true
        sample_rate = 1.0
      }
    }
  }
}
