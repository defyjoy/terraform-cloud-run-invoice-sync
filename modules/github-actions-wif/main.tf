resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions"
  description               = "Federates GitHub Actions OIDC tokens for keyless deploys, scoped to specific repos via each provider's attribute_condition."
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "GitHub"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "assertion.repository == \"${var.github_owner}/${var.github_repo}\" && assertion.ref == \"${var.github_ref}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

module "deploy_service_account" {
  source  = "terraform-google-modules/service-accounts/google"
  version = "~> 4.7"

  project_id   = var.project_id
  names        = [var.deploy_account_id]
  display_name = "Deploys ${var.github_owner}/${var.github_repo} via GitHub Actions (WIF, no key file)"
}

locals {
  deploy_sa_roles = {
    compute_network = {
      role      = google_project_iam_custom_role.compute_network.id
      condition = null
    }

    load_balancer = {
      role      = google_project_iam_custom_role.load_balancer.id
      condition = null
    }

    cloud_run = {
      role      = google_project_iam_custom_role.cloud_run.id
      condition = null
    }

    artifact_registry = {
      role      = google_project_iam_custom_role.artifact_registry.id
      condition = null
    }

    secret_manager = {
      role      = google_project_iam_custom_role.secret_manager.id
      condition = null
    }

    kms = {
      role      = google_project_iam_custom_role.kms.id
      condition = null
    }

    pubsub = {
      role      = google_project_iam_custom_role.pubsub.id
      condition = null
    }

    monitoring = {
      role      = google_project_iam_custom_role.monitoring.id
      condition = null
    }

    logging = {
      role      = google_project_iam_custom_role.logging.id
      condition = null
    }

    iam_service_account_mgmt = {
      role      = google_project_iam_custom_role.iam_service_account_mgmt.id
      condition = null
    }
  }
}

resource "google_project_iam_custom_role" "compute_network" {
  project     = var.project_id
  role_id     = "githubDeployerComputeNetwork"
  title       = "GitHub Deployer - Compute Network"
  description = "VPC/subnet/firewall/router/VPC-access-connector management for live/network."
  stage       = "GA"
  permissions = [
    "compute.networks.create",
    "compute.networks.get",
    "compute.networks.update",
    "compute.networks.use",
    "compute.subnetworks.create",
    "compute.subnetworks.get",
    "compute.subnetworks.update",
    "compute.subnetworks.use",
    "compute.subnetworks.setPrivateIpGoogleAccess",
    "compute.firewalls.create",
    "compute.firewalls.get",
    "compute.firewalls.update",
    "compute.firewalls.delete",
    "compute.routers.create",
    "compute.routers.get",
    "compute.routers.update",
    "compute.routers.use",
    "vpcaccess.connectors.create",
    "vpcaccess.connectors.get",
    "vpcaccess.connectors.update",
    "vpcaccess.connectors.list",
  ]
}

resource "google_project_iam_custom_role" "load_balancer" {
  project     = var.project_id
  role_id     = "githubDeployerLoadBalancer"
  title       = "GitHub Deployer - Load Balancer"
  description = "Global external HTTP(S) LB resources for modules/serverless-lb."
  stage       = "GA"
  permissions = [
    "compute.regionNetworkEndpointGroups.create",
    "compute.regionNetworkEndpointGroups.get",
    "compute.regionNetworkEndpointGroups.delete",
    "compute.regionNetworkEndpointGroups.use",
    "compute.globalAddresses.create",
    "compute.globalAddresses.get",
    "compute.globalAddresses.delete",
    "compute.globalAddresses.use",
    "compute.globalAddresses.setLabels",
    "compute.sslPolicies.create",
    "compute.sslPolicies.get",
    "compute.sslPolicies.update",
    "compute.sslPolicies.delete",
    "compute.sslPolicies.use",
    "compute.sslCertificates.create",
    "compute.sslCertificates.get",
    "compute.sslCertificates.delete",
    "compute.backendServices.create",
    "compute.backendServices.get",
    "compute.backendServices.update",
    "compute.backendServices.delete",
    "compute.backendServices.use",
    "compute.backendServices.setSecurityPolicy",
    "compute.urlMaps.create",
    "compute.urlMaps.get",
    "compute.urlMaps.update",
    "compute.urlMaps.delete",
    "compute.urlMaps.use",
    "compute.urlMaps.validate",
    "compute.targetHttpProxies.create",
    "compute.targetHttpProxies.get",
    "compute.targetHttpProxies.update",
    "compute.targetHttpProxies.delete",
    "compute.targetHttpProxies.use",
    "compute.targetHttpProxies.setUrlMap",
    "compute.targetHttpsProxies.create",
    "compute.targetHttpsProxies.get",
    "compute.targetHttpsProxies.update",
    "compute.targetHttpsProxies.delete",
    "compute.targetHttpsProxies.use",
    "compute.targetHttpsProxies.setUrlMap",
    "compute.targetHttpsProxies.setSslPolicy",
    "compute.targetHttpsProxies.setSslCertificates",
    "compute.globalForwardingRules.create",
    "compute.globalForwardingRules.get",
    "compute.globalForwardingRules.update",
    "compute.globalForwardingRules.delete",
    "compute.globalForwardingRules.setTarget",
    "compute.globalForwardingRules.setLabels",
  ]
}

