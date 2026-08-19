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

## Comments

- No comments in `.tf` files — not even to explain a non-obvious IAM/permissions choice.
  `CLAUDE.md` is the single source of truth for the *why* behind this repo's Terraform
  (rationale for custom roles, unconditioned project-wide grants, confirmed IAM Conditions
  gaps, etc. all live in the IAM section below, not inline). This applies retroactively too:
  when a file accumulates comments during a change, strip them at the end rather than leaving
  them for "context," and fold anything genuinely load-bearing into this file instead.

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
- `live/enable-apis` and `live/github-actions-wif` are the **only** stacks ever applied
  manually, with the operator's own credentials — `github-actions-wif` because it has to exist
  before the pipeline can authenticate at all, `enable-apis` because `roles/serviceusage.*` has
  no way to scope down to individual services (see the IAM section for both). Every other
  `live/*` stack (`artifact-registry`, `network`, `db-secrets`, `invoice-sync`, and any new
  stack added later) is applied by the pipeline, in `deploy.yml`, via its own `task <name>` —
  never left as a manual/bootstrap-only step. If a new stack seems to need a manual step because
  `github-deployer` doesn't yet hold the permission its resources require, the fix is to grant
  `github-deployer` that permission (via `modules/github-actions-wif`'s `deploy_sa_roles`,
  scoped as narrowly as the resource type allows — see the IAM section), not to carve out
  another bootstrap-only stack. Any such grant that's project-wide and unconditioned still goes
  through the stop-and-ask process in the IAM section first.
