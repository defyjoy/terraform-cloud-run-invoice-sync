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

## 7. Verify the deployment-failure-alert email channel

Terraform creates the email notification channel (`modules/deployment-failure-alert`) but
cannot verify it — Google requires a code sent to the actual inbox, and gcloud has no
`send-verification-code`/`verify` subcommand, so this is a one-time manual REST call. Skip this
and the channel silently drops every notification with no error anywhere (alert policy still
shows `enabled: true`, no Terraform/pipeline failure).

```bash
CHANNEL=$(gcloud alpha monitoring channels list --project=yeti-504903 \
  --filter='displayName:"deployment failures (email)"' --format='value(name)')

TOKEN=$(gcloud auth print-access-token)

# 1. Send the code — lands in the address configured as notification_email
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  "https://monitoring.googleapis.com/v3/${CHANNEL}:sendVerificationCode" -d '{}'

# 2. Verify with the code from that email
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  "https://monitoring.googleapis.com/v3/${CHANNEL}:verify" -d '{"code":"<code-from-email>"}'

# 3. Confirm
gcloud alpha monitoring channels describe "$CHANNEL" --format='value(verificationStatus)'
# should print VERIFIED
```

Re-run whenever the channel is recreated (e.g. `terraform destroy`/`apply` on `live/invoice-sync`,
or a `notification_email` change — Terraform's `google_monitoring_notification_channel` replaces
the channel on some field changes, resetting verification).

## 8. Force a test deployment failure

Exercises the alert end to end without touching Terraform-managed resources — see
`live/invoice-sync/variables.tf`'s `expected_db_password` and `app/server.js`'s `/readyz`.

```bash
# Break it: set db-password to something other than expected_db_password
# (live/invoice-sync/.auto.tfvars)
gcloud secrets versions add db-password --project=yeti-504903 \
  --data-file=<(printf '%s' "deliberately-wrong-value")

# Push any commit to main to deploy a new revision — /readyz will 503 forever, the
# revision never becomes Ready, and the alert (once its channel is verified, step 7) fires.

# Fix it: restore the real value so the next deploy succeeds
gcloud secrets versions add db-password --project=yeti-504903 \
  --data-file=<(printf '%s' "invoice-sync-test-password")
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

Confirm the email notification channel is verified:

```bash
gcloud alpha monitoring channels list --project=yeti-504903 \
  --filter='displayName:"deployment failures (email)"' --format='value(verificationStatus)'
```
