variable "project_id" {
  description = "ID of the project the service, topic and alert policy live in."
  type        = string
}

variable "service_name" {
  description = "Name of the Cloud Run service to watch for failed revisions."
  type        = string
}

variable "notification_email" {
  description = "Address the deployment-failure alert emails."
  type        = string
}

variable "topic_name" {
  description = "Name of the Pub/Sub topic deployment-failure alerts are published to."
  type        = string
  default     = "deployment-failures"
}
