locals {
  email = "${var.account_id}@${var.project_id}.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "project_roles" {
  for_each = toset(var.project_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${local.email}"
}

resource "google_service_account_iam_member" "sa_admin_members" {
  for_each = toset(var.sa_admin_members)

  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.email}"
  role               = "roles/iam.serviceAccountAdmin"
  member             = each.value
}
