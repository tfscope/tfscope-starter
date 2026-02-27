# firewall: internet egress only (deny all inbound)
# allows: http/s, dns, ntp, tailscale

terraform {
  required_providers {
    digitalocean = { source = "digitalocean/digitalocean" }
  }
}

// variables

variable "env" {
  type = string
}

variable "tag_inet_out" {
  type        = string
  description = "Provided by data.terraform_remote_state.security_tags"
}

// firewall

resource "digitalocean_firewall" "this" {
  lifecycle { create_before_destroy = true } # ⚠️

  name = "${var.env}-fw-inet-out"
  tags = [var.tag_inet_out]

  // no inbound rules

  // outbound

  outbound_rule {
    protocol              = "tcp"
    port_range            = "443" # https + tailscale derp fallback
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "443" # http3/quic
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "80" # http
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "53" # dns tcp fallback
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "53" # dns primary
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "123" # ntp time sync
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "41641" # tailscale wireguard
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"] # ping/traceroute
  }
}

// outputs

output "name" {
  value = digitalocean_firewall.this.name
}

output "id" {
  value = digitalocean_firewall.this.id
}
