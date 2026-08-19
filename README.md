# terraform-cloud-run-invoice-sync

Terraform for the `invoice-sync` Cloud Run service in the `yeti-504903` project: the service
itself, its runtime service account, a GitHub Actions deploy identity (Workload Identity
Federation, no key files), a public load balancer as the only entry point, and email alerting
when a deployed revision fails to become ready.

```
modules/
├── enable-apis/              wraps google_project_service, generic across projects
├── artifact-registry/        wraps google_artifact_registry_repository
├── secret-manager-secret/    wraps google_secret_manager_secret — creates the secret
│                             container only, never a version (the value never lands in
│                             Terraform state)
├── cloud-run/                copied from defyjoy/google-cloud-terraform, unchanged
├── github-actions-wif/       WIF pool + provider + deploy service account, scoped to one repo
├── deployment-failure-alert/ Pub/Sub topic + email/Pub/Sub notification channels + alert policy
└── serverless-lb/            copied from defyjoy/google-cloud-terraform, unchanged
live/
├── enable-apis/              service APIs this repo's stacks need — its own state
├── github-actions-wif/       the deploy identity — its own state, applied by hand once
│                             (bootstrap)
├── artifact-registry/        the invoice-sync image repo — its own state, applied ahead of
│                             docker push, since it has to exist before the pipeline can push
│                             to it
├── network/                  this repo's own VPC and connector (directly composing
│                             terraform-google-modules/network/google, no wrapper module) —
│                             its own state, applied ahead of invoice-sync, since Cloud Run's
│                             vpc_access references it by name
├── db-secrets/                the db-password secret container — its own state, applied ahead
│                             of invoice-sync, since Cloud Run's env_secret_vars references it
│                             by name
└── invoice-sync/             the service (including its runtime SA, its project roles, and the
                              deploy SA's actAs grant on it), load balancer, and failure
                              alerting
.github/
└── workflows/
    └── deploy.yml    artifact-registry + network + db-secrets -> build -> push -> `task invoice-sync`
```

Each root module holds separate state:
`gs://yeti-terraform-state-bucket/yeti-504903/live/<enable-apis|github-actions-wif|artifact-registry|network|db-secrets|invoice-sync>`.
`enable-apis` and `github-actions-wif` are the **only** stacks applied manually, with the
operator's own credentials, and never touched by the pipeline — `github-actions-wif` because it
has to exist before the pipeline can authenticate at all, `enable-apis` because
`roles/serviceusage.*` has no way to scope down to individual services (see CLAUDE.md's IAM
section for both). `artifact-registry`, `network` and `db-secrets` are split into their own
stacks because the pipeline applies them on every run, ahead of what depends on them.

