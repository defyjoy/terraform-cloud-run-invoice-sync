project_id = "yeti-504903"
region     = "us-central1"

name = "invoice-sync"

# Reserved block for this VPC is 10.50.0.0/24; this /28 is the connector's own dedicated
# subnet, carved out of it. The rest of the /24 is unused until another subnet is needed.
connector_cidr = "10.50.0.0/28"
