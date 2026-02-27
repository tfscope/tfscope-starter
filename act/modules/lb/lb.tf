# load balancer (SSL passthrough)
#
# fluxo: usuario → cloudflare (SSL termination) → LB (passthrough) → droplet (SSL termination com Origin CA)
#
# - LB nao descriptografa trafego, apenas encaminha TCP na porta 443
# - firewall do LB aceita apenas IPs do cloudflare (bloqueia acesso direto)
# - healthcheck usa porta 80 separada (HTTP) pois porta 443 esta em passthrough
# - certificado SSL gerenciado no droplet (reverse proxy) com Cloudflare Origin CA

terraform {
  required_providers {
    digitalocean = { source = "digitalocean/digitalocean" }
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

variable "lb_allow_ipv4" {
  type        = list(string)
  description = "Cloudflare IPv4 ranges. Update from: https://www.cloudflare.com/ips/"
}

variable "lb_allow_ipv6" {
  type        = list(string)
  description = "Cloudflare IPv6 ranges. Update from: https://www.cloudflare.com/ips/"
}

// locals

locals {
  cloudflare_allow_list = concat(
    [for ip in var.lb_allow_ipv4 : "cidr:${ip}"],
    [for ip in var.lb_allow_ipv6 : "cidr:${ip}"]
  )
}

// load balancer

resource "digitalocean_loadbalancer" "this" {
  name        = "${var.env}-lb"
  region      = var.region
  size        = "lb-small" # lb-small: 10k conexoes | lb-medium: 50k | lb-large: 100k
  vpc_uuid    = var.vpc_id
  droplet_tag = "${var.env}:role:app" # tag dos droplets que recebem trafego

  # lifecycle { prevent_destroy = true } # ⚠️

  firewall {
    allow = local.cloudflare_allow_list # so IPs do cloudflare acessam o LB - bloqueia acesso direto
  }

  forwarding_rule {
    entry_port      = 443 # LB escuta HTTPS
    entry_protocol  = "https"
    target_port     = 443 # droplet recebe na 443 - reverse proxy termina SSL com Origin CA cert
    target_protocol = "https"
    tls_passthrough = true # LB nao descriptografa - encaminha trafego criptografado direto pro droplet
  }

  healthcheck {
    port                     = 80 # porta separada pro healthcheck - reverse proxy expoe /health na 80
    protocol                 = "http"
    path                     = "/health" # endpoint que retorna 200 OK
    check_interval_seconds   = 10        # verifica a cada 10s
    response_timeout_seconds = 5         # droplet deve responder em ate 5s
    unhealthy_threshold      = 3         # 3 falhas = remove do pool
    healthy_threshold        = 5         # 5 sucessos = volta pro pool
  }

  sticky_sessions {
    type = "none" # stateless - sessao fica no Redis/DB, qualquer droplet atende qualquer request
  }

  redirect_http_to_https           = false # porta HTTP nao exposta - cloudflare faz redirect
  disable_lets_encrypt_dns_records = true  # usa cloudflare origin CA, nao let's encrypt
}

// outputs

output "id" {
  value = digitalocean_loadbalancer.this.id
}

output "name" {
  value = digitalocean_loadbalancer.this.name
}

output "ip" {
  value       = digitalocean_loadbalancer.this.ip
  description = "Point Cloudflare DNS A record to this IP"
}

output "urn" {
  value = digitalocean_loadbalancer.this.urn
}

output "size" {
  value       = digitalocean_loadbalancer.this.size
  description = "LB size (conexoes simultaneas): lb-small=10k | lb-medium=50k | lb-large=100k"
}

output "allowed_ipv4" {
  value       = var.lb_allow_ipv4
  description = "Cloudflare IPv4 ranges allowed"
}

output "allowed_ipv6" {
  value       = var.lb_allow_ipv6
  description = "Cloudflare IPv6 ranges allowed"
}
