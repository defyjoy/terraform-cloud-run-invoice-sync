terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6, < 8"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6, < 8"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 2.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}
