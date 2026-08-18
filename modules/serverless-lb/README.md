# serverless-lb

Global external HTTP(S) Load Balancer fronting a single Cloud Run service via a Serverless NEG,
wrapping [`GoogleCloudPlatform/lb-http/google//modules/serverless_negs`](https://registry.terraform.io/modules/GoogleCloudPlatform/lb-http/google/latest/submodules/serverless_negs).

The point of this module is the split it enables: the load balancer is the only public entry
point, and the Cloud Run service behind it stays off the public internet — pair it with
`ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"` (see `modules/cloud-run`) so `*.run.app`
refuses direct requests and only traffic that came through this load balancer is served.

## Usage

```hcl
module "lb" {
  source = "../../../modules/serverless-lb"

  project_id              = "my-project"
  name                    = "my-service-lb"
  region                  = "us-central1"
  cloud_run_service_name  = module.my_service.service_name
}
```

## Notes

- `ssl` defaults to `false`, serving plain HTTP on port 80. Set `ssl = true` and `domains` to
  terminate HTTPS with a Google-managed certificate; HTTP then redirects to HTTPS.
- The Cloud Run service still needs `roles/run.invoker` granted to whichever members should
  reach it through the load balancer (`allUsers` for public access) — this module only handles
  the network path, not IAM.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `project_id` | Project the load balancer and NEG are created in | `string` | n/a |
| `name` | Base name for the load balancer's components | `string` | n/a |
| `region` | Region of the Cloud Run service | `string` | n/a |
| `cloud_run_service_name` | Name of the Cloud Run service to front | `string` | n/a |
| `ssl` | Terminate HTTPS with a managed cert and redirect HTTP | `bool` | `false` |
| `domains` | Domains for the managed SSL certificate | `list(string)` | `[]` |
| `enable_cdn` | Cache responses at Cloud CDN | `bool` | `false` |
| `labels` | Labels applied to the forwarding rule | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `external_ip` | Public IPv4 address of the load balancer |
| `url_map` | Self link of the URL map |
| `neg_id` | ID of the serverless NEG |
