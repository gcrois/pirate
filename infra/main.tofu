terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "github" {
  token = var.github_token
  owner = var.owner
}

# --- GitHub Repository ---
resource "github_repository" "site_repo" {
  name         = var.repo_name
  homepage_url = "https://${var.itch_username}.itch.io/${var.repo_name}"
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

# --- Automation Bridge (Secrets & Vars) ---
resource "github_actions_secret" "secrets" {
  repository      = github_repository.site_repo.name
  secret_name     = "ITCHIO_API_KEY"
  plaintext_value = var.itch_token
}

resource "github_actions_variable" "configs" {
  for_each = {
    ITCH_USERNAME = var.itch_username
    ITCH_GAME_ID  = var.repo_name
    BUILD_DIR     = var.build_dir
  }
  repository    = github_repository.site_repo.name
  variable_name = each.key
  value         = each.value
}