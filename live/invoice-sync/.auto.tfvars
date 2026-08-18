notification_email = "joydeepbeyondsky86@gmail.com"

# github-deployer@<project>.iam.gserviceaccount.com is deterministic from
# ../github-actions-wif's deploy_account_id default ("github-deployer") + project_id — no need
# to wait for that stack's apply to fill this in, just to apply it before this stack.
deploy_service_account_email = "github-deployer@yeti-504903.iam.gserviceaccount.com"
