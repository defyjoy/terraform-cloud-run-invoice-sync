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
  # Every project-level role the deploy SA holds. condition = null means unconditioned/
  # project-wide; see CLAUDE.md's IAM section for why each unconditioned entry couldn't be
  # scoped further.
  deploy_sa_roles = {
    # Cloud Run's Service resource does not support IAM Conditions at all (Google's own docs:
    # "Supports IAM Conditions: No") — confirmed after a resource.name-scoped condition here
    # looked correct (matched run.services.create's own parent-location requirement) and still
    # denied every request, the same silent-no-op failure mode as artifactregistry_admin below.
    run_admin = {
      role      = "roles/run.admin"
      condition = null
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

    # roles/pubsub.editor, not .admin: needed for ../invoice-sync's deployment_alert module to
    # create its Pub/Sub topic. .editor grants topics.create/get/list/update/delete/publish but
    # not setIamPolicy, unlike .admin.
    pubsub_editor = {
      role      = "roles/pubsub.editor"
      condition = null
    }

    # Needed to read the externally-created Cloud Run runtime SA (create_service_account =
    # false in ../invoice-sync) — .serviceAccountViewer grants get/list/getIamPolicy only, no
    # write permissions, the narrowest predefined role with iam.serviceAccounts.get.
    service_account_viewer = {
      role      = "roles/iam.serviceAccountViewer"
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
