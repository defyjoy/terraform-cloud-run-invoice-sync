variable "project_id" {
  description = "ID of the project the services are enabled on."
  type        = string
}

variable "services" {
  description = "Service APIs to enable on the project."
  type        = set(string)
}

variable "disable_on_destroy" {
  description = "Disable the services when the resources are destroyed. Leave false so a destroy does not break other workloads still using the API."
  type        = bool
  default     = false
}

variable "disable_dependent_services" {
  description = "Also disable services that depend on the ones listed here when they are disabled."
  type        = bool
  default     = false
}
