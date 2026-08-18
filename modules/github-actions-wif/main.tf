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

  # Narrows token exchange to this one repo AND this one ref — without the ref check, any
  # branch or tag in the repo (not just the one deploy.yml actually deploys from) could mint a
  # token that impersonates the deploy service account below.
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

resource "google_project_iam_member" "run_admin_scoped" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = module.deploy_service_account.iam_email

  # Matches the parent location too, not just the service name — see CLAUDE.md's IAM section on
  # why create calls need that.
  condition {
    title       = "${var.cloud_run_service_name}-only"
    description = "Restricts roles/run.admin to the ${var.cloud_run_service_name} Cloud Run service only."
    expression  = <<-EOT
      resource.type == "run.googleapis.com/Service" && (
        resource.name == "projects/${var.project_id}/locations/${var.region}" ||
        resource.name == "projects/${var.project_id}/locations/${var.region}/services/${var.cloud_run_service_name}"
      )
    EOT
  }
}

resource "google_project_iam_member" "artifactregistry_admin_scoped" {
  project = var.project_id
  role    = "roles/artifactregistry.admin"
  member  = module.deploy_service_account.iam_email

  # roles/artifactregistry.admin, not .repoAdmin: .repoAdmin has no repositories.create/.delete
  # at all, only content-level permissions on a repo that already exists — see CLAUDE.md's IAM
  # section. Also matches the parent location, not just the repo name, since create calls check
  # the parent.
  condition {
    title       = "${var.artifact_registry_repo}-only"
    description = "Restricts roles/artifactregistry.admin to the ${var.artifact_registry_repo} Artifact Registry repo only."
    expression  = <<-EOT
      resource.type == "artifactregistry.googleapis.com/Repository" && (
        resource.name == "projects/${var.project_id}/locations/${var.region}" ||
        resource.name == "projects/${var.project_id}/locations/${var.region}/repositories/${var.artifact_registry_repo}"
      )
    EOT
  }
}

# Lets the pool's tokens, scoped to this repo, impersonate the deploy service account —
# equivalent to a key file but without one ever existing.
#
# A plain resource, not the service_accounts_iam module: that module's for_each is built from
# a set that includes this principalSet string, and google_iam_workload_identity_pool.github.name
# (it embeds the project *number*, resolved by the API) is unknown until the pool is actually
# created — for_each can't plan over a set with unknown members. A single resource has no such
# restriction; an unknown attribute value on one resource is fine, it just applies in dependency
# order.
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = module.deploy_service_account.service_account.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.github_repo}"
}

# The pipeline runs terraform init/apply itself, so its deploy service account needs write
# access to the state bucket.
resource "google_storage_bucket_iam_member" "deploy_can_write_state" {
  bucket = var.state_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${module.deploy_service_account.email}"
}
