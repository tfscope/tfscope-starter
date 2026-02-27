# digitalocean managed opensearch database
#
# o que faz:
#   - cria cluster opensearch (busca full-text, logs, analytics)
#   - configura trusted sources (quem pode conectar)
#
# quem pode conectar:
#   - qualquer recurso dentro da vpc (via cidr)
#   - conexao via rede privada
#
# por que usar vpc_cidr em vez de tag:
#   - tag: so droplets com tag especifica conectam
#   - cidr: qualquer recurso na vpc conecta (droplets, postgres, valkey)
#   - log forwarding nativo so funciona com cidr (recomendacao digitalocean)
#
# acesso:
#   - app conecta via private_uri (dentro da vpc)
#   - dashboard via ui_uri (interface web do opensearch)
#
# como enviar logs pro opensearch:
#   - droplet/django: instalar filebeat ou fluent bit, configurar pra ler logs
#   - postgres/valkey: usar log forwarding nativo da digitalocean (painel ou api)
#   - config de logs eh responsabilidade da equipe de app
#
# credenciais:
#   - terraform output private_uri (uri completa)
#   - ou: terraform output private_host, port, user, password

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

variable "vpc_cidr" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "opensearch_version" {
  type = string
}

variable "node_size" {
  type = string
}

variable "node_count" {
  type = number
}

variable "tags" {
  type = list(string)
}

// cluster

resource "digitalocean_database_cluster" "this" {
  name       = "${var.env}-${var.cluster_name}"
  engine     = "opensearch"
  version    = var.opensearch_version
  size       = var.node_size
  region     = var.region
  node_count = var.node_count

  private_network_uuid = var.vpc_id
  tags                 = var.tags

  # lifecycle { prevent_destroy = true } # ⚠️
}

// trusted sources

resource "digitalocean_database_firewall" "this" {
  cluster_id = digitalocean_database_cluster.this.id

  rule {
    type  = "ip_addr"
    value = var.vpc_cidr
  }
}

// outputs

output "id" {
  value = digitalocean_database_cluster.this.id
}

output "name" {
  value = digitalocean_database_cluster.this.name
}

output "host" {
  value     = digitalocean_database_cluster.this.host
  sensitive = true
}

output "private_host" {
  value     = digitalocean_database_cluster.this.private_host
  sensitive = true
}

output "port" {
  value = digitalocean_database_cluster.this.port
}

output "database" {
  value = digitalocean_database_cluster.this.database
}

output "user" {
  value = digitalocean_database_cluster.this.user
}

output "password" {
  value     = digitalocean_database_cluster.this.password
  sensitive = true
}

output "uri" {
  value     = digitalocean_database_cluster.this.uri
  sensitive = true
}

output "private_uri" {
  value     = digitalocean_database_cluster.this.private_uri
  sensitive = true
}

output "urn" {
  value = digitalocean_database_cluster.this.urn
}

// outputs - dashboard

output "ui_host" {
  value     = digitalocean_database_cluster.this.ui_host
  sensitive = true
}

output "ui_port" {
  value = digitalocean_database_cluster.this.ui_port
}

output "ui_uri" {
  value     = digitalocean_database_cluster.this.ui_uri
  sensitive = true
}

output "ui_database" {
  value = digitalocean_database_cluster.this.ui_database
}

output "ui_user" {
  value = digitalocean_database_cluster.this.ui_user
}

output "ui_password" {
  value     = digitalocean_database_cluster.this.ui_password
  sensitive = true
}