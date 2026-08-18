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

# Project-wide, unconditioned — see CLAUDE.md's IAM section: Artifact Registry has no
# resource.name-based IAM Conditions at all, confirmed by a real 403 persisting even when
# resource.name matched exactly what the error itself reported.
resource "google_project_iam_member" "artifactregistry_admin" {
  project = var.project_id
  role    = "roles/artifactregistry.admin"
  member  = module.deploy_service_account.iam_email
}

# Project-wide, unconditioned — a deliberate, discussed exception (see CLAUDE.md's IAM
# section), not a default. This project also hosts the google-cloud-terraform repo's hub/dev
# VPCs, so this grant lets the deploy SA touch that networking too, not just ../network's. Not
# scoped via IAM Conditions because Compute Engine's condition support isn't confirmed for
# networks/subnetworks/routers, and this session already spent a long time discovering that a
# condition which looks correct can silently never match (see the artifactregistry_admin
# comment above) — an untested condition here risks the same failure mode on infra with a much
# larger blast radius if guessed wrong.
resource "google_project_iam_member" "compute_network_admin" {
  project = var.project_id
  role    = "roles/compute.networkAdmin"
  member  = module.deploy_service_account.iam_email
}

# compute.networkAdmin excludes firewall rules by design; ../network's allow_internal rule
# needs this separately.
resource "google_project_iam_member" "compute_security_admin" {
  project = var.project_id
  role    = "roles/compute.securityAdmin"
  member  = module.deploy_service_account.iam_email
}

resource "google_project_iam_member" "vpcaccess_admin" {
  project = var.project_id
  role    = "roles/vpcaccess.admin"
  member  = module.deploy_service_account.iam_email
}

# roles/iam.serviceAccountCreator, not .serviceAccountAdmin: needed for ../invoice-sync's
# create_service_account = true (the Cloud Run runtime SA), and .serviceAccountCreator only
# grants create/get/list, not delete/update/setIamPolicy on every service account in the
# project — narrower than the admin role while still covering the one permission actually
# needed. Project-wide and unconditioned for the same reason as the compute grants above:
# account creation is authorized against the project, not a not-yet-existing account name.
resource "google_project_iam_member" "service_account_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountCreator"
  member  = module.deploy_service_account.iam_email
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
