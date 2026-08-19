module "db_password" {
  source = "../../modules/secret-manager-secret"

  project_id = var.project_id
  secret_id  = var.db_password_secret_id
}
