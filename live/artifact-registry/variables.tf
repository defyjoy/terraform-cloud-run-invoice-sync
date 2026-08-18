variable "project_id" {
  description = "ID of the project the repo is created in."
  type        = string
}

variable "region" {
  description = "Region the repo is created in. Must match ../invoice-sync's own region — that stack references this repo by name, not by output."
  type        = string
}

variable "repository_id" {
  description = "ID of the Artifact Registry repo. Must match ../invoice-sync's own artifact_registry_repo."
  type        = string
}
