# Runtime identity for the invoice-sync Cloud Run service, kept in its own state and applied by
# hand — granting it project-level roles, or granting the deploy SA actAs on it, needs
# resourcemanager.projects.setIamPolicy / iam.serviceAccounts.setIamPolicy, neither of which the
# pipeline's own deploy SA can be scoped to hold safely. See CLAUDE.md's IAM section.
module "runtime_sa" {
  source = "../../modules/invoice-sync-runtime-sa"

  project_id   = var.project_id
  account_id   = var.account_id
  service_name = var.service_name

  project_roles = var.project_roles
  actas_members = ["serviceAccount:${var.deploy_account_id}@${var.project_id}.iam.gserviceaccount.com"]
}
