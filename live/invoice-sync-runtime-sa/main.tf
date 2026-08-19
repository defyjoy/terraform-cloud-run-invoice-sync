module "runtime_sa" {
  source = "../../modules/invoice-sync-runtime-sa"

  project_id = var.project_id
  account_id = var.account_id

  project_roles    = var.project_roles
  sa_admin_members = ["serviceAccount:${var.deploy_account_id}@${var.project_id}.iam.gserviceaccount.com"]
}
