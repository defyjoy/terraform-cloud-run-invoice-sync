variable "project_id" {
  description = "ID of the project everything is created in."
  type        = string
  default     = "yeti-504903"
}

variable "region" {
  description = "Region for Cloud Run, Artifact Registry and the google provider."
  type        = string
  default     = "us-central1"
}

variable "service_name" {
  description = "Name of the Cloud Run service."
  type        = string
  default     = "invoice-sync"
}

variable "artifact_registry_repo" {
  description = "ID of the Artifact Registry Docker repo images are pushed to."
  type        = string
  default     = "invoice-sync"
}

variable "network_name" {
  description = "Name of the VPC Cloud Run's Direct VPC egress attaches to. Defaults to the hub VPC created by the google-cloud-terraform repo's live/hub/vpc; point elsewhere if that stack isn't reused."
  type        = string
  default     = "yeti-hub-vpc"
}

variable "subnetwork_name" {
  description = "Name of network_name's Cloud Run Direct VPC egress subnet, one of live/hub/vpc's cloud_run_subnet_names output entries in the google-cloud-terraform repo."
  type        = string
  default     = "yeti-hub-run-us-central1-0"
}

variable "vpc_egress" {
  description = "Which of the service's outbound traffic is routed through network_interfaces. PRIVATE_RANGES_ONLY sends only RFC1918 destinations through the VPC; ALL_TRAFFIC sends everything, including internet-bound traffic, through it (and Cloud NAT from there)."
  type        = string
  default     = "PRIVATE_RANGES_ONLY"

  validation {
    condition     = contains(["ALL_TRAFFIC", "PRIVATE_RANGES_ONLY"], var.vpc_egress)
    error_message = "vpc_egress must be ALL_TRAFFIC or PRIVATE_RANGES_ONLY."
  }
}

variable "lb_name" {
  description = "Base name for the public load balancer's components."
  type        = string
  default     = "invoice-sync-lb"
}

variable "image_tag" {
  description = "Tag of the invoice-sync image to deploy, e.g. a git SHA. No default — the pipeline always passes this explicitly."
  type        = string
}

variable "github_owner" {
  description = "GitHub org or user that owns the repo allowed to deploy via Workload Identity Federation."
  type        = string
}

variable "github_repo" {
  description = "GitHub repo (without owner) allowed to deploy via Workload Identity Federation."
  type        = string
}

variable "notification_email" {
  description = "Address notified when a Cloud Run revision fails to become ready."
  type        = string
}

variable "state_bucket" {
  description = "GCS bucket holding this stack's Terraform state. Must match Taskfile's STATE_BUCKET — the deploy service account is granted write access to it so the pipeline can run terraform apply."
  type        = string
  default     = "yeti-terraform-state-bucket"
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

variable "deletion_protection" {
  description = "Block terraform destroy on the service."
  type        = bool
  default     = true
}
