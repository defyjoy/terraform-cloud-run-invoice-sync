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
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
