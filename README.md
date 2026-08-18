# terraform-cloud-run-invoice-sync

Terraform for the `invoice-sync` Cloud Run service in the `yeti-504903` project: the service
itself, its runtime service account, a GitHub Actions deploy identity (Workload Identity
Federation, no key files), a public load balancer as the only entry point, and email alerting
when a deployed revision fails to become ready.

```
modules/
├── cloud-run/                copied from defyjoy/google-cloud-terraform, unchanged
├── github-actions-wif/       WIF pool + provider + deploy service account, scoped to one repo
├── deployment-failure-alert/ Pub/Sub topic + email/Pub/Sub notification channels + alert policy
└── serverless-lb/            copied from defyjoy/google-cloud-terraform, unchanged
live/
├── github-actions-wif/  the deploy identity — its own state, applied by hand once (bootstrap)
└── invoice-sync/        the service, Artifact Registry repo, load balancer, and failure
                          alerting — applied by the pipeline from then on
.github/
└── workflows/
    └── deploy.yml    build image -> push -> terraform apply -var image_tag=<sha>
```

Each root module holds separate state:
`gs://yeti-terraform-state-bucket/yeti-504903/live/<github-actions-wif|invoice-sync>`. They're
split because `github-actions-wif` has to exist before the pipeline can authenticate at all —
if it lived in the same state as the service, the very first apply of *everything* would have
to run locally. Splitting it keeps that manual step to the smallest possible slice, and lets
`invoice-sync` be applied via GitHub only, per this repo's `CLAUDE.md`.

## Usage

```bash
task                             # list tasks
task github-actions-wif          # init + plan the deploy identity (bootstrap only)
task invoice-sync                # init + plan the service (normally the pipeline's job)
ACTION=apply task invoice-sync   # init + apply
```

`invoice-sync`'s `image_tag` has no default and must always be passed explicitly:

```bash
task invoice-sync -- -var image_tag=<git-sha>
```

## Bootstrap: `github-actions-wif` must be applied locally, once

The GitHub Actions pipeline authenticates via Workload Identity Federation, but the pool,
provider and deploy service account it authenticates as are themselves Terraform-managed — they
can't exist before the first apply, and the pipeline can't authenticate before they exist. So,
before the pipeline can deploy anything:

1. Apply `github-actions-wif` locally, with your own `gcloud` credentials:
   ```bash
   ACTION=apply task github-actions-wif
   ```
   This is the *only* stack meant to be applied outside the pipeline — it never needs an image
   tag or a running Cloud Run service, so there's no bootstrap placeholder value needed anywhere.
2. Read its outputs:
   ```bash
   terraform -chdir=live/github-actions-wif output -raw workload_identity_provider
   terraform -chdir=live/github-actions-wif output -raw service_account_email
   ```
3. Set them as GitHub repo variables (Settings → Secrets and variables → Actions → Variables):
   `WIF_PROVIDER` and `DEPLOY_SA_EMAIL`.
4. `live/invoice-sync` builds this same account's email itself from `project_id` +
   `deploy_account_id` — as long as both stacks' `.auto.tfvars` set the same
   `deploy_account_id` (`"github-deployer"` by default in both), there's nothing to copy from
   this stack's output into the other.
5. From then on, pushes to `main` (or a manual `workflow_dispatch`) build, push and deploy
   `invoice-sync` end to end — no further local applies required.

## Deployment failure alerting

`modules/deployment-failure-alert` watches Cloud Run's own log line for a revision that never
went healthy (`Ready condition status changed to False`) via a log-based Cloud Monitoring alert
policy, and notifies two channels in parallel: a Pub/Sub topic (`deployment-failures`, for any
future automation that wants to subscribe) and an email address (`notification_email` in
`.auto.tfvars`).

## Private Cloud Run behind a public load balancer

Cloud Run's `ingress` is `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` — the service's own
`*.run.app` URL refuses direct requests, and `module.lb` (an external HTTP(S) load balancer,
`modules/serverless-lb`) is the only path in. This mirrors
`google-cloud-terraform`'s `live/hub/cloud-run` pattern.

Getting there requires Direct VPC egress into a real VPC, which this repo doesn't create itself
— `network_name`/`subnetwork_name` (`.auto.tfvars`) are set to the hub VPC and its Cloud Run
subnet (`yeti-hub-vpc` / `yeti-hub-run-us-central1-0`) already created by the
`google-cloud-terraform` repo's `live/hub/vpc`. That stack must exist first; change the values
in `.auto.tfvars` if this repo shouldn't depend on it.

No VPN is wired up — the load balancer is public. Add one later (or switch ingress to
`INGRESS_TRAFFIC_INTERNAL_ONLY` and drop the load balancer) if the service needs to be
VPN-only instead.

## App source

`app/` is a placeholder Node.js "Hello, World!" server (`GET /` and `GET /healthz`), just
enough to prove the pipeline end to end — swap in the real invoice-sync service without
touching the `Dockerfile`, as long as it keeps listening on `$PORT` (8080 by default, matching
`modules/cloud-run`'s `port` var).
