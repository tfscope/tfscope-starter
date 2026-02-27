terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.73.0"
    }
  }
}

provider "digitalocean" {
  spaces_access_id  = var.do_spaces_id
  spaces_secret_key = var.do_spaces_secret
}

variable "do_spaces_id" {
  type        = string
  sensitive   = true
  description = "Injected via direnv → TF_VAR_do_spaces_id"
}

variable "do_spaces_secret" {
  type        = string
  sensitive   = true
  description = "Injected via direnv → TF_VAR_do_spaces_secret"
}

variable "bucket_name" {
  type = string
}

variable "region" {
  type = string
}

variable "bucket_versioning" {
  type    = bool
  default = true
}

variable "bucket_noncurrent_days" {
  type    = number
  default = 0
}

resource "digitalocean_spaces_bucket" "this" {
  # lifecycle { prevent_destroy = true } # ⚠️
  # force_destroy = true # ⛔⛔⛔⛔ enable to destroy with content ⛔⛔⛔⛔

  name   = var.bucket_name
  region = var.region
  acl    = "private"

  versioning {
    enabled = var.bucket_versioning
  }

  dynamic "lifecycle_rule" {
    for_each = var.bucket_noncurrent_days > 0 ? [1] : []
    content {
      enabled = true
      noncurrent_version_expiration {
        days = var.bucket_noncurrent_days
      }
    }
  }
}

output "id" {
  value = digitalocean_spaces_bucket.this.id
}

output "name" {
  value = digitalocean_spaces_bucket.this.name
}

output "urn" {
  value = digitalocean_spaces_bucket.this.urn
}

output "endpoint" {
  value = digitalocean_spaces_bucket.this.bucket_domain_name
}

output "region" {
  value = digitalocean_spaces_bucket.this.region
}
