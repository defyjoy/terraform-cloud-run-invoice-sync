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
└── invoice-sync/    the service, Artifact Registry repo, load balancer, WIF, and failure alerting
.github/
└── workflows/
    └── deploy.yml    build image -> push -> terraform apply -var image_tag=<sha>
```

State is stored at `gs://yeti-terraform-state-bucket/yeti-504903/live/invoice-sync`.

## Usage

```bash
task                             # list tasks
task invoice-sync                # init + plan
ACTION=apply task invoice-sync   # init + apply
```

`image_tag` has no default and must always be passed explicitly:

```bash
task invoice-sync -- -var image_tag=<git-sha>
```

## Bootstrap: first apply must run locally

The GitHub Actions pipeline authenticates via Workload Identity Federation, but the WIF
pool/provider/deploy-service-account are themselves created by this Terraform — they can't
exist before the first apply, and the pipeline can't authenticate before they exist. So:

1. Run the first apply locally, with your own `gcloud` credentials:
   ```bash
   ACTION=apply task invoice-sync -- -var image_tag=bootstrap
   ```
   (`bootstrap` is a placeholder tag — nothing needs to exist at that tag yet for the WIF/IAM
   resources to be created; the Cloud Run revision itself will fail to pull it, which is fine
   for this one-time step.)
2. Read the outputs:
   ```bash
   terraform -chdir=live/invoice-sync output -raw workload_identity_provider
   terraform -chdir=live/invoice-sync output -raw deploy_service_account_email
   ```
3. Set them as GitHub repo variables (Settings → Secrets and variables → Actions → Variables):
   `WIF_PROVIDER` and `DEPLOY_SA_EMAIL`.
4. From then on, pushes to `main` (or a manual `workflow_dispatch`) build, push and deploy the
   image, tagging every revision with the commit SHA.

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
— `network_name`/`subnetwork_name` (`variables.tf`) default to the hub VPC and its Cloud Run
subnet (`yeti-hub-vpc` / `yeti-hub-run-us-central1-0`) already created by the
`google-cloud-terraform` repo's `live/hub/vpc`. That stack must exist first; override the
variables to point elsewhere if this repo shouldn't depend on it.

No VPN is wired up — the load balancer is public. Add one later (or switch ingress to
`INGRESS_TRAFFIC_INTERNAL_ONLY` and drop the load balancer) if the service needs to be
VPN-only instead.

## App source

This repo holds only infrastructure. `deploy.yml` expects a `Dockerfile` at the repo root
building the invoice-sync service — add the application source separately.
