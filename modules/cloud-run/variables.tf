variable "project_id" {
  description = "ID of the project the service is created in."
  type        = string
}

variable "service_name" {
  description = "Name of the Cloud Run service."
  type        = string
}

variable "location" {
  description = "Cloud Run service deployment location, e.g. us-central1."
  type        = string
}

variable "image" {
  description = "Container image to deploy, e.g. us-docker.pkg.dev/project/repo/image:tag."
  type        = string
}

variable "container_name" {
  description = "Name of the container within the revision. Null lets Cloud Run generate one."
  type        = string
  default     = null
}

variable "container_command" {
  description = "Overrides the container ENTRYPOINT. Empty uses the image's own entrypoint."
  type        = list(string)
  default     = []
}

variable "container_args" {
  description = "Arguments passed to the ENTRYPOINT."
  type        = list(string)
  default     = []
}

variable "port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080
}

variable "env_vars" {
  description = "Cleartext environment variables."
  type        = map(string)
  default     = {}
}

variable "env_secret_vars" {
  description = "Environment variables sourced from Secret Manager, keyed by env var name. Each value names the secret and version to mount."
  type = map(object({
    secret  = string
    version = string
  }))
  default = {}
}

variable "cpu" {
  description = "CPU limit for the container, e.g. \"1\" or \"2\"."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory limit for the container, e.g. 512Mi or 1Gi."
  type        = string
  default     = "512Mi"
}

variable "cpu_idle" {
  description = <<-EOT
    Throttle CPU to zero outside of request processing. True (the default) lets the instance
    scale to zero and only bills for CPU during requests. Set false only for workloads that do
    background work between requests (queue consumers, background threads) — CPU is then
    allocated for the instance's full lifetime and billed accordingly.
  EOT
  type        = bool
  default     = true
}

variable "min_instance_count" {
  description = "Minimum number of instances kept running. 0 allows scale-to-zero."
  type        = number
  default     = 0
}

variable "max_instance_count" {
  description = "Maximum number of instances the service can scale out to."
  type        = number
  default     = 2
}

variable "max_instance_request_concurrency" {
  description = "Maximum concurrent requests per instance. Null uses the Cloud Run default."
  type        = number
  default     = null
}

variable "timeout" {
  description = "Max time an instance has to respond to a request, e.g. \"300s\"."
  type        = string
  default     = "300s"
}

variable "ingress" {
  description = "Restricts which traffic can reach the service."
  type        = string
  default     = "INGRESS_TRAFFIC_ALL"

  validation {
    condition = contains([
      "INGRESS_TRAFFIC_ALL",
      "INGRESS_TRAFFIC_INTERNAL_ONLY",
      "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER",
    ], var.ingress)
    error_message = "ingress must be INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY or INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  }
}

variable "vpc_access" {
  description = <<-EOT
    Send the service's egress traffic through a VPC, e.g. to reach a private GKE cluster or
    Cloud SQL instance over its internal address instead of the public internet. Set either
    connector (a Serverless VPC Access connector name) or network_interfaces (direct VPC
    egress). Null leaves the service on its default, internet-only egress path.
  EOT
  type = object({
    connector = optional(string)
    egress    = optional(string)
    network_interfaces = optional(object({
      network    = optional(string)
      subnetwork = optional(string)
      tags       = optional(list(string))
    }))
  })
  default = null
}

variable "create_service_account" {
  description = "Create a dedicated service account for the service. False requires service_account to be set."
  type        = bool
  default     = true
}

variable "service_account" {
  description = "Email of an existing service account for the revision to run as. Null with create_service_account true generates one."
  type        = string
  default     = null
}

variable "service_account_project_roles" {
  description = "Project-level IAM roles granted to the generated service account. Only used when create_service_account is true and service_account is null."
  type        = list(string)
  default     = []
}

variable "members" {
  description = "Members granted roles/run.invoker on the service, e.g. [\"serviceAccount:...\"]. Empty leaves the service reachable only to principals granted invoker access elsewhere. Use [\"allUsers\"] for public access."
  type        = list(string)
  default     = []
}

variable "service_account_users" {
  description = "Members granted roles/iam.serviceAccountUser on the service's own service account (created or existing), e.g. a CI/CD deploy service account that needs to deploy new revisions running as it. Fully qualified members, e.g. [\"serviceAccount:...\"]."
  type        = list(string)
  default     = []
}

variable "deletion_protection" {
  description = "Block terraform destroy on the service."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels applied to the service."
  type        = map(string)
  default     = {}
}
