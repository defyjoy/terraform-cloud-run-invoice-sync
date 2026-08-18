# terraform-cloud-run-invoice-sync

Terraform for the `invoice-sync` Cloud Run service in the `yeti-504903` project: the service
itself, its runtime service account, a GitHub Actions deploy identity (Workload Identity
Federation, no key files), a public load balancer as the only entry point, and email alerting
when a deployed revision fails to become ready.

```
modules/
├── enable-apis/              wraps google_project_service, generic across projects
├── artifact-registry/        wraps google_artifact_registry_repository
├── cloud-run/                copied from defyjoy/google-cloud-terraform, unchanged
├── github-actions-wif/       WIF pool + provider + deploy service account, scoped to one repo
├── deployment-failure-alert/ Pub/Sub topic + email/Pub/Sub notification channels + alert policy
└── serverless-lb/            copied from defyjoy/google-cloud-terraform, unchanged
live/
├── enable-apis/          service APIs this repo's stacks need — its own state
├── github-actions-wif/   the deploy identity — its own state, applied by hand once (bootstrap)
├── artifact-registry/    the invoice-sync image repo — its own state, applied ahead of
│                         docker push, since it has to exist before the pipeline can push to it
└── invoice-sync/         the service, load balancer, and failure alerting
.github/
└── workflows/
    └── deploy.yml    artifact-registry -> build -> push -> `task invoice-sync`
```

Each root module holds separate state:
`gs://yeti-terraform-state-bucket/yeti-504903/live/<enable-apis|github-actions-wif|artifact-registry|invoice-sync>`.
`enable-apis` and `github-actions-wif` are both bootstrap-only, applied locally with the
operator's own credentials, and never touched by the pipeline — `github-actions-wif` because it
has to exist before the pipeline can authenticate at all, and `enable-apis` because
`roles/serviceusage.*` has no way to scope down to individual services (see CLAUDE.md's IAM
section), so granting the deploy SA project-wide service-enablement access isn't worth the blast
radius. `artifact-registry` is split into its own stack because the pipeline applies it on every
run, ahead of the image push that needs it to exist.

`deploy.yml` never runs `terraform` directly — it installs Task and calls the exact same
`task <name>` a human would, so the init/backend-config/apply sequence lives in one place
(`Taskfile.yml`'s `_tf` task) instead of being duplicated as raw commands in the workflow. The
backend bucket and prefix Task builds `-backend-config` from come from `PROJECT_ID`/
`STATE_BUCKET`, which Task reads from the environment automatically — set once in `deploy.yml`'s
job-level `env:`, not hardcoded a second time as literal `-backend-config` strings.

## Pipeline stages and privileges

`deploy.yml` runs three stages in order: `artifact-registry` (apply) → docker build → docker
push → `invoice-sync` (apply). `artifact-registry` runs every time — it's idempotent, a no-op
once the repo exists — so a deleted repo self-heals on the next push without a separate manual
step.

This means the deploy SA needs `roles/artifactregistry.admin` (not `.repoAdmin`/`.writer`,
neither of which grant `repositories.create`/`.delete`), and unlike every other grant in this
repo, it's project-wide rather than scoped to the one repo — Artifact Registry has no
`resource.name`-based IAM Conditions at all, only Resource Manager tags, a different mechanism.
See CLAUDE.md's IAM section.

`enable-apis` is deliberately kept local-only, unlike `artifact-registry` — see CLAUDE.md's IAM
section for why `roles/serviceusage.*` doesn't scope down the same way.

## Usage

```bash
task                             # list tasks
task enable-apis                 # init + plan the service APIs (bootstrap only, local)
task github-actions-wif          # init + plan the deploy identity (bootstrap only, local)
task artifact-registry           # init + plan the image repo (normally the pipeline's job)
task invoice-sync                # init + plan the service (normally the pipeline's job)
ACTION=apply task invoice-sync   # init + apply
```

`PROJECT_ID` and `STATE_BUCKET` (used for every task's `-backend-config`) default to
`yeti-504903` / `yeti-terraform-state-bucket` but can be overridden the same way `ACTION` is,
via the environment: `PROJECT_ID=other-project STATE_BUCKET=other-bucket task invoice-sync`.

`invoice-sync`'s `image_tag` has no default and must always be passed explicitly:

```bash
task invoice-sync -- -var image_tag=<git-sha>
```

## Bootstrap: `enable-apis` and `github-actions-wif` must be applied locally, once

The GitHub Actions pipeline authenticates via Workload Identity Federation, but the pool,
provider and deploy service account it authenticates as are themselves Terraform-managed — they
can't exist before the first apply, and the pipeline can't authenticate before they exist. And
`github-actions-wif` itself can't apply without APIs (`iam`, `sts`, `cloudresourcemanager`, ...)
that this project doesn't enable by default. So, before the pipeline can deploy anything:

0. Apply `enable-apis` locally, with your own `gcloud` credentials — the pipeline never applies
   this stack (see CLAUDE.md's IAM section), so any newly-added API needs a re-run of this step:
   ```bash
   ACTION=apply task enable-apis
   ```
1. Apply `github-actions-wif` locally, with your own `gcloud` credentials:
   ```bash
   ACTION=apply task github-actions-wif
   ```
   Both this and `enable-apis` are meant to be applied outside the pipeline only — neither needs
   an image tag or a running Cloud Run service, so there's no bootstrap placeholder value needed
   anywhere. `artifact-registry` doesn't need a separate manual apply: once `github-actions-wif`
   exists and its outputs are set as repo variables (step 3), the pipeline applies it itself on
   every run.
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
