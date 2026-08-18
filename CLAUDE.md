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
