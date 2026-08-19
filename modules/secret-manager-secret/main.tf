# Secret Manager encrypts/decrypts secret payloads via its own service identity, not the
# caller's credentials — a principal with roles/secretmanager.secretAccessor (e.g. Cloud Run's
# runtime SA, granted elsewhere) never needs any direct Cloud KMS permission of its own for this
# to work. See https://cloud.google.com/secret-manager/docs/cmek.
resource "google_project_service_identity" "secretmanager" {
  provider = google-beta

  project = var.project_id
  service = "secretmanager.googleapis.com"
}

# Automatic replication's CMEK support requires the key to be in the global multi-region
# specifically — Secret Manager rejects any other location for this replication mode.
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
    # Destroying this key (or letting a careless replace happen) would permanently strand every
    # secret version encrypted under it — KMS key rings themselves can never be deleted, but the
    # key inside one can, and doing so is irreversible in a way applying Terraform elsewhere
    # can't be.
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key_iam_member" "secretmanager_can_use_key" {
  crypto_key_id = google_kms_crypto_key.this.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.secretmanager.email}"
}

# Rotation notification target — Secret Manager has no way to generate a new secret value
# itself, so "rotation" here means a scheduled Pub/Sub reminder, not an automatic value change.
resource "google_pubsub_topic" "rotation" {
  count = var.rotation_period != null ? 1 : 0

  project = var.project_id
  name    = "${var.secret_id}-rotation"
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
      rotation_period = var.rotation_period
      # Only used to seed the very first reminder — see the ignore_changes below for why.
      next_rotation_time = timeadd(plantimestamp(), var.rotation_period)
    }
  }

  labels = var.labels

  # Secret Manager itself advances next_rotation_time by rotation_period every time a reminder
  # fires; without this, every subsequent plan would fight that and try to reset it back to
  # "now + rotation_period" as computed at apply time.
  lifecycle {
    ignore_changes = [rotation]
  }

  depends_on = [google_kms_crypto_key_iam_member.secretmanager_can_use_key]
}

resource "google_secret_manager_secret_iam_member" "admin_members" {
  for_each = toset(var.admin_members)

  project   = var.project_id
  secret_id = google_secret_manager_secret.this.secret_id
  role      = "roles/secretmanager.admin"
  member    = each.value
}
