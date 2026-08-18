terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6, < 8"
    }
    # Required by GoogleCloudPlatform/cloud-run/google//modules/v2, unused here since this
    # module grants no beta-only resources itself.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6, < 8"
    }
  }
}
