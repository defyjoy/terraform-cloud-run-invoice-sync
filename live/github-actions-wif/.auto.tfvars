project_id = "yeti-504903"
region     = "us-central1"

github_owner = "defyjoy"
github_repo  = "terraform-cloud-run-invoice-sync"
github_ref   = "refs/heads/main"

state_bucket = "yeti-terraform-state-bucket"

deploy_account_id = "github-deployer"

# Must match ../invoice-sync's own service_name/artifact_registry_repo — scopes run.admin and
# artifactregistry.writer to just this service/repo via IAM Conditions.
cloud_run_service_name = "invoice-sync"
artifact_registry_repo = "invoice-sync"
