project_id   = "yeti-504903"
region       = "us-central1"
service_name = "invoice-sync"

artifact_registry_repo = "invoice-sync"

notification_email = "joydeepbeyondsky86@gmail.com"

runtime_service_account_id = "invoice-sync-us-central1-sa"

vpc_connector_name = "invoice-sync-connector"
vpc_egress         = "PRIVATE_RANGES_ONLY"

lb_name = "invoice-sync-lb"

min_instance_count  = 0
max_instance_count  = 2
deletion_protection = true
