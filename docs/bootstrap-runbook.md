# Bootstrap runbook

One-liners for the manual steps that have to happen outside Terraform/the pipeline, in order.

## 1. Enable Cloud Resource Manager (once, before anything else)

`google_project_service` goes through the Service Usage API, which itself needs Cloud Resource
Manager enabled to authorize the call — it can't be the thing that enables itself, and the
deploy SA can't do this either (same bootstrap problem, one layer deeper).

```bash
gcloud services enable cloudresourcemanager.googleapis.com --project=yeti-504903
```

## 2. Apply `enable-apis` locally

The pipeline never applies this stack (`roles/serviceusage.*` can't be scoped to individual
services — see CLAUDE.md's IAM section), so re-run this step by hand whenever a new API is added.

```bash
ACTION=apply task enable-apis
```

## 3. Apply `github-actions-wif` locally

```bash
ACTION=apply task github-actions-wif
```

## 4. Apply `invoice-sync-runtime-sa` locally

The pipeline never applies this stack either (granting roles to a service account needs
project-wide or service-account-wide IAM-editing power that can't be scoped down — see
CLAUDE.md's IAM section), so re-run this step by hand whenever the runtime SA's roles change.

```bash
ACTION=apply task invoice-sync-runtime-sa
```

## 5. Set the pipeline's repo variables from its outputs

```bash
gh variable set WIF_PROVIDER --body "$(terraform -chdir=live/github-actions-wif output -raw workload_identity_provider)"
gh variable set DEPLOY_SA_EMAIL --body "$(terraform -chdir=live/github-actions-wif output -raw service_account_email)"
```

## Checks

Confirm an API is enabled:

```bash
gcloud services list --enabled --project=yeti-504903 --format="value(config.name)" | grep <api>
```

Confirm the deploy SA's current IAM bindings:

```bash
gcloud projects get-iam-policy yeti-504903 --flatten="bindings[].members" --filter="bindings.members:github-deployer" --format="table(bindings.role,bindings.condition.title)"
```

Confirm the repo variables the pipeline reads:

```bash
gh variable list
```