- Every pipeline-applied stack goes through separate plan and apply jobs in `deploy.yml`, never
  a single `ACTION=apply` step — `ACTION=plan task <name>` first, saving a `tfplan` file
  (`Taskfile.yml`'s `_tf`, when `ACTION=plan`, always runs `terraform plan -out=tfplan`), then
  `actions/upload-artifact`/`download-artifact` to carry that exact file into a separate `needs:`
  job, then `ACTION=apply task <name>` there — `_tf`'s apply branch runs `terraform apply
  tfplan` (no re-plan, no `-var`) whenever that file is present, only falling back to a plain
  `terraform apply -auto-approve` when it isn't (the local, no-artifact path — `ACTION=apply
  task <name>` run standalone still works exactly as before). This means what gets applied is
  provably the same plan a human (or a future required-review gate) could inspect, not a fresh
  plan computed at apply time against whatever state happens to exist by then. Variables like
  `invoice-sync`'s `image_tag` must be passed at the `plan` step (`ACTION=plan task invoice-sync
  -- -var image_tag=...`) — a saved plan file already fixes every variable, and `terraform apply
  <planfile>` rejects `-var` outright.

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
- **`github-deployer`'s project-level roles are custom roles, one per service group, not
  predefined roles** (`modules/github-actions-wif`'s `google_project_iam_custom_role.*`,
  wired up via the `deploy_sa_roles` local). Predefined roles like `run.admin` (18
  permissions), `artifactregistry.admin` (~50), `compute.networkAdmin`/`.securityAdmin`/
  `.loadBalancerAdmin` (~1,586 combined), `secretmanager.admin` (~15), `cloudkms.admin`
  (~40), `pubsub.admin` (~15), `logging.configWriter` (60) all bundle in capabilities this
  repo never exercises (VPNs/interconnects/GKE networking, AR package/tag management, Secret
  Manager version lifecycle, Pub/Sub subscriptions/schemas/snapshots, 59 of
  `logging.configWriter`'s 60 permissions — this repo has zero `google_logging_*` resources).
  Each custom role's permission list was derived from `gcloud iam list-testable-permissions`
  against this project's actual deployed resources, not inferred from predefined-role
  membership — that shortcut is what produced an earlier, much larger draft (~1,447
  permissions) of this same change. Total across all nine custom roles is roughly 120-130
  permissions. When a `live/` stack starts managing a new resource type, add the specific
  permissions it needs to the relevant custom role (or a new one) — don't reach for a
  predefined role as a shortcut, and don't add permissions "just in case" without a resource
  in this repo that actually needs them (the one deliberate exception:
  `githubDeployerLoadBalancer` includes `compute.sslCertificates.*` pre-emptively, since
  `modules/serverless-lb`'s managed-cert code path already exists and is one `lb_domains`
  tfvars edit away from being live).
- **When a service's mutating API is asynchronous (returns a long-running Operation that
  Terraform polls), the custom role needs an `*.operations.get` permission too, on top of the
  resource CRUD permissions** — easy to miss because it's not a permission on the resource
  being managed at all. Found the hard way on `run.services.update`: `terraform apply` created/
  updated the Cloud Run service fine, then 403'd on `run.operations.get` while polling the
  operation it had just kicked off. `googleapi`/provider errors for this failure mode name the
  *operation's* resource path (`.../operations/<uuid>`), not the service/resource path — don't
  mistake it for a missing permission on the resource itself. `githubDeployerCloudRun` has
  `run.operations.get`; `githubDeployerComputeNetwork`/`githubDeployerLoadBalancer` have
  `compute.globalOperations.get`/`compute.regionOperations.get` (Compute Engine's mutating APIs
  are async too) plus `vpcaccess.operations.get` (VPC connector creation is its own,
  separately-permissioned async API, not covered by the `compute.*` operations permissions).
  No `zoneOperations.get` — nothing this repo manages is zone-scoped. Secret Manager, Pub/Sub,
  Cloud KMS, Cloud Monitoring/Logging, and IAM service-account management are all confirmed
  synchronous in this repo's actual usage (their resources were created successfully without
  any `*.operations.get` grant) — don't add operations permissions for those preemptively, but
  when adding a *new* custom role for a service not yet covered here, check whether its
  mutating calls return an Operation before assuming resource-CRUD permissions alone are
  enough.
- Creating (not just writing to) an Artifact Registry repo needs
  `artifactregistry.repositories.create`/`.delete` specifically — confirmed via `gcloud iam
  roles describe`: the predefined `.repoAdmin` role has neither at all (it's content/IAM
  management on a repo that already exists), and `.writer` only grants push/pull. Don't reach
  for either when the caller is the one provisioning the repo.
- `githubDeployerArtifactRegistry` also includes `artifactregistry.repositories.uploadArtifacts`
  — needed for `deploy.yml`'s `docker push` step, not by any `google_artifact_registry_*`
  Terraform resource. The permission audit that produced the nine custom roles only enumerated
  what Terraform itself manages; plain `gcloud`/`docker` CLI calls the pipeline makes as
  `github-deployer` outside `terraform apply` are a separate surface and can be missed the same
  way this one was — check `.github/workflows/*.yml` and `Taskfile.yml` for non-Terraform
  `gcloud`/`docker` invocations too when auditing what a custom role needs, not just the
  `live/`/`modules/` resource graph.
- `githubDeployerArtifactRegistry` also includes `artifactregistry.repositories.downloadArtifacts`
  — confirmed the hard way: `terraform apply`'s `run.services.update` call 403'd without it. Cloud
  Run validates at deploy time that the *caller* (`github-deployer`, not just the runtime service
  agent) can read the image being deployed — an initial assumption that the runtime service
  agent's own pull access would be enough, and that the deploy SA only ever pushes, was wrong.
  Don't assume a predefined role's push/pull split (`.writer` grants both) maps cleanly onto
  "the deploy SA only pushes" just because that's the only *direct* Artifact Registry action it
  performs — Cloud Run's own deploy-time checks add a second, indirect need for read access.
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
  A `resource.name`-scoped condition looked correct (it even matched `run.services.create`'s
  own parent-location requirement) and still denied every request, the exact same silent-no-op
  failure mode as Artifact Registry below. `githubDeployerCloudRun` is granted project-wide,
  unconditioned, for this reason.
- Artifact Registry has no `resource.name`/`resource.type`-based IAM Conditions at all — its only
  documented conditional-access mechanism is Resource Manager tags, a different feature. A
  `resource.name`-scoped condition looked like it matched (the 403's own error detail showed
  the exact resource name the condition checked for) and still denied every request, because
  the condition attribute isn't evaluated for this resource type in the first place —
  confirmed against Google's Artifact Registry access-control docs, not assumed.
  `githubDeployerArtifactRegistry` is granted project-wide, unconditioned, for this reason —
  don't reintroduce a `resource.name` condition on it expecting it to narrow anything.
- `githubDeployerComputeNetwork` (VPC/subnet/firewall/router/VPC-access-connector, needed for
  the pipeline to apply `live/network`) and `githubDeployerLoadBalancer` (global external
  HTTP(S) LB resources, needed for `../invoice-sync`'s `modules/serverless-lb`) are granted
  project-wide, unconditioned — a discussed, accepted trade-off, not a default. This is a
  materially bigger blast radius than every other grant in this repo: `yeti-504903` also hosts
  the `google-cloud-terraform` repo's hub/dev VPCs, GKE networking and VPN, so this lets the
  deploy SA touch all of that, not just this repo's own network/LB resources. Compute Engine's
  IAM Conditions support isn't confirmed for these resource types specifically (Google's
  supported-services list only says "Compute Engine" broadly), and given Artifact Registry
  above already showed a condition that looks syntactically correct can silently never match,
  an unverified condition here was judged not worth risking on infra with this much more to
  lose if guessed wrong. Narrowing the *permission count* for these two roles (from
  `compute.networkAdmin`/`.securityAdmin`/`.loadBalancerAdmin`'s ~1,586 combined permissions
  down to ~70) doesn't change this trade-off — it's still project-wide, just fewer permission
  types. If a narrower binding is ever confirmed to actually work at runtime (not just accepted
  by `terraform apply`), prefer it.
- `github-deployer` holds `githubDeployerIamServiceAccountMgmt`
  (`iam.serviceAccounts.{create,get,list,update,getIamPolicy,setIamPolicy}`,
  `resourcemanager.projects.{getIamPolicy,setIamPolicy}`), project-wide, so `../invoice-sync`
  can create the Cloud Run runtime SA, grant it its own `roles/logging.logWriter`/
  `roles/cloudtrace.agent` project roles, and grant itself `roles/iam.serviceAccountUser`
  (actAs) on it — all in the same pipeline run, no separate bootstrap-only stack. This is a
  deliberate, discussed trade-off, not a default, and narrowing the permission list (versus the
  predefined `iam.serviceAccountAdmin`/`resourcemanager.projectIamAdmin` this replaced) doesn't
  change the underlying risk: `setIamPolicy` at the project or service-account level is
  inherently that broad regardless of which role wraps it — it can still rewrite IAM policy for
  *any* member/role at the project level, or set IAM policy on *every* service account in the
  project, not just the one `invoice-sync` creates. Confirmed via `gcloud iam roles describe`,
  not assumed. The narrower alternative — a one-time, manually-applied bootstrap stack granting
  a scoped `iam.serviceAccountAdmin` on just the runtime SA, and leaving the project roles as a
  manual step — was proposed first and explicitly rejected in favor of a fully pipeline-driven
  deploy, since only `enable-apis` and `github-actions-wif` are allowed to stay manual (see
  CI/CD section). Don't revert to the narrower alternative without the same explicit
  discussion.
- `github-deployer` holds `githubDeployerSecretManager`
  (`secretmanager.secrets.{create,get,update,getIamPolicy,setIamPolicy}`), project-wide, so
  `../db-secrets` can create the `db-password` secret and manage IAM policy on it (and any
  other secret this repo adds later) entirely from the pipeline. Same class of gap as
  `githubDeployerIamServiceAccountMgmt` above: `secretmanager.secrets.create` is authorized
  against the project (the parent), not the not-yet-existing secret, so it can't be scoped to
  one secret in advance. Secret Manager is confirmed to support IAM Conditions (see the
  `google_secret_manager_secret_iam_member` bullet above) — a `resource.name` condition scoped
  to just `db-password` for the `getIamPolicy`/`setIamPolicy` half of this role is a plausible
  future narrowing, but hasn't been tried/verified here yet, and Pub/Sub's identical-looking
  condition attempt turned out to be a silent no-op (see below) — verify in isolation before
  trusting it in the real pipeline. The narrower alternative to the current unconditioned
  grant — `db-secrets` as a manually-applied bootstrap stack granting a scoped
  `secretmanager.admin` on just the one secret it creates (via
  `modules/secret-manager-secret`'s `admin_members`, still available for a future caller that
  needs it) — was the original design and was superseded once the "only `enable-apis` and
  `github-actions-wif` are manual" rule was adopted. Runtime access to secrets is unaffected by
  this: the Cloud Run runtime SA still only gets `roles/secretmanager.secretAccessor` scoped
  per-secret via `modules/cloud-run`'s `secret_accessor_secrets`, never a project-wide role.
- `github-deployer` holds `githubDeployerPubsub`
  (`pubsub.topics.{create,get,update,getIamPolicy,setIamPolicy}`), project-wide, unconditioned
  — covers both `../invoice-sync`'s `deployment_alert` module creating its Pub/Sub topic, and
  `../db-secrets` granting the Secret Manager service agent publish rights on the
  `db-password-rotation` topic it creates (`modules/secret-manager-secret`'s
  `google_pubsub_topic_iam_member.secretmanager_can_publish_rotation`), which needs
  `pubsub.topics.setIamPolicy`/`getIamPolicy` — permissions the predefined `pubsub.editor`/
  `.publisher` roles both lack. `topics.publish` itself isn't included — the Secret Manager
  service agent is what publishes rotation notifications, never `github-deployer`. A
  `resource.name` condition scoped to just the `db-password-rotation` topic was tried first
  (same reasoning as the Secret Manager case above: the topic name is deterministic even
  before the topic exists) but confirmed to be a silent no-op — Pub/Sub Topic doesn't evaluate
  `resource.name` conditions, the same failure mode already confirmed for Cloud Run and
  Artifact Registry above. Confirmed with the user before applying.
- `github-deployer` holds `githubDeployerKms`
  (`cloudkms.keyRings.{create,get,list,getIamPolicy}`,
  `cloudkms.cryptoKeys.{create,get,update,getIamPolicy,setIamPolicy}`), project-wide, so
  `../db-secrets` (via `modules/secret-manager-secret`) can create the CMEK key ring/key
  protecting the `db-password` secret. No `cryptoKeys.delete` — the key has
  `lifecycle.prevent_destroy = true` and can't be truly deleted in GCP regardless. Same class
  of gap as `githubDeployerSecretManager` above: `keyRings.create`/`cryptoKeys.create` are
  authorized against the project/location, not the not-yet-existing key ring, so this can't be
  scoped to just this one key ring in advance, and Cloud KMS's IAM Conditions support for
  `KeyRing`/`CryptoKey` isn't confirmed — same unverified-condition risk already documented for
  `githubDeployerArtifactRegistry`/`githubDeployerCloudRun` above. A discussed, accepted
  trade-off, confirmed with the user before applying: the deploy SA can manage any KMS key in
  the project, not just this one. Runtime decryption is unaffected by this — Secret Manager's
  own service identity (`google_project_service_identity` in `modules/secret-manager-secret`)
  does the encrypt/decrypt on behalf of whoever holds `secretAccessor`, so the Cloud Run
  runtime SA never needs any direct KMS grant of its own.
- `github-deployer` holds `githubDeployerMonitoring`
  (`monitoring.notificationChannels.{create,get,update,delete,list}`,
  `monitoring.alertPolicies.{create,get,update,delete,list}`) and `githubDeployerLogging`
  (`logging.notificationRules.{create,get,update,delete,list}`), both project-wide, for
  `../invoice-sync`'s `modules/deployment-failure-alert` (two notification channels — pubsub
  and email — plus one alert policy). The logging permissions exist only because the alert
  policy uses `condition_matched_log`, which routes creation through Cloud Logging's
  log-based-alerting API and specifically needs `logging.notificationRules.create` — no
  predefined role narrower than `logging.configWriter` (60 permissions, 59 unused) includes
  it, and nothing else in this repo touches Cloud Logging.

## Deployment failure alerting

- `modules/deployment-failure-alert`'s `condition_matched_log` filter must match a log entry
  that actually reaches the project's `_Default` log bucket — Cloud Monitoring's log-based
  alerting only evaluates logs routed there, confirmed the hard way: a filter on
  `protoPayload.status.message:"Ready condition status changed to False"` never fired a single
  incident despite `gcloud logging read` confirming matching entries existed, because that
  message lives on a `cloudaudit.googleapis.com/system_event` audit log entry, and this
  project's `_Default` sink (GCP's own default project configuration, not something this repo
  set up) explicitly excludes all `cloudaudit.googleapis.com/*` logs
  (`gcloud logging sinks describe _Default`) — they route only to `_Required` instead. No
  filter text on an audit-log-only field can ever match, regardless of correctness, the same
  silent-no-op shape as the IAM Conditions gaps above but on a completely different GCP
  subsystem. Before writing or changing a `condition_matched_log` filter, check the target log
  entry's `logName` (`gcloud logging read '<filter>' --format='value(logName)'`) — anything
  under `cloudaudit.googleapis.com/{activity,system_event,access_transparency}` (or
  `externalaudit.googleapis.com/*`) is excluded from `_Default` by GCP's default sink config
  and cannot be used. The current filter instead matches `severity=ERROR` on
  `logName="run.googleapis.com/varlog/system"` — Cloud Run's own system log stream, a regular
  (non-audit) log that does reach `_Default`, and empirically carries a clean, low-noise ERROR
  signal for revision/instance startup failures (confirmed against 2 days of this project's
  actual log history: every `ERROR` entry there was a genuine startup-probe failure, zero
  false positives).
- `modules/deployment-failure-alert` is invoked from `live/invoice-sync/main.tf` with
  `service_name = var.service_name`, not `module.cloud_run.service_name` — deliberately, even
  though both resolve to the same value. Passing the module output instead creates a real
  dependency edge in Terraform's graph (`deployment_alert` → `cloud_run`), and Terraform aborts
  applying a resource's dependents when the resource it depends on fails to apply. Since a
  failed Cloud Run deploy is exactly the condition this alerting exists to catch, that coupling
  meant an alert-policy fix could never reach GCP on the same push that also contains a broken
  revision — confirmed the hard way: a corrected filter sat committed on `main` for three
  pipeline runs, all of which failed on the Cloud Run update before ever reaching the
  now-unrelated alert-policy resource, because the graph made them falsely appear related. Keep
  passing `var.service_name` (the static input both modules are ultimately built from) to
  anything alerting-related — don't reintroduce a `module.cloud_run.*` output reference here
  even if it's more "correct" in the sense of tracking the real deployed value, since
  `service_name` itself never differs from `var.service_name` in this repo. `module.lb`'s
  `cloud_run_service_name = module.cloud_run.service_name` is a different, legitimate case —
  the load balancer's backend NEG genuinely needs the Cloud Run resource to exist first — and
  should stay as a module-output reference.
- The email notification channel needs a one-time manual verification step Terraform cannot
  perform (a code sent to the actual inbox) — see `docs/bootstrap-runbook.md` steps 7-8 for the
  exact commands (gcloud has no `send-verification-code`/`verify` subcommand; both need a raw
  REST call). Re-verify whenever the channel is recreated, e.g. a `notification_email` change
  that Terraform can't do as an in-place update.
