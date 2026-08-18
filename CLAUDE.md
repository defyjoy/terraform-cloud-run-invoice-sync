# CLAUDE.md

Rules for working on this repo's Terraform. These override default behavior.

## Networking

- VPCs and everything on them are private by default. The only thing ever exposed publicly is
  the load balancer in front of Cloud Run (`modules/serverless-lb`) — no public IPs, no
  `INGRESS_TRAFFIC_ALL` on Cloud Run, no public Cloud SQL, no `0.0.0.0/0` ingress firewall
  rules, unless the user explicitly asks for an exception and understands what it opens up.
- `live/network` (directly composing `terraform-google-modules/network/google` and its
  `vpc-serverless-connector-beta`/`firewall-rules` submodules, no wrapper module of our own) is
  this repo's own VPC — a dedicated network with a
  Serverless VPC Access connector on a private /28 subnet, which Cloud Run attaches to via
  `vpc_access.connector`. This project (`yeti-504903`) also hosts the `google-cloud-terraform`
  repo's hub/dev VPCs; `live/network` does not touch them and shouldn't grow to.

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
- Prefer a `google_project_iam_member` with a `condition` block over a project-wide grant when
  the target resource doesn't exist yet — the resource name
  (`projects/<id>/locations/<region>/services/<name>`, `.../repositories/<id>`, etc.) is
  deterministic and doesn't require the target resource to exist, so the grant can in principle
  be scoped from the start. But verify the resource type actually supports IAM Conditions
  before relying on this — Cloud Run and Artifact Registry both don't (see below), and a
  condition that isn't evaluated at all looks identical, at `terraform apply` time, to one that
  works. Where it does work (Secret Manager, confirmed): grant per-secret via
  `google_secret_manager_secret_iam_member`, never a project-wide
  `roles/secretmanager.secretAccessor` (see `modules/cloud-run`'s `secret_accessor_secrets`,
  which defaults to zero grants).
- Before adding a role to a service account's blanket project-level role list, check whether a
  resource-scoped binding for that same permission already exists elsewhere in the stack. Don't
  grant the same effective access twice at different scopes — the broader one just widens blast
  radius for no benefit.
- `enable-apis` is bootstrap-only, applied locally with the operator's own credentials, and the
  pipeline never touches it — `roles/serviceusage.*` has no way to scope down to individual
  services (`serviceusage.googleapis.com/Service` resource names use the project *number*, not
  the project ID, which broke an earlier attempt at an IAM-Condition-scoped
  `serviceUsageAdmin` grant; `services.list` also can't be scoped at all, since it's authorized
  against the whole project container). Granting the deploy SA project-wide `serviceUsageAdmin`
  just to let the pipeline self-heal newly-added APIs isn't worth that blast radius — if a new
  API is needed, add it to `live/enable-apis` and apply it locally, the same as any other
  bootstrap change.
- Creating (not just writing to) an Artifact Registry repo needs `roles/artifactregistry.admin`
  specifically — confirmed via `gcloud iam roles describe`: `.repoAdmin` has no
  `repositories.create`/`.delete` at all (it's content/IAM management on a repo that already
  exists), and `.writer` only grants push/pull. Don't reach for either when the caller is the
  one provisioning the repo.
- A `create` call for a resource that doesn't exist yet is generally authorized against the
  *parent* (its location), not the resource's own `resource.name` — a single
  `resource.name == <child>` check would not be enough to let the deploy SA provision the
  resource in the first place, on a service whose IAM Conditions actually support
  `resource.name`; the condition would need an `||` branch matching the parent location too.
  Same class of gap as `services.list` above. Neither Cloud Run nor Artifact Registry support
  `resource.name` conditions at all (see below), so this repo has no live example of the
  pattern actually working — don't assume it does on a new service without checking Google's
  own "resource types with conditional role bindings" reference first.
- **Cloud Run's `Service` resource does not support IAM Conditions at all** — confirmed against
  Google's Config Connector docs ("Supports IAM Conditions: No" for `RunService`), not assumed.
  A `resource.name`-scoped condition on `run_admin` looked correct (it even matched
  `run.services.create`'s own parent-location requirement) and still denied every request, the
  exact same silent-no-op failure mode as Artifact Registry below. `run_admin` is granted
  project-wide, unconditioned, for this reason.
- Artifact Registry has no `resource.name`/`resource.type`-based IAM Conditions at all — its only
  documented conditional-access mechanism is Resource Manager tags, a different feature. A
  `resource.name`-scoped condition on `artifactregistry_admin` looked like it matched (the 403's
  own error detail showed the exact resource name the condition checked for) and still denied
  every request, because the condition attribute isn't evaluated for this resource type in the
  first place — confirmed against Google's Artifact Registry access-control docs, not assumed.
  `artifactregistry_admin` is granted project-wide, unconditioned, for this reason — don't
  reintroduce a `resource.name` condition on it expecting it to narrow anything.
- `roles/compute.networkAdmin`, `roles/compute.securityAdmin` and `roles/vpcaccess.admin`
  (`modules/github-actions-wif`'s `compute_network_admin`/`compute_security_admin`/
  `vpcaccess_admin`, needed for the pipeline to apply `live/network`) are granted project-wide,
  unconditioned — a discussed, accepted trade-off, not a default. This is a materially bigger
  blast radius than every other grant in this repo: `yeti-504903` also hosts the
  `google-cloud-terraform` repo's hub/dev VPCs, GKE networking and VPN, so this lets the deploy
  SA touch all of that, not just `live/network`'s own resources. Compute Engine's IAM
  Conditions support isn't confirmed for networks/subnetworks/routers/firewalls specifically
  (Google's supported-services list only says "Compute Engine" broadly), and given
  `artifactregistry_admin` above already showed a condition that looks syntactically correct
  can silently never match, an unverified condition here was judged not worth risking on infra
  with this much more to lose if guessed wrong. If a narrower binding for these roles is ever
  confirmed to actually work at runtime (not just accepted by `terraform apply`), prefer it.
- `live/invoice-sync-runtime-sa` (Cloud Run's runtime SA, its `roles/logging.logWriter`/
  `roles/cloudtrace.agent` project roles, and the deploy SA's `roles/iam.serviceAccountUser`
  grant on it) is bootstrap-only, applied locally, and never touched by the pipeline — same
  reasoning as `enable-apis`, one level further: granting *any* role to a service account (via
  `google_project_iam_member` for the project roles, or `google_service_account_iam_member` for
  the actAs grant) requires `resourcemanager.projects.setIamPolicy` or
  `iam.serviceAccounts.setIamPolicy`, and neither can be scoped down to "only this one grant" —
  `roles/resourcemanager.projectIamAdmin` is Google's own narrowest role for the former, and it
  grants the ability to rewrite the *entire* project's IAM policy (any role, to any member,
  including granting itself Owner). Confirmed via `gcloud iam roles describe`, not assumed. This
  was an explicit, discussed trade-off — the alternative (granting the deploy SA
  `projectIamAdmin` + `iam.serviceAccountAdmin`) was rejected as too large a blast radius on a
  shared project. `live/invoice-sync` only ever references the runtime SA by its deterministic
  email (`create_service_account = false`), never creates or grants it anything itself.
- `roles/pubsub.editor` (`modules/github-actions-wif`'s `pubsub_editor`), for
  `../invoice-sync`'s `deployment_alert` module to create its Pub/Sub topic. Deliberately not
  `.admin`: `.editor` grants `topics.create`/`get`/`list`/`update`/`delete`/`publish` but not
  `setIamPolicy` on topics, which `.admin` also grants.