`deploy.yml` never runs `terraform` directly — it installs Task and calls the exact same
`task <name>` a human would, so the init/backend-config/apply sequence lives in one place
(`Taskfile.yml`'s `_tf` task) instead of being duplicated as raw commands in the workflow. The
backend bucket and prefix Task builds `-backend-config` from come from `PROJECT_ID`/
`STATE_BUCKET`, which Task reads from the environment automatically — set once in `deploy.yml`'s
job-level `env:`, not hardcoded a second time as literal `-backend-config` strings.

## Pipeline stages and privileges

`deploy.yml` runs four stages in order: `artifact-registry` + `network` + `db-secrets` (apply,
any order) → docker build → docker push → `invoice-sync` (apply). All three of
`artifact-registry`, `network` and `db-secrets` run every time — idempotent, a no-op once they
exist — so each self-heals on the next push if deleted, without a separate manual step.

This means the deploy SA needs, project-wide and unconditioned:
- `roles/run.admin` — Cloud Run's `Service` resource has no `resource.name`-based IAM
  Conditions at all (Google's own docs: "Supports IAM Conditions: No"). A scoped condition here
  looked correct and silently denied every request; see CLAUDE.md's IAM section.
- `roles/artifactregistry.admin` (not `.repoAdmin`/`.writer`, neither of which grant
  `repositories.create`/`.delete`) — Artifact Registry has no `resource.name`-based IAM
  Conditions at all, only Resource Manager tags, a different mechanism.
- `roles/compute.networkAdmin`, `roles/compute.securityAdmin` (firewall rules aren't covered by
  `networkAdmin`) and `roles/vpcaccess.admin`, for `network`'s VPC/subnet/firewall/connector.
  This is a materially bigger blast radius than everything else here: `yeti-504903` also hosts
  the `google-cloud-terraform` repo's hub/dev VPCs, so the deploy SA can touch that networking
  too, not just this repo's own. Accepted as a discussed trade-off — see CLAUDE.md's IAM section.
- `roles/pubsub.editor` (not `.admin`), for `deployment_alert`'s Pub/Sub topic.
- `roles/iam.serviceAccountAdmin` and `roles/resourcemanager.projectIamAdmin`, so `invoice-sync`
  can grant the Cloud Run runtime SA it creates its own project roles
  (`logging.logWriter`/`cloudtrace.agent`) and the deploy SA's own `iam.serviceAccountUser`
  (actAs) grant on it, in the same pipeline run. Neither can be scoped down to "only this one
  grant" — `projectIamAdmin` can rewrite the entire project's IAM policy, and
  `serviceAccountAdmin` can set IAM policy on every service account in the project, not just
  this one. A discussed, accepted trade-off in place of a separate manually-applied bootstrap
  stack. See CLAUDE.md's IAM section.
- `roles/secretmanager.admin`, so `db-secrets` can create the `db-password` secret and manage
  IAM policy on it entirely from the pipeline — `secretmanager.secrets.create` is authorized
  against the project, not the not-yet-existing secret, so it can't be scoped to one secret in
  advance either. Runtime access is unaffected: the Cloud Run runtime SA still only gets
  `roles/secretmanager.secretAccessor` scoped per-secret via `modules/cloud-run`'s
  `secret_accessor_secrets`, never a project-wide role.

`enable-apis` is deliberately kept local-only, unlike `artifact-registry`/`network` — see
CLAUDE.md's IAM section for why.

## Usage

```bash
task                             # list tasks
task enable-apis                 # init + plan the service APIs (bootstrap only, local)
task github-actions-wif          # init + plan the deploy identity (bootstrap only, local)
task artifact-registry           # init + plan the image repo (normally the pipeline's job)
task network                     # init + plan the VPC/connector (normally the pipeline's job)
task db-secrets                  # init + plan the db-password secret (normally the pipeline's job)
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

## Bootstrap

The GitHub Actions pipeline authenticates via Workload Identity Federation, but the pool,
provider and deploy service account it authenticates as are themselves Terraform-managed — they
can't exist before the first apply, and the pipeline can't authenticate before they exist. And
`github-actions-wif` itself can't apply without APIs (`iam`, `sts`, `cloudresourcemanager`, ...)
that this project doesn't enable by default.

0. Apply `enable-apis` locally, with your own `gcloud` credentials — the pipeline never applies
   this stack (see CLAUDE.md's IAM section), so any newly-added API needs a re-run of this step:
   ```bash
   ACTION=apply task enable-apis
   ```
1. Apply `github-actions-wif` locally, with your own `gcloud` credentials:
   ```bash
   ACTION=apply task github-actions-wif
   ```
2. Read its outputs and set them as GitHub repo variables (Settings → Secrets and variables →
   Actions → Variables): `WIF_PROVIDER` and `DEPLOY_SA_EMAIL`.
   ```bash
   terraform -chdir=live/github-actions-wif output -raw workload_identity_provider
   terraform -chdir=live/github-actions-wif output -raw service_account_email
   ```
3. Push to `main` (or run `workflow_dispatch`) — the pipeline creates the runtime SA, grants it
   its own project roles and the deploy SA's actAs on it, and deploys `invoice-sync` end to
   end, all in one run.
4. From then on, every push builds, pushes and deploys automatically — no further local applies
   required, unless a new API is needed (re-run step 0). `db-secrets` only creates the
   `db-password` secret *container* — the pipeline never writes a value to it, so add one
   out-of-band once, with your own credentials:
   ```bash
   gcloud secrets versions add db-password --project=yeti-504903 --data-file=<path-to-password-file>
   ```

## Deployment failure alerting

`modules/deployment-failure-alert` watches Cloud Run's own log line for a revision that never
went healthy (`Ready condition status changed to False`) via a log-based Cloud Monitoring alert
policy, and notifies two channels in parallel: a Pub/Sub topic (`deployment-failures`, for any
future automation that wants to subscribe) and an email address (`notification_email` in
`.auto.tfvars`).

## Private Cloud Run behind a public load balancer

Cloud Run's `ingress` is `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` — the service's own
`*.run.app` URL refuses direct requests, and `module.lb` (an external HTTP(S) load balancer,
`modules/serverless-lb`) is the only path in.

Outbound (egress) traffic reaches private destinations through a Serverless VPC Access
connector, on its own dedicated subnet in `live/network`'s own VPC (`10.50.0.0/28`, part of a
reserved `10.50.0.0/24` block — see that stack's `.auto.tfvars`) — self-contained within this
repo, not a dependency on `google-cloud-terraform`'s hub VPC. `vpc_egress`
(`live/invoice-sync/.auto.tfvars`) controls whether only RFC1918 destinations
(`PRIVATE_RANGES_ONLY`) or everything (`ALL_TRAFFIC`) routes through it.

No VPN is wired up — the load balancer is public. Add one later (or switch ingress to
`INGRESS_TRAFFIC_INTERNAL_ONLY` and drop the load balancer) if the service needs to be
VPN-only instead.

## App source

`app/` is a placeholder Node.js "Hello, World!" server (`GET /` and `GET /healthz`), just
enough to prove the pipeline end to end — swap in the real invoice-sync service without
touching the `Dockerfile`, as long as it keeps listening on `$PORT` (8080 by default, matching
`modules/cloud-run`'s `port` var).
