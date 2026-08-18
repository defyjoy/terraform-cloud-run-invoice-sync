project_id   = "yeti-504903"
region       = "us-central1"
service_name = "invoice-sync"

artifact_registry_repo = "invoice-sync"

notification_email = "joydeepbeyondsky86@gmail.com"

# Must match ../github-actions-wif's own deploy_account_id — main.tf builds the email from this
# plus project_id, so there's nothing to wait on or copy from that stack's output.
deploy_account_id = "github-deployer"

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
