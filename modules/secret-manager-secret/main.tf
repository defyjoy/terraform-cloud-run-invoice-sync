resource "google_project_service_identity" "secretmanager" {
  provider = google-beta

  project = var.project_id
  service = "secretmanager.googleapis.com"
}

resource "google_kms_key_ring" "this" {
  project  = var.project_id
  name     = "${var.secret_id}-keyring"
  location = "global"
}

resource "google_kms_crypto_key" "this" {
  name            = "${var.secret_id}-key"
  key_ring        = google_kms_key_ring.this.id
  rotation_period = var.kms_key_rotation_period

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key_iam_member" "secretmanager_can_use_key" {
  crypto_key_id = google_kms_crypto_key.this.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.secretmanager.email}"
}

resource "google_pubsub_topic" "rotation" {
  count = var.rotation_period != null ? 1 : 0

  project = var.project_id
  name    = "${var.secret_id}-rotation"
}

resource "google_pubsub_topic_iam_member" "secretmanager_can_publish_rotation" {
  count = var.rotation_period != null ? 1 : 0

  project = var.project_id
  topic   = google_pubsub_topic.rotation[0].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_project_service_identity.secretmanager.email}"
}

resource "time_sleep" "pubsub_iam_propagation" {
  count = var.rotation_period != null ? 1 : 0

  depends_on      = [google_pubsub_topic_iam_member.secretmanager_can_publish_rotation]
  create_duration = "60s"
}

resource "google_secret_manager_secret" "this" {
  project   = var.project_id
  secret_id = var.secret_id

  replication {
    auto {
      customer_managed_encryption {
        kms_key_name = google_kms_crypto_key.this.id
      }
    }
  }

  dynamic "topics" {
    for_each = var.rotation_period != null ? [1] : []
    content {
      name = google_pubsub_topic.rotation[0].id
    }
  }

  dynamic "rotation" {
    for_each = var.rotation_period != null ? [1] : []
    content {
      rotation_period    = var.rotation_period
      next_rotation_time = timeadd(plantimestamp(), var.rotation_period)
    }
  }

  labels = var.labels

  lifecycle {
    ignore_changes = [rotation]
  }

  depends_on = [
    google_kms_crypto_key_iam_member.secretmanager_can_use_key,
    time_sleep.pubsub_iam_propagation,
  ]
}

resource "google_secret_manager_secret_iam_member" "admin_members" {
  for_each = toset(var.admin_members)

  project   = var.project_id
  secret_id = google_secret_manager_secret.this.secret_id
  role      = "roles/secretmanager.admin"
  member    = each.value
}
