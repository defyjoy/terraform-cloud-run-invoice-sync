terraform {
  required_version = ">= 1.5"

  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6, < 8"
    }
  }
}

provider "google" {
  project = var.project_id
}
