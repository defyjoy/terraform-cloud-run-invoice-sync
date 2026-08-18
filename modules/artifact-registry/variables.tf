variable "project_id" {
  description = "ID of the project the repo is created in."
  type        = string
}

variable "location" {
  description = "Region the repo is created in, e.g. us-central1."
  type        = string
}

variable "repository_id" {
  description = "ID of the Artifact Registry repo."
  type        = string
}

variable "format" {
  description = "Artifact format the repo stores."
  type        = string
  default     = "DOCKER"
}

variable "description" {
  description = "Human-readable description of the repo."
  type        = string
  default     = null
}
