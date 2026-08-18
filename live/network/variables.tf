variable "project_id" {
  description = "ID of the project the network is created in."
  type        = string
}

variable "region" {
  description = "Region the connector subnet and connector are created in. Must match ../invoice-sync's own region."
  type        = string
}

variable "name" {
  description = "Base name for the network and every resource derived from it. Must match ../invoice-sync's own vpc_connector_name (the connector's name is derived from this)."
  type        = string
}

variable "connector_cidr" {
  description = "CIDR range for the Serverless VPC Access connector's dedicated subnet. Must be exactly /28."
  type        = string
}
