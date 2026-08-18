project_id   = "yeti-504903"
region       = "us-central1"
service_name = "invoice-sync"

artifact_registry_repo = "invoice-sync"

notification_email = "joydeepbeyondsky86@gmail.com"

# github-deployer@<project>.iam.gserviceaccount.com is deterministic from
# ../github-actions-wif's deploy_account_id ("github-deployer") + project_id — no need to wait
# for that stack's apply to fill this in, just to apply it before this stack.
deploy_service_account_email = "github-deployer@yeti-504903.iam.gserviceaccount.com"

# Cloud Run is private (INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER) and reached only through
# module.lb. Points at the hub VPC created by the google-cloud-terraform repo's live/hub/vpc.
network_name    = "yeti-hub-vpc"
subnetwork_name = "yeti-hub-run-us-central1-0"
vpc_egress      = "PRIVATE_RANGES_ONLY"

lb_name = "invoice-sync-lb"

min_instance_count  = 0
max_instance_count  = 2
deletion_protection = true

# image_tag has no value here — the pipeline always passes -var image_tag=<git sha> on the CLI.
