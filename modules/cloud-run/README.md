# cloud-run

Deploys a single Cloud Run service, wrapping the
[`v2` submodule](https://registry.terraform.io/modules/GoogleCloudPlatform/cloud-run/google/latest/submodules/v2)
of [`GoogleCloudPlatform/cloud-run/google`](https://registry.terraform.io/modules/GoogleCloudPlatform/cloud-run/google/latest)
with a thinner, single-container interface and secure-by-default settings.

## Usage

```hcl
module "api" {
  source = "../../../modules/cloud-run"

  project_id   = "my-project"
  service_name = "api"
  location     = "us-central1"
  image        = "us-docker.pkg.dev/my-project/api/api:latest"

  members = ["allUsers"] # omit to keep the service private
}
```

## Notes

- `deletion_protection` defaults to `true`, same as the `gke` module: `terraform destroy`
  fails on the service rather than silently deleting it, until a caller opts out explicitly.
- `create_service_account` defaults to `true`: a dedicated service account is generated for
  the revision unless an existing one is passed via `service_account`. Grant it project roles
  through `service_account_project_roles` rather than reusing a broader default identity.
- `members` defaults to `[]`, so the service has no invoker access granted by this module —
  pass `["allUsers"]` for a public service, or specific `serviceAccount:`/`user:` members
  otherwise.
- `min_instance_count` defaults to `0` (scale-to-zero) and `cpu_idle` to `true` (CPU only
  allocated while handling a request), matching Cloud Run's cost-optimized defaults. Set
  `cpu_idle = false` for workloads that do background work between requests.
- `ingress` defaults to `INGRESS_TRAFFIC_ALL`. Set it to `INGRESS_TRAFFIC_INTERNAL_ONLY` or
  `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` to keep the service off the public internet, and
  pair with `vpc_access` if it also needs to reach resources inside a VPC (e.g. a private GKE
  cluster or Cloud SQL instance in `network`/`gke`).
- This module exposes a single container. For multi-container revisions, GPUs, Cloud Run
  Jobs, or the full secure-serverless network/LB/Cloud Armor blueprint, use the relevant
  upstream submodule directly — see the sub-module survey below.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `project_id` | Project the service is created in | `string` | n/a |
| `service_name` | Name of the Cloud Run service | `string` | n/a |
| `location` | Deployment location, e.g. `us-central1` | `string` | n/a |
| `image` | Container image to deploy | `string` | n/a |
| `container_name` | Name of the container within the revision | `string` | `null` |
| `container_command` | Overrides the image ENTRYPOINT | `list(string)` | `[]` |
| `container_args` | Arguments passed to the ENTRYPOINT | `list(string)` | `[]` |
| `port` | Port the container listens on | `number` | `8080` |
| `env_vars` | Cleartext environment variables | `map(string)` | `{}` |
| `env_secret_vars` | Env vars sourced from Secret Manager | `map(object)` | `{}` |
| `cpu` | CPU limit, e.g. `"1"` | `string` | `"1"` |
| `memory` | Memory limit, e.g. `"512Mi"` | `string` | `"512Mi"` |
| `cpu_idle` | Throttle CPU to zero outside requests | `bool` | `true` |
| `min_instance_count` | Minimum instances kept running | `number` | `0` |
| `max_instance_count` | Maximum instances to scale out to | `number` | `2` |
| `max_instance_request_concurrency` | Max concurrent requests per instance | `number` | `null` |
| `timeout` | Max request response time, e.g. `"300s"` | `string` | `"300s"` |
| `ingress` | Traffic allowed to reach the service | `string` | `"INGRESS_TRAFFIC_ALL"` |
| `vpc_access` | Connector/direct-VPC egress config | `object` | `null` |
| `create_service_account` | Generate a dedicated service account | `bool` | `true` |
| `service_account` | Existing service account email to use instead | `string` | `null` |
| `service_account_project_roles` | Project roles granted to the generated SA | `list(string)` | `[]` |
| `members` | Members granted `roles/run.invoker` | `list(string)` | `[]` |
| `deletion_protection` | Block `terraform destroy` on the service | `bool` | `true` |
| `labels` | Labels applied to the service | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `service_name` | Name of the created service |
| `service_id` | Fully qualified service ID |
| `url` | URL the service is reachable at |
| `location` | Location the service was created in |
| `project_id` | Project the service was created in |
| `service_account_id` | ID and email of the service account the revision runs as |
| `latest_ready_revision` | Name of the latest revision serving traffic |

## Sub-modules of the upstream `GoogleCloudPlatform/cloud-run/google` module

The upstream module ships as a root module plus eight sub-modules. This wrapper uses only
`v2`; the rest are documented here for when a future need outgrows this module's scope.

| Sub-module | Purpose |
|---|---|
| **(root)** | Deploys a Cloud Run service on the **v1** (Knative-style) API, plus domain mapping and invoker IAM. Superseded by `v2` for new work — kept for compatibility with existing v1-based configs. |
| **`v2`** | Deploys a Cloud Run service on the modern **v2 API**: multi-container revisions, GPUs, direct VPC egress, volumes (Secret Manager, Cloud SQL, GCS, NFS, in-memory), IAP, session affinity. This is what `modules/cloud-run` here wraps. Google's recommended module for new single-service deployments. |
| **`job-exec`** | Deploys a **Cloud Run Job** (run-to-completion, not request-serving) and optionally triggers an execution as part of `terraform apply`. Used for batch jobs, migrations, and scheduled tasks rather than HTTP services. |
| **`secure-cloud-run-core`** | The core piece of Google's "secure serverless" blueprint: the Cloud Run service itself, a Secret Manager IAM binding for the runtime service account, an HTTPS Load Balancer with Google-managed certs in front of it, and a Cloud Armor policy pre-loaded with OWASP rules (SQLi, XSS, LFI, RCE, RFI, scanner detection, protocol attack, session fixation). |
| **`secure-cloud-run-security`** | The security/IAM layer of the same blueprint: creates a KMS keyring/key for CMEK, enforces org policies restricting ingress to internal+LB traffic and egress to private ranges only, and grants persona-based IAM roles (serverless admin, security admin, developer, etc.) across the security and service projects. |
| **`secure-serverless-net`** | The networking layer of the blueprint: firewall rules between the service, its Serverless VPC Access connector, and the load balancer, plus the connector's dedicated subnet. Supports Shared VPC, with the connector optionally created in the host project. |
| **`secure-cloud-run`** | Orchestrates the three modules above (`secure-cloud-run-core` + `secure-serverless-net` + `secure-cloud-run-security`) into the complete secure-serverless-for-Cloud-Run blueprint in one call. Use this (not the pieces individually) when the goal is the full hardened reference architecture rather than a plain service. |
| **`secure-serverless-harness`** | A self-contained test/demo harness for the blueprint: creates its own folder, service project, security project (with KMS + Artifact Registry, seeded with a hello-world image), network, subnet, and deny-all-egress firewall rule. Meant for trying out or developing against the blueprint, not for adopting directly into a real environment. |
| **`service-project-factory`** | Provisions the service project(s) that host Cloud Run workloads in the secure blueprint, wiring up Shared VPC attachment and the project-level IAM/API enablement the blueprint expects. |

**Rule of thumb:** for a plain internet- or Shared-VPC-facing service, use `v2` (what this
module wraps). For a batch/cron workload, use `job-exec`. For the full hardened
LB+Armor+CMEK+org-policy reference architecture, use `secure-cloud-run` rather than assembling
its three constituent modules by hand.
