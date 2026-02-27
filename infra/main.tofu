terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "github" {
  token = var.github_token
  owner = var.owner
}

# --- GitHub Repository ---
resource "github_repository" "site_repo" {
  name         = var.repo_name
  description  = "Managed by Terraform: ${var.project_name}"
  homepage_url = "https://${var.subdomain == "@" ? var.root_domain : "${var.subdomain}.${var.root_domain}"}"
  visibility   = var.repo_visibility
  auto_init    = true

  lifecycle {
    ignore_changes = [
      allow_forking
    ]
  }
}

resource "null_resource" "git_remote_config" {
  triggers = {
    repo_url = github_repository.site_repo.ssh_clone_url
  }

  provisioner "local-exec" {
    command = "git -C .. remote add origin ${github_repository.site_repo.ssh_clone_url} || git -C .. remote set-url origin ${github_repository.site_repo.ssh_clone_url}"
  }
}

# --- Cloudflare Pages ---
resource "cloudflare_pages_project" "static_site" {
  account_id        = var.account_id
  name              = var.project_name
  production_branch = "main"
}

resource "cloudflare_pages_domain" "custom_domain" {
  account_id   = var.account_id
  project_name = cloudflare_pages_project.static_site.name
  domain       = var.subdomain == "@" ? var.root_domain : "${var.subdomain}.${var.root_domain}"
}

resource "cloudflare_record" "site_dns" {
  zone_id = var.zone_id
  name    = var.subdomain
  type    = "CNAME"
  content = cloudflare_pages_project.static_site.subdomain
  proxied = true
}

# --- Automation Bridge (Secrets & Vars) ---
resource "github_actions_secret" "secrets" {
  for_each = {
    CLOUDFLARE_API_TOKEN = var.cloudflare_api_token
    CLOUDFLARE_ACCOUNT_ID = var.account_id
  }
  repository      = github_repository.site_repo.name
  secret_name     = each.key
  plaintext_value = each.value
}

resource "github_actions_variable" "configs" {
  for_each = {
    CLOUDFLARE_PROJECT_NAME = var.project_name
    CLOUDFLARE_OUTPUT_DIR   = var.build_dir
    VITE_PAGES_HOST         = cloudflare_pages_project.static_site.subdomain
  }
  repository    = github_repository.site_repo.name
  variable_name = each.key
  value         = each.value
}