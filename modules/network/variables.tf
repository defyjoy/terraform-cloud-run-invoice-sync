variable "project_id" {
  description = "ID of the project the network is created in."
  type        = string
}

variable "region" {
  description = "Region the connector subnet and connector are created in."
  type        = string
}

variable "name" {
  description = "Base name for the network and every resource derived from it, e.g. \"invoice-sync\"."
  type        = string
}

variable "connector_cidr" {
  description = "CIDR range for the Serverless VPC Access connector's dedicated subnet. Must be exactly /28 and unused by anything else in the network."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.connector_cidr)) && split("/", var.connector_cidr)[1] == "28"
    error_message = "connector_cidr must be a valid /28 CIDR range."
  }
}

variable "connector_machine_type" {
  description = "Machine type for the connector's instances."
  type        = string
  default     = "e2-micro"
}

variable "connector_min_instances" {
  description = "Minimum number of connector instances."
  type        = number
  default     = 2
}

variable "connector_max_instances" {
  description = "Maximum number of connector instances."
  type        = number
  default     = 3
}
