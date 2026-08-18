project_id = "yeti-504903"

github_owner = "defyjoy"
github_repo  = "terraform-cloud-run-invoice-sync"

state_bucket = "yeti-terraform-state-bucket"

deploy_account_id = "github-deployer"

# Least privilege for what ../invoice-sync's pipeline actually does: deploy Cloud Run
# revisions, push images, and act as the runtime service account.
project_roles = [
  "roles/run.admin",
  "roles/artifactregistry.writer",
  "roles/iam.serviceAccountUser",
]
