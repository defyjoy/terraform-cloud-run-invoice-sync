resource "google_pubsub_topic" "deployment_failures" {
  project = var.project_id
  name    = var.topic_name
}

resource "google_monitoring_notification_channel" "pubsub" {
  project      = var.project_id
  type         = "pubsub"
  display_name = "${var.service_name} deployment failures (Pub/Sub)"

  labels = {
    topic = google_pubsub_topic.deployment_failures.id
  }
}

resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  type         = "email"
  display_name = "${var.service_name} deployment failures (email)"

  labels = {
    email_address = var.notification_email
  }
}

resource "google_monitoring_alert_policy" "revision_failed" {
  project      = var.project_id
  display_name = "${var.service_name}: revision failed to become ready"
  combiner     = "OR"

  conditions {
    display_name = "Revision failed (run.googleapis.com/varlog/system error)"

    condition_matched_log {
      filter = <<-EOT
        resource.type="cloud_run_revision"
        resource.labels.service_name="${var.service_name}"
        logName="projects/${var.project_id}/logs/run.googleapis.com%2Fvarlog%2Fsystem"
        severity=ERROR
      EOT
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.pubsub.id,
    google_monitoring_notification_channel.email.id,
  ]

  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
  }
}
