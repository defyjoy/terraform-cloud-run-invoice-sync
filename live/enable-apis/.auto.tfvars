project_id = "yeti-504903"

services = [
  "run.googleapis.com",             # Cloud Run service itself
  "artifactregistry.googleapis.com", # image repo the pipeline pushes to
  "compute.googleapis.com",          # load balancer, NEG, forwarding rule
  "iam.googleapis.com",              # service accounts, WIF pool/provider
  "iamcredentials.googleapis.com",   # WIF token impersonation
  "sts.googleapis.com",              # WIF token exchange (google-github-actions/auth)
  "cloudresourcemanager.googleapis.com", # underlies most project-level IAM operations
  "secretmanager.googleapis.com",    # per-secret access for the Cloud Run runtime SA
  "pubsub.googleapis.com",           # deployment-failure-alert's topic
  "monitoring.googleapis.com",       # deployment-failure-alert's alert policy/channels
  "logging.googleapis.com",          # roles/logging.logWriter, log-based alert condition
  "cloudtrace.googleapis.com",       # roles/cloudtrace.agent
  "storage.googleapis.com",          # Terraform state bucket access
  "serviceusage.googleapis.com",     # the pipeline enabling/managing this very list
  "vpcaccess.googleapis.com",        # Serverless VPC Access connector for invoice-sync
]
