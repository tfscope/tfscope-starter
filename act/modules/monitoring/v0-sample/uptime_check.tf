// uptime_check.tf

// variable

variable "uptime_check_url" {
  description = "URL to monitor for uptime (empty = no uptime check created)"
  type        = string
}

variable "uptime_check_type" {
  description = "Type of uptime check (https, http, ping)"
  type        = string
}

variable "uptime_regions" {
  description = "Regions to perform uptime checks from"
  type        = list(string)
}

locals {
  create_uptime_check = var.uptime_check_url != ""
}

// resource

resource "digitalocean_uptime_check" "app" {
  count = local.create_uptime_check ? 1 : 0

  name    = "${var.env}-uptime"
  target  = var.uptime_check_url
  type    = var.uptime_check_type
  regions = var.uptime_regions
  enabled = var.enabled
}

// output

output "uptime_check_id" {
  description = "Uptime check ID"
  value       = local.create_uptime_check ? digitalocean_uptime_check.app[0].id : null
}

output "uptime_check_url" {
  description = "URL being monitored"
  value       = local.create_uptime_check ? var.uptime_check_url : null
}

output "uptime_check_type" {
  description = "Type of uptime check"
  value       = local.create_uptime_check ? var.uptime_check_type : null
}

output "uptime_check_regions" {
  description = "Regions performing uptime checks"
  value       = local.create_uptime_check ? var.uptime_regions : null
}
