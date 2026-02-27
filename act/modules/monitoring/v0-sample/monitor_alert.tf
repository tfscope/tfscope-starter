// monitor_alert.tf

terraform {
  required_providers {
    digitalocean = { source = "digitalocean/digitalocean" }
  }
}

// variables

variable "enabled" {
  description = "Enable/disable all alerts (alerts exist but don't fire when false)"
  type        = bool
}

variable "env" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "alert_emails" {
  description = "Email addresses to receive alerts"
  type        = list(string)
}

variable "droplet_ids" {
  description = "List of Droplet IDs to monitor (empty = no droplet alerts created)"
  type        = list(number)
}

variable "droplet_alerts" {
  description = "Map of droplet alert configurations"
  type = map(object({
    metric = string
    value  = number
  }))
}

variable "cpu_warning_window" {
  description = "Window for CPU warning alert"
  type        = string
}

variable "cpu_critical_window" {
  description = "Window for CPU critical alert"
  type        = string
}

variable "memory_warning_window" {
  description = "Window for memory warning alert"
  type        = string
}

variable "memory_critical_window" {
  description = "Window for memory critical alert"
  type        = string
}

variable "disk_warning_window" {
  description = "Window for disk warning alert"
  type        = string
}

variable "disk_critical_window" {
  description = "Window for disk critical alert"
  type        = string
}

locals {
  create_droplet_alerts = length(var.droplet_ids) > 0

  alert_windows = {
    cpu_warning      = var.cpu_warning_window
    cpu_critical     = var.cpu_critical_window
    memory_warning   = var.memory_warning_window
    memory_critical  = var.memory_critical_window
    disk_warning     = var.disk_warning_window
    disk_critical    = var.disk_critical_window
  }
}

// resource

resource "digitalocean_monitor_alert" "droplet" {
  for_each = local.create_droplet_alerts ? var.droplet_alerts : {}

  alerts {
    email = var.alert_emails
  }

  description = "[${var.env}] Droplet ${replace(each.key, "_", " ")}"
  type        = each.value.metric
  compare     = "GreaterThan"
  value       = each.value.value
  window      = local.alert_windows[each.key]
  entities    = var.droplet_ids
  enabled     = var.enabled
}

// output

output "droplet_alert_ids" {
  description = "Map of droplet alert names to UUIDs"
  value       = { for k, v in digitalocean_monitor_alert.droplet : k => v.uuid }
}

output "enabled" {
  description = "Whether monitoring is enabled"
  value       = var.enabled
}

output "alert_emails" {
  description = "Email addresses receiving notifications"
  value       = var.alert_emails
}