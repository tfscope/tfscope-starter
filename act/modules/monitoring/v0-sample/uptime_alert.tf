// uptime_alert.tf

// variables

variable "latency_threshold" {
  description = "Latency threshold in ms for uptime alert"
  type        = number
}

variable "ssl_expiry_days" {
  description = "Days before SSL expiry to trigger alert"
  type        = number
}

variable "down_alert_period" {
  description = "Period for down alert"
  type        = string
}

variable "latency_alert_period" {
  description = "Period for latency alert"
  type        = string
}

variable "ssl_alert_period" {
  description = "Period for SSL expiry alert"
  type        = string
}

// resource

resource "digitalocean_uptime_alert" "down" {
  count = local.create_uptime_check ? 1 : 0

  name       = "[${var.env}] Site down"
  check_id   = digitalocean_uptime_check.app[0].id
  type       = "down"
  threshold  = 0
  comparison = "greater_than"
  period     = var.down_alert_period

  notifications {
    email = var.alert_emails
  }
}

resource "digitalocean_uptime_alert" "latency" {
  count = local.create_uptime_check ? 1 : 0

  name       = "[${var.env}] High latency"
  check_id   = digitalocean_uptime_check.app[0].id
  type       = "latency"
  threshold  = var.latency_threshold
  comparison = "greater_than"
  period     = var.latency_alert_period

  notifications {
    email = var.alert_emails
  }
}

resource "digitalocean_uptime_alert" "ssl_expiry" {
  count = local.create_uptime_check ? 1 : 0

  name       = "[${var.env}] SSL expires soon"
  check_id   = digitalocean_uptime_check.app[0].id
  type       = "ssl_expiry"
  threshold  = var.ssl_expiry_days
  comparison = "less_than"
  period     = var.ssl_alert_period

  notifications {
    email = var.alert_emails
  }
}

// output

output "down_alert_period" {
  description = "Period for down alert"
  value       = local.create_uptime_check ? var.down_alert_period : null
}

output "latency_alert_period" {
  description = "Period for latency alert"
  value       = local.create_uptime_check ? var.latency_alert_period : null
}

output "ssl_alert_period" {
  description = "Period for SSL expiry alert"
  value       = local.create_uptime_check ? var.ssl_alert_period : null
}

output "latency_threshold" {
  description = "Latency threshold in ms"
  value       = local.create_uptime_check ? var.latency_threshold : null
}

output "ssl_expiry_days" {
  description = "Days before SSL expiry to trigger alert"
  value       = local.create_uptime_check ? var.ssl_expiry_days : null
}