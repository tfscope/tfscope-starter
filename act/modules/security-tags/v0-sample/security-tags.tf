terraform {
  required_providers {
    digitalocean = { source = "digitalocean/digitalocean" }
  }
}

// variables

variable "env" {
  type = string
}

// firewall tags

resource "digitalocean_tag" "fw_inet_out" {
  lifecycle { create_before_destroy = true }  # ⚠️
  name = "${var.env}:fw:inet-out"
}

// role tags

resource "digitalocean_tag" "role_app" {
  lifecycle { create_before_destroy = true }  # ⚠️
  name = "${var.env}:role:app"
}

// info tags

resource "digitalocean_tag" "info_postgres" {
  lifecycle { create_before_destroy = true } # ⚠️
  name = "${var.env}:info:postgres"
}

resource "digitalocean_tag" "info_valkey" {
  lifecycle { create_before_destroy = true } # ⚠️
  name = "${var.env}:info:valkey"
}

resource "digitalocean_tag" "info_opensearch" {
  lifecycle { create_before_destroy = true } # ⚠️
  name = "${var.env}:info:opensearch"
}

// outputs

output "fw_inet_out" {
  value = digitalocean_tag.fw_inet_out.name
}

output "role_app" {
  value = digitalocean_tag.role_app.name
}

output "info_postgres" {
  value = digitalocean_tag.info_postgres.name
}

output "info_valkey" {
  value = digitalocean_tag.info_valkey.name
}

output "info_opensearch" {
  value = digitalocean_tag.info_opensearch.name
}
