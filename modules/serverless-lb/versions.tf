terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6, < 8"
    }
    # Required by GoogleCloudPlatform/lb-http/google//modules/serverless_negs.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6, < 8"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 2.1"
    }
    # Generates the self-signed fallback cert used when ssl = true but no domain is configured
    # yet for a Google-managed cert.
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}
