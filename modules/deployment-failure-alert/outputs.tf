output "topic_id" {
  description = "ID of the Pub/Sub topic deployment-failure alerts are published to."
  value       = google_pubsub_topic.deployment_failures.id
}

output "alert_policy_id" {
  description = "ID of the alert policy watching for failed revisions."
  value       = google_monitoring_alert_policy.revision_failed.id
}
