# droplet
#
# o que faz:
#   - cria droplet linux
#   - cria usuario ssh (nao root)
#   - desabilita login root
#   - instala tailscale e registra no tailnet
#
# acesso:
#   - ssh via tailscale: tailscale ssh {user}@{name}
#   - sudo sem senha (tailscale autentica)
#
# nome final: {env}-{type}-{suffix}
#   exemplo: dev-app-a7f3, prod-api-b8e4
#
# logs:
#   - cat /var/log/terraform-init.log
#
# customizacao:
#   - apos criar, acessa via tailscale e instala o que precisar
#   - ou usa ansible pra configurar

terraform {
  required_providers {
    digitalocean = { source = "digitalocean/digitalocean" }
    random       = { source = "hashicorp/random" }
  }
}

// variables

variable "env" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "ts_auth_droplet" {
  type      = string
  sensitive = true
}

variable "ssh_user" {
  type = string
}

variable "droplet_type" {
  type        = string
  description = "Tipo do droplet (app, web, api, worker, etc)"
}

variable "droplet_size" {
  type = string
}

variable "droplet_image" {
  type = string
}

variable "tags" {
  type = list(string)
}

// locals

locals {
  user_data = templatefile("${path.module}/templates/init.sh", {
    ssh_user    = var.ssh_user
    ts_auth_key = var.ts_auth_droplet
  })
}

// random suffix

resource "random_id" "suffix" {
  byte_length = 2
}

// droplet

resource "digitalocean_droplet" "this" {
  # lifecycle { prevent_destroy = true } # ⚠️ 

  name              = "${var.env}-${var.droplet_type}-${random_id.suffix.hex}"
  image             = var.droplet_image
  size              = var.droplet_size
  region            = var.region
  vpc_uuid          = var.vpc_id
  user_data         = local.user_data
  tags              = var.tags
  monitoring        = true
  graceful_shutdown = true
}

// outputs

output "id" {
  value = digitalocean_droplet.this.id
}

output "name" {
  value = digitalocean_droplet.this.name
}

output "private_ip" {
  value = digitalocean_droplet.this.ipv4_address_private
}

output "public_ip" {
  value = digitalocean_droplet.this.ipv4_address
}

output "urn" {
  value = digitalocean_droplet.this.urn
}
