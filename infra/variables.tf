variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "github_token" {
  type      = string
  sensitive = true
}

variable "account_id" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "owner" {
  description = "GitHub username or org"
  type        = string
}

variable "repo_name" {
  type = string
}

variable "project_name" {
  type = string
}

variable "root_domain" {
  type = string
}

variable "subdomain" {
  type    = string
  default = "@"
}

variable "build_dir" {
  type    = string
  default = "./dist"
}

variable "repo_visibility" {
  type    = string
  default = "public"
}