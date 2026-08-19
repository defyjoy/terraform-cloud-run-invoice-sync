# 🚀 terraform-cloud-run-invoice-sync

Terraform for the `invoice-sync` Cloud Run service in the `yeti-504903` project:

- 🏃 the service itself
- 🪪 its runtime service account
- 🔑 a GitHub Actions deploy identity (Workload Identity Federation, no key files)
- 🌐 a public load balancer as the only entry point
- 📧 email alerting when a deployed revision fails to become ready

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

- 🗄️ Each root module holds separate state:
  `gs://yeti-terraform-state-bucket/yeti-504903/live/<enable-apis|github-actions-wif|artifact-registry|network|db-secrets|invoice-sync>`.
- ✋ `enable-apis` and `github-actions-wif` are the **only** stacks applied manually, with the
  operator's own credentials, and never touched by the pipeline:
  - `github-actions-wif` because it has to exist before the pipeline can authenticate at all
  - `enable-apis` because `roles/serviceusage.*` has no way to scope down to individual
    services (see CLAUDE.md's IAM section for both)
- 🔁 `artifact-registry`, `network` and `db-secrets` are split into their own stacks because the
  pipeline applies them on every run, ahead of what depends on them.
- 🛠️ `deploy.yml` never runs `terraform` directly:
  - it installs Task and calls the exact same `task <name>` a human would, so the
    init/backend-config/apply sequence lives in one place (`Taskfile.yml`'s `_tf` task) instead
    of being duplicated as raw commands in the workflow
  - the backend bucket and prefix Task builds `-backend-config` from come from `PROJECT_ID`/
    `STATE_BUCKET`, which Task reads from the environment automatically — set once in
    `deploy.yml`'s job-level `env:`, not hardcoded a second time as literal `-backend-config`
    strings

## 🔐 Pipeline stages and privileges

- ⚙️ `deploy.yml` runs five jobs in order: `plan-invoice-sync-prereqs` →
  `apply-invoice-sync-prereqs` (`artifact-registry` + `network` + `db-secrets`) →
  `build-and-push` (docker build/push) → `plan-invoice-sync` → `apply-invoice-sync`.
- 📝 Every stack goes through a separate plan job and apply job — the plan job runs
  `ACTION=plan task <name>` (`Taskfile.yml`'s `_tf` saves a `tfplan` file), uploads that file as
  a build artifact, and the apply job downloads it and runs `ACTION=apply task <name>`, which
  applies the saved plan directly (`terraform apply tfplan`, no re-plan). What gets applied is
  provably the same plan that was computed, not a fresh one against whatever state exists by
  the time apply runs.
- 🏷️ `invoice-sync`'s `image_tag` is fixed at its `plan` step (`-- -var image_tag=...`) — a
  saved plan file already has every variable baked in, so it can't be passed again at apply
  time.
- ♻️ `artifact-registry`, `network` and `db-secrets` run every time — idempotent, a no-op once
  they exist — so each self-heals on the next push if deleted, without a separate manual step.
- 🎭 This means the deploy SA needs, project-wide and unconditioned: nine custom roles (one per
  service group — Compute/Network, Load Balancer, Cloud Run, Artifact Registry, Secret Manager,
  Cloud KMS, Pub/Sub, Monitoring, Logging — plus IAM/service-account management), each holding
  only the specific permissions this repo's Terraform (and the pipeline's `docker push`/Cloud
  Run deploy-time image read) actually exercises, not a bundled predefined role.
  - 📄 See `modules/github-actions-wif/main.tf`'s `google_project_iam_custom_role.*` resources
    for the exact permission lists.
  - 📄 See CLAUDE.md's IAM section for the full rationale — why each is still
    project-wide/unconditioned despite the narrower permission sets, which services' async APIs
    need an `*.operations.get` grant on top of resource CRUD, and the confirmed IAM-Conditions
    gaps for Cloud Run/Artifact Registry/Pub-Sub.
- 🖐️ `enable-apis` is deliberately kept local-only, unlike `artifact-registry`/`network` — see
  CLAUDE.md's IAM section for why.

## 🧰 Usage

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

- 🌍 `PROJECT_ID` and `STATE_BUCKET` (used for every task's `-backend-config`) default to
  `yeti-504903` / `yeti-terraform-state-bucket` but can be overridden the same way `ACTION` is,
  via the environment: `PROJECT_ID=other-project STATE_BUCKET=other-bucket task invoice-sync`.
- 🏷️ `invoice-sync`'s `image_tag` has no default and must always be passed explicitly:

```bash
task invoice-sync -- -var image_tag=<git-sha>
```

## 🥾 Bootstrap

- 🔑 The GitHub Actions pipeline authenticates via Workload Identity Federation, but the pool,
  provider and deploy service account it authenticates as are themselves Terraform-managed —
  they can't exist before the first apply, and the pipeline can't authenticate before they
  exist.
- 🚫 `github-actions-wif` itself can't apply without APIs (`iam`, `sts`,
  `cloudresourcemanager`, ...) that this project doesn't enable by default.

See `docs/bootstrap-runbook.md` for the full step-by-step commands (including installing/
authenticating the GitHub CLI). Short version:

0. ✅ Apply `enable-apis` locally, with your own `gcloud` credentials — the pipeline never
   applies this stack (see CLAUDE.md's IAM section), so any newly-added API needs a re-run of
   this step:
   ```bash
   ACTION=apply task enable-apis
   ```
1. 🪪 Apply `github-actions-wif` locally, with your own `gcloud` credentials:
   ```bash
   ACTION=apply task github-actions-wif
   ```
2. 📋 Read its outputs and set them as GitHub repo variables (Settings → Secrets and variables →
   Actions → Variables): `WIF_PROVIDER` and `DEPLOY_SA_EMAIL`.
   ```bash
   terraform -chdir=live/github-actions-wif output -raw workload_identity_provider
   terraform -chdir=live/github-actions-wif output -raw service_account_email
   ```
3. 🚀 Push to `main` (or run `workflow_dispatch`) — the pipeline creates the runtime SA, grants
   it its own project roles and the deploy SA's actAs on it, and deploys `invoice-sync` end to
   end, all in one run.
4. 🔄 From then on, every push builds, pushes and deploys automatically:
   - no further local applies required, unless a new API is needed (re-run step 0)
   - `db-secrets` only creates the `db-password` secret *container* — the pipeline never writes
     a value to it, so add one out-of-band once, with your own credentials:
   ```bash
   gcloud secrets versions add db-password --project=yeti-504903 --data-file=<path-to-password-file>
   ```

## 🚨 Deployment failure alerting

- 👀 `modules/deployment-failure-alert` watches Cloud Run's own log line for a revision that
  never went healthy via a log-based Cloud Monitoring alert policy.
- 📨 It notifies two channels in parallel:
  - a Pub/Sub topic (`deployment-failures`, for any future automation that wants to subscribe)
  - an email address (`notification_email` in `.auto.tfvars`)
- ✔️ Terraform creates the email channel but can't verify it (Google requires a code sent to the
  actual inbox) — see `docs/bootstrap-runbook.md` for that one-time step and for forcing a test
  failure.
- 📄 See CLAUDE.md's "Deployment failure alerting" section for why the alert filter matches
  `run.googleapis.com/varlog/system` and not the more obvious-looking
  `protoPayload.status.message` (audit logs are excluded from the log bucket alerting evaluates).

## 🔒 Private Cloud Run behind a public load balancer

- 🚪 Cloud Run's `ingress` is `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` — the service's own
  `*.run.app` URL refuses direct requests, and `module.lb` (an external HTTP(S) load balancer,
  `modules/serverless-lb`) is the only path in.
- ➡️ Outbound (egress) traffic reaches private destinations through a Serverless VPC Access
  connector, on its own dedicated subnet in `live/network`'s own VPC (`10.50.0.0/28`, part of a
  reserved `10.50.0.0/24` block — see that stack's `.auto.tfvars`) — self-contained within this
  repo, not a dependency on `google-cloud-terraform`'s hub VPC.
- 🎛️ `vpc_egress` (`live/invoice-sync/.auto.tfvars`) controls whether only RFC1918 destinations
  (`PRIVATE_RANGES_ONLY`) or everything (`ALL_TRAFFIC`) routes through it.
- 🌐 No VPN is wired up — the load balancer is public. Add one later (or switch ingress to
  `INGRESS_TRAFFIC_INTERNAL_ONLY` and drop the load balancer) if the service needs to be
  VPN-only instead.

## 📦 App source

- 👋 `app/` is a placeholder Node.js "Hello, World!" server (`GET /` and `GET /healthz`), just
  enough to prove the pipeline end to end.
- 🔄 Swap in the real invoice-sync service without touching the `Dockerfile`, as long as it
  keeps listening on `$PORT` (8080 by default, matching `modules/cloud-run`'s `port` var).
