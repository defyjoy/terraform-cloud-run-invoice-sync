variable "project_id" {
  description = "ID of the project everything is created in."
  type        = string
}

variable "region" {
  description = "Region for Cloud Run, Artifact Registry and the google provider."
  type        = string
}

variable "service_name" {
  description = "Name of the Cloud Run service."
  type        = string
}

variable "artifact_registry_repo" {
  description = "ID of the Artifact Registry Docker repo images are pushed to. Must match ../artifact-registry's own repository_id — that stack creates it, this one only references it by name."
  type        = string
}

variable "vpc_connector_name" {
  description = "Name of the Serverless VPC Access connector Cloud Run attaches to. Must match ../network's own name-derived connector name (\"<name>-connector\") — that stack creates it, this one only references it by name."
  type        = string
}

variable "vpc_egress" {
  description = "Which of the service's outbound traffic is routed through the connector. PRIVATE_RANGES_ONLY sends only RFC1918 destinations through the VPC; ALL_TRAFFIC sends everything, including internet-bound traffic, through it."
  type        = string

  validation {
    condition     = contains(["ALL_TRAFFIC", "PRIVATE_RANGES_ONLY"], var.vpc_egress)
    error_message = "vpc_egress must be ALL_TRAFFIC or PRIVATE_RANGES_ONLY."
  }
}

variable "lb_name" {
  description = "Base name for the public load balancer's components."
  type        = string
}

variable "image_tag" {
  description = "Tag of the invoice-sync image to deploy, e.g. a git SHA. No default — the pipeline always passes this explicitly."
  type        = string
}

variable "notification_email" {
  description = "Address notified when a Cloud Run revision fails to become ready."
  type        = string
}

variable "min_instance_count" {
  description = "Minimum number of instances kept running. 0 allows scale-to-zero."
  type        = number
}

variable "max_instance_count" {
  description = "Maximum number of instances the service can scale out to."
  type        = number
}

variable "deletion_protection" {
  description = "Block terraform destroy on the service."
  type        = bool
}

variable "deploy_account_id" {
  description = "Account ID (local part of the email) of the GitHub Actions deploy service account created by ../github-actions-wif. Must match that stack's own deploy_account_id. Granted roles/iam.serviceAccountUser on the runtime SA so the pipeline can deploy revisions running as it, via ../github-actions-wif's project-wide roles/iam.serviceAccountAdmin grant."
  type        = string
}

variable "runtime_service_account_project_roles" {
  description = "Project-level IAM roles granted to the Cloud Run runtime SA, e.g. [\"roles/logging.logWriter\"]. Granted directly by this stack via ../github-actions-wif's project-wide roles/resourcemanager.projectIamAdmin grant."
  type        = list(string)
}

variable "db_password_secret_id" {
  description = "ID of the db-password secret, created by ../db-secrets (not by this stack). The runtime SA is granted roles/secretmanager.secretAccessor on it, scoped to just this secret, via ../db-secrets' own grant of roles/secretmanager.admin (scoped to just this secret) to the deploy SA. Must match ../db-secrets' own db_password_secret_id."
  type        = string
}