resource "google_project_iam_custom_role" "cloud_run" {
  project     = var.project_id
  role_id     = "githubDeployerCloudRun"
  title       = "GitHub Deployer - Cloud Run"
  description = "Cloud Run service management for modules/cloud-run."
  stage       = "GA"
  permissions = [
    "run.services.create",
    "run.services.get",
    "run.services.update",
    "run.services.delete",
    "run.services.getIamPolicy",
    "run.services.setIamPolicy",
  ]
}

resource "google_project_iam_custom_role" "artifact_registry" {
  project     = var.project_id
  role_id     = "githubDeployerArtifactRegistry"
  title       = "GitHub Deployer - Artifact Registry"
  description = "Repository management for modules/artifact-registry."
  stage       = "GA"
  permissions = [
    "artifactregistry.repositories.create",
    "artifactregistry.repositories.get",
    "artifactregistry.repositories.update",
    "artifactregistry.repositories.delete",
    "artifactregistry.repositories.getIamPolicy",
    "artifactregistry.repositories.setIamPolicy",
  ]
}

resource "google_project_iam_custom_role" "secret_manager" {
  project     = var.project_id
  role_id     = "githubDeployerSecretManager"
  title       = "GitHub Deployer - Secret Manager"
  description = "Secret container management for modules/secret-manager-secret."
  stage       = "GA"
  permissions = [
    "secretmanager.secrets.create",
    "secretmanager.secrets.get",
    "secretmanager.secrets.update",
    "secretmanager.secrets.getIamPolicy",
    "secretmanager.secrets.setIamPolicy",
  ]
}

resource "google_project_iam_custom_role" "kms" {
  project     = var.project_id
  role_id     = "githubDeployerKms"
  title       = "GitHub Deployer - Cloud KMS"
  description = "CMEK key ring/key management for modules/secret-manager-secret."
  stage       = "GA"
  permissions = [
    "cloudkms.keyRings.create",
    "cloudkms.keyRings.get",
    "cloudkms.keyRings.list",
    "cloudkms.keyRings.getIamPolicy",
    "cloudkms.cryptoKeys.create",
    "cloudkms.cryptoKeys.get",
    "cloudkms.cryptoKeys.update",
    "cloudkms.cryptoKeys.getIamPolicy",
    "cloudkms.cryptoKeys.setIamPolicy",
  ]
}

resource "google_project_iam_custom_role" "pubsub" {
  project     = var.project_id
  role_id     = "githubDeployerPubsub"
  title       = "GitHub Deployer - Pub/Sub"
  description = "Topic management for modules/secret-manager-secret and modules/deployment-failure-alert."
  stage       = "GA"
  permissions = [
    "pubsub.topics.create",
    "pubsub.topics.get",
    "pubsub.topics.update",
    "pubsub.topics.getIamPolicy",
    "pubsub.topics.setIamPolicy",
  ]
}

resource "google_project_iam_custom_role" "monitoring" {
  project     = var.project_id
  role_id     = "githubDeployerMonitoring"
  title       = "GitHub Deployer - Monitoring"
  description = "Notification channel and alert policy management for modules/deployment-failure-alert."
  stage       = "GA"
  permissions = [
    "monitoring.notificationChannels.create",
    "monitoring.notificationChannels.get",
    "monitoring.notificationChannels.update",
    "monitoring.notificationChannels.delete",
    "monitoring.notificationChannels.list",
    "monitoring.alertPolicies.create",
    "monitoring.alertPolicies.get",
    "monitoring.alertPolicies.update",
    "monitoring.alertPolicies.delete",
    "monitoring.alertPolicies.list",
  ]
}

resource "google_project_iam_custom_role" "logging" {
  project     = var.project_id
  role_id     = "githubDeployerLogging"
  title       = "GitHub Deployer - Logging"
  description = "Log-based-alerting notification rule needed by modules/deployment-failure-alert."
  stage       = "GA"
  permissions = [
    "logging.notificationRules.create",
    "logging.notificationRules.get",
    "logging.notificationRules.update",
    "logging.notificationRules.delete",
    "logging.notificationRules.list",
  ]
}

resource "google_project_iam_custom_role" "iam_service_account_mgmt" {
  project     = var.project_id
  role_id     = "githubDeployerIamServiceAccountMgmt"
  title       = "GitHub Deployer - IAM Service Account Management"
  description = "Runtime SA creation/actAs and its project-role grants for modules/cloud-run."
  stage       = "GA"
  permissions = [
    "iam.serviceAccounts.create",
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.list",
    "iam.serviceAccounts.update",
    "iam.serviceAccounts.getIamPolicy",
    "iam.serviceAccounts.setIamPolicy",
    "resourcemanager.projects.getIamPolicy",
    "resourcemanager.projects.setIamPolicy",
  ]
}

resource "google_project_iam_member" "deploy_sa_roles" {
  for_each = local.deploy_sa_roles

  project = var.project_id
  role    = each.value.role
  member  = module.deploy_service_account.iam_email

  dynamic "condition" {
    for_each = each.value.condition != null ? [each.value.condition] : []
    content {
      title       = condition.value.title
      description = condition.value.description
      expression  = condition.value.expression
    }
  }
}

resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = module.deploy_service_account.service_account.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.github_repo}"
}

resource "google_storage_bucket_iam_member" "deploy_can_write_state" {
  bucket = var.state_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${module.deploy_service_account.email}"
}
