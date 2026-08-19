variable "project_id" {
  description = "ID of the project the load balancer and NEG are created in."
  type        = string
}

variable "name" {
  description = "Base name for the load balancer's forwarding rule, proxy, url map and backend service."
  type        = string
}

variable "region" {
  description = "Region of the Cloud Run service the serverless NEG points at."
  type        = string
}

variable "cloud_run_service_name" {
  description = "Name of the Cloud Run service to front. Must be in project_id and region."
  type        = string
}

variable "ssl" {
  description = "Terminate HTTPS at the load balancer and redirect HTTP to HTTPS. False serves plain HTTP only, unencrypted. With domains set, uses a Google-managed certificate for those domains; with domains empty, falls back to a self-signed certificate (still encrypts transit, but browsers show a trust warning since nothing signs it) until a real domain is available."
  type        = bool
  default     = false
}

variable "domains" {
  description = "Domains for the Google-managed SSL certificate. Each must already resolve (or be pointed, once the LB's IP is known) to this load balancer's IP — Google's managed-cert provisioning polls DNS and never completes otherwise. Ignored when ssl is false. Empty while ssl is true uses a self-signed cert instead (see ssl's description)."
  type        = list(string)
  default     = []
}

variable "enable_cdn" {
  description = "Cache eligible responses at Cloud CDN in front of the backend."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels applied to the load balancer's forwarding rule."
  type        = map(string)
  default     = {}
}
