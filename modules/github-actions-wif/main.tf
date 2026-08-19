resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions"
  description               = "Federates GitHub Actions OIDC tokens for keyless deploys, scoped to specific repos via each provider's attribute_condition."
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "GitHub"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "assertion.repository == \"${var.github_owner}/${var.github_repo}\" && assertion.ref == \"${var.github_ref}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

module "deploy_service_account" {
  source  = "terraform-google-modules/service-accounts/google"
  version = "~> 4.7"

  project_id   = var.project_id
  names        = [var.deploy_account_id]
  display_name = "Deploys ${var.github_owner}/${var.github_repo} via GitHub Actions (WIF, no key file)"
}

locals {
  deploy_sa_roles = {
    run_admin = {
      role      = "roles/run.admin"
      condition = null
    }

    artifactregistry_admin = {
      role      = "roles/artifactregistry.admin"
      condition = null
    }

    compute_network_admin = {
      role      = "roles/compute.networkAdmin"
      condition = null
    }

    compute_security_admin = {
      role      = "roles/compute.securityAdmin"
      condition = null
    }

    vpcaccess_admin = {
      role      = "roles/vpcaccess.admin"
      condition = null
    }

    pubsub_editor = {
      role      = "roles/pubsub.editor"
      condition = null
    }

    # ../db-secrets needs to grant the Secret Manager service agent publish rights on the
    # db-password-rotation topic it creates (modules/secret-manager-secret's
    # google_pubsub_topic_iam_member.secretmanager_can_publish_rotation) — that's
    # pubsub.topics.setIamPolicy, which pubsub_editor above deliberately excludes. Only
    # roles/pubsub.admin includes it. Scoped via a resource.name condition to just this one
    # topic rather than granting admin project-wide: the topic name is deterministic
    # (projects/<id>/topics/db-password-rotation) even before it exists, the same reasoning
    # CLAUDE.md's IAM section uses for Secret Manager. Unlike Secret Manager, Pub/Sub Topic's
    # IAM Conditions support isn't confirmed here (Google's docs didn't clearly confirm or
    # rule it out) — if this condition turns out to be a silent no-op like the Cloud Run/
    # Artifact Registry cases, the fix is to drop the condition and accept pubsub.admin
    # project-wide, not to add a second, different condition guess.
    pubsub_rotation_topic_admin = {
      role = "roles/pubsub.admin"
      condition = {
        title       = "db-password-rotation-topic-only"
        description = "Only the db-password-rotation Pub/Sub topic, for setIamPolicy"
        expression  = "resource.name == \"projects/${var.project_id}/topics/db-password-rotation\""
      }
    }

    service_account_admin = {
      role      = "roles/iam.serviceAccountAdmin"
      condition = null
    }

    project_iam_admin = {
      role      = "roles/resourcemanager.projectIamAdmin"
      condition = null
    }

    secretmanager_admin = {
      role      = "roles/secretmanager.admin"
      condition = null
    }

    monitoring_notification_channel_editor = {
      role      = "roles/monitoring.notificationChannelEditor"
      condition = null
    }

    monitoring_alert_policy_editor = {
      role      = "roles/monitoring.alertPolicyEditor"
      condition = null
    }

    logging_config_writer = {
      role      = "roles/logging.configWriter"
      condition = null
    }

    compute_load_balancer_admin = {
      role      = "roles/compute.loadBalancerAdmin"
      condition = null
    }

    cloudkms_admin = {
      role      = "roles/cloudkms.admin"
      condition = null
    }
  }
}

resource "google_project_iam_member" "deploy_sa_roles" {
  for_each = local.deploy_sa_roles

  project = var.project_id
  role    = each.value.role
  member  = module.deploy_service_account.iam_email

  dynamic "condition" {
    for_each = each.value.condition != null ? [each.value.condition] : []
    content {
      title       = condition.value.title
      description = condition.value.description
      expression  = condition.value.expression
    }
  }
}

resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = module.deploy_service_account.service_account.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.github_repo}"
}

resource "google_storage_bucket_iam_member" "deploy_can_write_state" {
  bucket = var.state_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${module.deploy_service_account.email}"
}
