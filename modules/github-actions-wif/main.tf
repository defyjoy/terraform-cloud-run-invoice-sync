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

locals {
  # Every project-level role the deploy SA holds, keyed by the same names the old individual
  # resources used (kept via the moved blocks below, so this refactor doesn't churn real IAM
  # bindings). condition = null means unconditioned/project-wide; see CLAUDE.md's IAM section
  # for why each unconditioned entry couldn't be scoped further.
  deploy_sa_roles = {
    run_admin_scoped = {
      role = "roles/run.admin"
      # Matches the parent location too, not just the service name — see CLAUDE.md's IAM
      # section on why create calls need that.
      condition = {
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

    # Artifact Registry has no resource.name-based IAM Conditions at all, confirmed by a real
    # 403 persisting even when resource.name matched exactly what the error itself reported.
    artifactregistry_admin = {
      role      = "roles/artifactregistry.admin"
      condition = null
    }

    # This project also hosts the google-cloud-terraform repo's hub/dev VPCs, so this grant
    # lets the deploy SA touch that networking too, not just ../network's. Not scoped via IAM
    # Conditions because Compute Engine's condition support isn't confirmed for
    # networks/subnetworks/routers, and a condition that looks correct can silently never
    # match (see artifactregistry_admin above) — not worth risking on infra with this much
    # more to lose if guessed wrong.
    compute_network_admin = {
      role      = "roles/compute.networkAdmin"
      condition = null
    }

    # compute.networkAdmin excludes firewall rules by design; ../network's allow_internal rule
    # needs this separately.
    compute_security_admin = {
      role      = "roles/compute.securityAdmin"
      condition = null
    }

    vpcaccess_admin = {
      role      = "roles/vpcaccess.admin"
      condition = null
    }

    # roles/iam.serviceAccountCreator, not .serviceAccountAdmin: needed for ../invoice-sync's
    # create_service_account = true (the Cloud Run runtime SA), and .serviceAccountCreator
    # only grants create/get/list, not delete/update/setIamPolicy on every service account in
    # the project.
    service_account_creator = {
      role      = "roles/iam.serviceAccountCreator"
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

# Preserves the pre-refactor resource addresses' real IAM bindings instead of destroying and
# recreating each one under the new for_each key.
moved {
  from = google_project_iam_member.run_admin_scoped
  to   = google_project_iam_member.deploy_sa_roles["run_admin_scoped"]
}
moved {
  from = google_project_iam_member.artifactregistry_admin
  to   = google_project_iam_member.deploy_sa_roles["artifactregistry_admin"]
}
moved {
  from = google_project_iam_member.compute_network_admin
  to   = google_project_iam_member.deploy_sa_roles["compute_network_admin"]
}
moved {
  from = google_project_iam_member.compute_security_admin
  to   = google_project_iam_member.deploy_sa_roles["compute_security_admin"]
}
moved {
  from = google_project_iam_member.vpcaccess_admin
  to   = google_project_iam_member.deploy_sa_roles["vpcaccess_admin"]
}
moved {
  from = google_project_iam_member.service_account_creator
  to   = google_project_iam_member.deploy_sa_roles["service_account_creator"]
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
