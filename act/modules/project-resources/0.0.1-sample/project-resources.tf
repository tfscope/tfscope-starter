terraform {
  required_providers {
    digitalocean = { source = "digitalocean/digitalocean" }
  }
}

// variables

variable "target_project_id" {
  type        = string
  description = "ID do projeto destino"
}

variable "target_project_name" {
  type        = string
  description = "Nome do projeto destino"
}

variable "resources_to_assign" {
  type        = list(string)
  description = "Lista de URNs dos recursos a alocar"
}

// resource

# prevent_destroy não necessário - destroy apenas desassocia, recursos voltam pro project-default
resource "digitalocean_project_resources" "this" {
  project   = var.target_project_id
  resources = var.resources_to_assign
}

// outputs

output "target_project_id" {
  value       = digitalocean_project_resources.this.project
  description = "ID do projeto que recebeu os recursos"
}

output "target_project_name" {
  value       = var.target_project_name
  description = "Nome do projeto que recebeu os recursos"
}

output "assigned_resources" {
  value       = digitalocean_project_resources.this.resources
  description = "URNs dos recursos alocados ao projeto"
}