# Bootstrap runbook

One-liners for the manual steps that have to happen outside Terraform/the pipeline, in order.
Only `enable-apis` and `github-actions-wif` are ever applied by hand — every other `live/*`
stack is applied by the pipeline (see CLAUDE.md's CI/CD section).

## 1. Enable Cloud Resource Manager (once, before anything else)

- `google_project_service` goes through the Service Usage API, which itself needs Cloud
  Resource Manager enabled to authorize the call — it can't be the thing that enables itself.
- The deploy SA can't do this either (same bootstrap problem, one layer deeper).

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

## 4. Install and authenticate the GitHub CLI

- Only needed once per machine.
- Step 5 uses `gh variable set` to reach the repo's Settings → Secrets and variables → Actions
  page without leaving the terminal.

```bash
# macOS
brew install gh

# Debian/Ubuntu
(type -p wget >/dev/null || sudo apt install wget -y) \
  && sudo mkdir -p -m 755 /etc/apt/keyrings \
  && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
  && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && sudo apt update && sudo apt install gh -y
```

```bash
gh auth login
```

- Interactive — pick `GitHub.com`, `HTTPS`, and browser-based login.
- Needs `repo` scope (the default) so `gh variable set` can write to this repo's Actions
  variables.

Confirm it worked:

```bash
gh auth status
```

## 5. Set the pipeline's repo variables from github-actions-wif's outputs

- `gh` takes no repo argument here — it infers the target from the current directory's git
  `origin` remote.
- So these must be run from inside a clone of this repo (same assumption step 6's `git push`
  makes).
- Running from elsewhere, or scripting this non-interactively, needs an explicit
  `-R defyjoy/terraform-cloud-run-invoice-sync` on each command instead.

```bash
gh variable set WIF_PROVIDER --body "$(terraform -chdir=live/github-actions-wif output -raw workload_identity_provider)"
gh variable set DEPLOY_SA_EMAIL --body "$(terraform -chdir=live/github-actions-wif output -raw service_account_email)"
```

## 6. Trigger the pipeline

- Creates the runtime SA, grants it its own project roles and the deploy SA's actAs on it.
- Creates the `db-password` secret container.
- Deploys `invoice-sync` end to end, all in one run.

```bash
git commit --allow-empty -m "bootstrap: trigger first pipeline run" && git push
```

## 7. Add the db-password secret value

- `db-secrets` only creates the secret container — the pipeline never writes a value to it (so
  the value never lands in Terraform state).
- Add one out-of-band, with your own credentials.
- `--data-file=-` reads the value from stdin instead of a file on disk, so it never touches
  shell history either:

```bash
echo -n "<the actual db password>" | gcloud secrets versions add db-password --project=yeti-504903 --data-file=-
```

Or from a file (e.g. one already used to seed the database itself):

```bash
gcloud secrets versions add db-password --project=yeti-504903 --data-file=./db-password.txt
```

## 8. Verify the deployment-failure-alert email channel

- Terraform creates the email notification channel (`modules/deployment-failure-alert`) but
  cannot verify it — Google requires a code sent to the actual inbox.
- gcloud has no `send-verification-code`/`verify` subcommand, so this is a one-time manual
  REST call.
- Skip this and the channel silently drops every notification with no error anywhere (alert
  policy still shows `enabled: true`, no Terraform/pipeline failure).
- Needs the `alpha` gcloud component:

```bash
gcloud components install alpha --quiet
```

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

- Re-run whenever the channel is recreated, e.g. `terraform destroy`/`apply` on
  `live/invoice-sync`.
- Also re-run after a `notification_email` change — Terraform's
  `google_monitoring_notification_channel` replaces the channel on some field changes,
  resetting verification.

## 9. Force a test deployment failure

- Exercises the alert end to end without touching Terraform-managed resources — see
  `live/invoice-sync/variables.tf`'s `expected_db_password` and `app/server.js`'s `/readyz`.
- The value below must match `expected_db_password` in `live/invoice-sync/.auto.tfvars` —
  check that file first, since it's stack-specific config, not a fixed value.

```bash
# Break it: set db-password to something other than expected_db_password
# (live/invoice-sync/.auto.tfvars)
gcloud secrets versions add db-password --project=yeti-504903 \
  --data-file=<(printf '%s' "deliberately-wrong-value")

# Push any commit to main to deploy a new revision — /readyz will 503 forever, the
# revision never becomes Ready, and the alert (once its channel is verified, step 8) fires.

# Fix it: restore the real value so the next deploy succeeds — read it from
# live/invoice-sync/.auto.tfvars's expected_db_password, don't hardcode it here
gcloud secrets versions add db-password --project=yeti-504903 \
  --data-file=<(printf '%s' "<expected_db_password from .auto.tfvars>")
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
