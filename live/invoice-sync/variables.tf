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
  description = "ID of the Artifact Registry Docker repo images are pushed to."
  type        = string
}

variable "network_name" {
  description = "Name of the VPC Cloud Run's Direct VPC egress attaches to. Set to the hub VPC created by the google-cloud-terraform repo's live/hub/vpc unless that stack isn't reused."
  type        = string
}

variable "subnetwork_name" {
  description = "Name of network_name's Cloud Run Direct VPC egress subnet, one of live/hub/vpc's cloud_run_subnet_names output entries in the google-cloud-terraform repo."
  type        = string
}

variable "vpc_egress" {
  description = "Which of the service's outbound traffic is routed through network_interfaces. PRIVATE_RANGES_ONLY sends only RFC1918 destinations through the VPC; ALL_TRAFFIC sends everything, including internet-bound traffic, through it (and Cloud NAT from there)."
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

variable "deploy_service_account_email" {
  description = "Email of the GitHub Actions deploy service account, from ../github-actions-wif's service_account_email output. That stack must be applied first."
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
