terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.73.0"
    }
  }
}

variable "vpc_name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_description" {
  type    = string
  default = ""
}

resource "digitalocean_vpc" "this" {
  # lifecycle { prevent_destroy = true } # ⚠️

  name        = var.vpc_name
  region      = var.region
  description = var.vpc_description
  # ip_range automatically assigned by DigitalOcean
}

output "id" {
  value = digitalocean_vpc.this.id
}

output "name" {
  value = digitalocean_vpc.this.name
}

output "region" {
  value = digitalocean_vpc.this.region
}

output "ip_range" {
  value = digitalocean_vpc.this.ip_range
}

output "is_default" {
  value       = digitalocean_vpc.this.default
  description = "Read-only. Set default via DigitalOcean Control Panel."
}
