# Bootstrap runbook

One-liners for the manual steps that have to happen outside Terraform/the pipeline, in order.
Only `enable-apis` and `github-actions-wif` are ever applied by hand — every other `live/*`
stack is applied by the pipeline (see CLAUDE.md's CI/CD section).

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

## 4. Set the pipeline's repo variables from github-actions-wif's outputs

```bash
gh variable set WIF_PROVIDER --body "$(terraform -chdir=live/github-actions-wif output -raw workload_identity_provider)"
gh variable set DEPLOY_SA_EMAIL --body "$(terraform -chdir=live/github-actions-wif output -raw service_account_email)"
```

## 5. Trigger the pipeline

Creates the runtime SA, grants it its own project roles and the deploy SA's actAs on it,
creates the `db-password` secret container, and deploys `invoice-sync` end to end, all in one
run.

```bash
git commit --allow-empty -m "bootstrap: trigger first pipeline run" && git push
```

## 6. Add the db-password secret value

`db-secrets` only creates the secret container — the pipeline never writes a value to it (so
the value never lands in Terraform state). Add one out-of-band, with your own credentials —
`--data-file=-` reads the value from stdin instead of a file on disk, so it never touches shell
history either:

```bash
echo -n "<the actual db password>" | gcloud secrets versions add db-password --project=yeti-504903 --data-file=-
```

Or from a file (e.g. one already used to seed the database itself):

```bash
gcloud secrets versions add db-password --project=yeti-504903 --data-file=./db-password.txt
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
