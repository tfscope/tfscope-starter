# v0-sample — reference only
terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.73.0"
    }
  }
}

variable "project_name" {
  type = string
}

variable "project_description" {
  type = string
}

variable "project_purpose" {
  type = string
}

variable "project_environment" {
  type = string
}

variable "is_default" {
  type = bool
}

resource "digitalocean_project" "this" {
  # lifecycle { prevent_destroy = true }  # ⚠️

  name        = var.project_name
  description = var.project_description
  purpose     = var.project_purpose
  environment = var.project_environment
  is_default  = var.is_default
}

output "id" {
  value = digitalocean_project.this.id
}

output "name" {
  value = digitalocean_project.this.name
}

output "is_default" {
  value = digitalocean_project.this.is_default
}
