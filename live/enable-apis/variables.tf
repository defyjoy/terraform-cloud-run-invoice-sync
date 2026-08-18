variable "project_id" {
  description = "ID of the project to enable the service APIs on."
  type        = string
}

variable "services" {
  description = "Service APIs to enable on the project, covering every resource type used across this repo's stacks."
  type        = set(string)
}
