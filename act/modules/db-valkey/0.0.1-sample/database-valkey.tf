# digitalocean managed valkey database
#
# o que eh valkey
#   - banco de cache em memoria (chave-valor)
#   - substituto do redis (100% compativel)
#   - digitalocean nao oferece redis, celery nem rabbitmq gerenciado
#
# o que esse modulo faz
#   - cria cluster valkey
#   - configura trusted sources via vpc cidr (quem pode conectar)
#   - configura eviction policy (o que deletar quando memoria enche)
#
# o que esse modulo NAO faz
#   - criar vpc (recebe vpc_id do caller)
#   - criar usuarios (valkey usa usuario "default" unico)
#   - connection pool (valkey nao precisa, diferente do postgres)
#
# uso no django
#   - cache: sessoes de usuarios, cache de views, cache de queries
#   - filas: tarefas assincronas em background
#     - exemplo: envio de email, geracao de relatorios, processamento de arquivos
#
# credenciais
#   - terraform output uri (usar no django)

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

variable "valkey_version" {
  type = string
}

variable "node_size" {
  type = string
}

variable "node_count" {
  type = number
  # 1 = sem alta disponibilidade
  # 2+ = com alta disponibilidade (primary + standby)
}

variable "eviction_policy" {
  type = string
  # o que deletar quando memoria enche
  # recomendado: allkeys_lru (remove menos usados)
}

variable "tags" {
  type = list(string)
}

// cluster

resource "digitalocean_database_cluster" "this" {
  name       = "${var.env}-${var.cluster_name}"
  engine     = "valkey"
  version    = var.valkey_version
  size       = var.node_size
  region     = var.region
  node_count = var.node_count

  eviction_policy      = var.eviction_policy
  private_network_uuid = var.vpc_id
  tags                 = var.tags

  # lifecycle { prevent_destroy = true } # ⚠️
}

// trusted sources
# quem pode conectar no banco
# vpc cidr = qualquer recurso na vpc (droplets, outros bancos)

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
  value     = digitalocean_database_cluster.this.private_host
  sensitive = true
}

output "port" {
  value = digitalocean_database_cluster.this.port
}

output "password" {
  value     = digitalocean_database_cluster.this.password
  sensitive = true
}

output "uri" {
  value     = digitalocean_database_cluster.this.private_uri
  sensitive = true
  # USAR ESSE NO DJANGO
}

output "urn" {
  value = digitalocean_database_cluster.this.urn
}

output "eviction_policy" {
  value = var.eviction_policy
}