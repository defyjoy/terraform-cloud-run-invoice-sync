# Grants roles to the invoice-sync Cloud Run runtime SA, kept in its own state and applied by
# hand — ../invoice-sync's create_service_account = true creates the account itself (a narrow
# permission), but granting it project-level roles, or granting the deploy SA actAs on it,
# needs resourcemanager.projects.setIamPolicy / iam.serviceAccounts.setIamPolicy, neither of
# which the pipeline's own deploy SA can be scoped to hold safely. See CLAUDE.md's IAM section.
module "runtime_sa" {
  source = "../../modules/invoice-sync-runtime-sa"

  project_id = var.project_id
  account_id = var.account_id

  project_roles = var.project_roles
  actas_members = ["serviceAccount:${var.deploy_account_id}@${var.project_id}.iam.gserviceaccount.com"]
}
