module "runtime_service_account" {
  source  = "terraform-google-modules/service-accounts/google"
  version = "~> 4.7"

  project_id    = var.project_id
  names         = [var.account_id]
  project_roles = [for role in var.project_roles : "${var.project_id}=>${role}"]
  display_name  = "Runtime identity for the ${var.service_name} Cloud Run service"
}

# Lets the deploy service account deploy new revisions running as this service account, without
# granting it roles/iam.serviceAccountUser on the whole project. Applied here (bootstrap, local
# credentials) rather than from live/invoice-sync's pipeline-applied stack: granting any role to
# a service account requires resourcemanager.projects.setIamPolicy or iam.serviceAccounts.setIamPolicy,
# neither of which can be scoped down to "only this one grant" — see CLAUDE.md's IAM section.
resource "google_service_account_iam_member" "actas_members" {
  for_each = toset(var.actas_members)

  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.runtime_service_account.email}"
  role               = "roles/iam.serviceAccountUser"
  member             = each.value
}
