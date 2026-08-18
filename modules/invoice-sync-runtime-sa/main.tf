locals {
  email = "${var.account_id}@${var.project_id}.iam.gserviceaccount.com"
}

# Project-level roles for a service account that already exists (created by ../invoice-sync's
# create_service_account = true), not created here — granting any role to a service account
# requires resourcemanager.projects.setIamPolicy, which can't be scoped down to "only this one
# grant," so the deploy SA that creates the account can't also be the one granting these. See
# CLAUDE.md's IAM section.
resource "google_project_iam_member" "project_roles" {
  for_each = toset(var.project_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${local.email}"
}

# Lets the deploy service account deploy new revisions running as this service account, without
# granting it roles/iam.serviceAccountUser on the whole project. Same reasoning as above:
# iam.serviceAccounts.setIamPolicy can't be scoped down either.
resource "google_service_account_iam_member" "actas_members" {
  for_each = toset(var.actas_members)

  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.email}"
  role               = "roles/iam.serviceAccountUser"
  member             = each.value
}
