# CLAUDE.md

Rules for working on this repo's Terraform. These override default behavior.

## Networking

- VPCs and everything on them are private by default. The only thing ever exposed publicly is
  the load balancer in front of Cloud Run (`modules/serverless-lb`) — no public IPs, no
  `INGRESS_TRAFFIC_ALL` on Cloud Run, no public Cloud SQL, no `0.0.0.0/0` ingress firewall
  rules, unless the user explicitly asks for an exception and understands what it opens up.

## Module structure

- `live/*` root modules only compose modules (`module` blocks, `data` sources, variables,
  outputs) — no raw `resource` blocks. If a `live/` config needs a resource, add it to the
  module that owns the concern it belongs to (or a new module, if none fits) and expose
  whatever variable/output makes it configurable from `live/`, rather than declaring it inline.

## Variables

- `live/*` root module variables have no `default`. Every value a stack actually runs with
  lives in that stack's `.auto.tfvars`, which is the single source of truth — not a fallback
  baked into `variables.tf`, and not injected via `-var` from the Taskfile or a pipeline
  (`image_tag` is the one exception: it's a genuinely per-run value, not a stack config value,
  so it's always passed with `-var` instead of living in a static file).
  `terraform.tfvars.example` mirrors `.auto.tfvars` in full, since there's nothing to fall back
  on if a value is missing. This is about `live/`, not the reusable modules under `modules/` —
  those can keep sensible defaults (e.g. `modules/cloud-run`'s `cpu`, `memory`, `port`).

## Taskfile

- Every root Terraform module under `live/` gets a task in `Taskfile.yml` using the existing
  `_tf` pattern (`init` with `-backend-config bucket=`/`prefix=`, then `plan`/`apply`/`destroy`
  via `ACTION`). Don't hand-roll `terraform` invocations elsewhere (docs, scripts) when a task
  should exist instead.

## CI/CD

- Every pipeline authenticates to GCP with Workload Identity Federation
  (`google-github-actions/auth@v2` + `modules/github-actions-wif`), scoped to the specific
  GitHub repo via `attribute_condition`. Never a service account key file, never a broad WIF
  pool without a repo-scoped condition.
- Pipelines call `task <name>` (install via `arduino/setup-task`), never raw `terraform
  init`/`plan`/`apply`. The init/backend-config/apply sequence lives once, in `Taskfile.yml`'s
  `_tf` task — a pipeline hand-rolling the same commands is exactly the duplication the Taskfile
  rule above exists to prevent, just one layer further out.
- The backend bucket/prefix a pipeline needs are set via `PROJECT_ID`/`STATE_BUCKET` in the
  job's environment, which Task's own variable resolution picks up automatically — the same
  mechanism already relied on for `ACTION` (`ACTION=apply task invoice-sync`). Don't hardcode a
  second literal `-backend-config` string in the workflow. This can't be done via `TF_VAR_*`
  instead — that prefix only applies to declared root-module variables, never to backend
  blocks, which don't accept variables at all.

## IAM

- Principle of least privilege, always: prefer the narrowest role that does the job
  (resource-level binding over project-level, a custom/predefined role over `roles/editor` or
  `roles/owner`) and grant it only to the specific service account or member that needs it.
  Default to project-scoped IAM only when the resource doesn't support a narrower binding.
- Before granting anything that reads as a privilege escalation — `roles/owner`/`roles/editor`,
  `roles/iam.securityAdmin`, broad `serviceAccountTokenCreator`/`serviceAccountUser` on many
  accounts, project-wide instead of resource-scoped bindings, wildcard WIF attribute
  conditions, service account key file creation — stop and ask the user why it's needed instead
  of just applying it. Propose the narrower alternative that would satisfy the actual use case
  first.
- IAM bindings are always additive (`google_*_iam_member`), never authoritative
  (`google_*_iam_binding`/`_policy`). Authoritative resources overwrite the entire policy for a
  role (or resource), silently dropping any binding not declared in that exact Terraform config
  — including ones added by hand, by another stack, or by a module using a different mode.
  `terraform-google-modules/iam`'s submodules default to additive and are fine to use where
  that mode actually works; if the only way to make a binding fit the module is switching it to
  `mode = "authoritative"`, don't — write the raw `_member` resource instead, even though the
  module has that escape hatch.
- Never grant a project-wide role just because the resource it should be scoped to doesn't
  exist yet (e.g. a deploy identity's `roles/run.admin` before the Cloud Run service it deploys
  exists). Use a `google_project_iam_member` with a `condition` block instead — the resource
  name (`projects/<id>/locations/<region>/services/<name>`, `.../repositories/<id>`, etc.) is
  deterministic and doesn't require the target resource to exist, so the grant can be scoped
  from the start (see `modules/github-actions-wif`'s `run_admin_scoped` /
  `artifactregistry_admin_scoped`). Same for Secret Manager access: grant per-secret via
  `google_secret_manager_secret_iam_member`, never a project-wide
  `roles/secretmanager.secretAccessor` (see `modules/cloud-run`'s `secret_accessor_secrets`,
  which defaults to zero grants).
- Before adding a role to a service account's blanket project-level role list, check whether a
  resource-scoped binding for that same permission already exists elsewhere in the stack. Don't
  grant the same effective access twice at different scopes — the broader one just widens blast
  radius for no benefit.
- `roles/serviceusage.serviceUsageAdmin` (`modules/github-actions-wif`'s
  `serviceusage_admin_scoped`, needed for the pipeline to apply `enable-apis`) is the one grant
  in this repo that can't be scoped to a single resource the way everything above can — service
  enablement has no per-API resource the way a Cloud Run service or AR repo does. The narrowest
  available control is an IAM Condition listing the exact service names `enable_apis_services`
  declares (must match `live/enable-apis`'s own `services` list). This was an explicit,
  discussed trade-off (see README's "Pipeline stages and privileges"), not a default — don't
  extend this pattern to other roles just because it exists here, and don't widen the condition
  to more services than `enable-apis` actually needs without the same discussion.
- Creating (not just writing to) an Artifact Registry repo needs `roles/artifactregistry.admin`
  or `.repoAdmin` — `.writer` only grants push/pull to a repo that already exists, it has no
  `repositories.create`/`.delete`. Don't reach for `.writer` when the caller is the one
  provisioning the repo.
