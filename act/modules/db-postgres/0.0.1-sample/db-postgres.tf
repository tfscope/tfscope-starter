# digitalocean managed postgresql database
#
# arquitetura
#   - servico gerenciado (backups, updates, monitoramento automaticos)
#   - alta disponibilidade opcional (standby nodes para failover)
#   - connection pooling via pgbouncer (incluso)
#   - atualizacoes automaticas de versoes menores
#   - point-in-time recovery (PITR)
#
# compliance
#   - ISO 27001 A.12.3.1 (backups automaticos, PITR)
#   - ISO 27001 A.12.4.1 (logging de eventos)
#   - ISO 27001 A.18.1.3 (protecao de dados, criptografia em repouso)
#   - ISO 27001 A.9.4.1 (controle de acesso - usuarios separados)
#   - LGPD Art. 46 (medidas de seguranca)
#   - GDPR Art. 32 (criptografia, backup, integridade)
#   - SOC 2 CC6.1 (controles de acesso logico)
#   - SOC 2 CC7.2 (monitoramento e logging do sistema)
#   - PCI-DSS Req 2.4 (inventario de componentes)
#   - PCI-DSS Req 3.4 (criptografia em repouso - AES-256 automatico)
#   - PCI-DSS Req 7.1 (acesso limitado por necessidade)
#
# seguranca
#   - criptografia em repouso: AES-256 (automatico)
#   - criptografia em transito: TLS 1.2+ (obrigatorio)
#   - rede privada apenas (VPC isolada)
#   - trusted sources via VPC CIDR (sem acesso publico)
#   - atualizacoes de seguranca automaticas
#   - connection pooling reduz superficie de ataque
#   - usuarios separados para app/migrations/readonly/maintenance (least privilege)
#
# estrategia de backup
#   - backups diarios automaticos (gerenciado pela DigitalOcean)
#   - retencao de 7 dias (padrao, nao configuravel via Terraform)
#   - point-in-time recovery (ultimos 7 dias)
#   - janela de backup otimizada automaticamente pela DigitalOcean
#   - backup cross-region (disaster recovery)
#
# usuarios (principle of least privilege)
#   - app: django/celery (SELECT, INSERT, UPDATE, DELETE)
#   - migrations: ci/cd (DDL: CREATE, ALTER, DROP)
#   - readonly: reports/bi (SELECT only)
#   - maintenance: debug/suporte (SELECT only em views anonimizadas)
#   - keycloak: auth server (full no database keycloak, isolado do app)
#   - doadmin: emergencia (credenciais no vault, bloqueado por FORCE RLS)
#
# rls (row level security) - CRITICO
#   - FORCE RLS obrigatorio em todas as tabelas com dados de clientes
#   - sem FORCE: superuser/doadmin ve todos os dados (risco grave)
#   - django deve setar current_setting('app.escritorio_id') em cada request
#   - app: RLS filtra por escritorio_id
#   - migrations: FORCE RLS - nao ve dados mesmo com DDL
#   - readonly: RLS - so ve dados agregados/anonimizados
#   - maintenance: acesso apenas a views de manutencao (dados anonimizados)
#   - keycloak: banco separado, nao acessa dados do app
#
# credenciais
#   - terraform output app_pool_uri (usar no django)
#   - terraform output readonly_pool_uri (usar em reports)
#   - terraform output maintenance_password (usar em debug/suporte)
#   - terraform output keycloak_pool_uri (usar no keycloak container)

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

variable "postgres_version" {
  type = string
}

variable "node_size" {
  type = string
}

variable "node_count" {
  type = number
}

variable "pool_size" {
  type = number
}

variable "tags" {
  type = list(string)
}

// cluster

resource "digitalocean_database_cluster" "this" {
  name       = "${var.env}-${var.cluster_name}"
  engine     = "pg"
  version    = var.postgres_version
  size       = var.node_size
  region     = var.region
  node_count = var.node_count

  # rede privada - sem ip publico, acesso apenas via vpc
  private_network_uuid = var.vpc_id
  tags                 = var.tags

  # lifecycle { prevent_destroy = true } # ⚠️
}

// database - app
# banco principal da aplicacao
# nome usa underscore pq postgres nao aceita hifen

resource "digitalocean_database_db" "main" {
  cluster_id = digitalocean_database_cluster.this.id
  name       = replace("${var.env}_${var.cluster_name}", "-", "_")
}

// database - keycloak
# banco separado para keycloak (auth server)
# roda como sidecar no droplet, persiste aqui
# isolado do banco do app - keycloak gerencia proprio schema

resource "digitalocean_database_db" "keycloak" {
  cluster_id = digitalocean_database_cluster.this.id
  name       = "${var.env}_keycloak"
}

// users - app
# usuarios separados por funcao (principle of least privilege)
# permissoes configuradas via django migrations, nao aqui

resource "digitalocean_database_user" "app" {
  cluster_id = digitalocean_database_cluster.this.id
  name       = "${var.env}_app"
  # usado por: django, celery
  # permissoes: SELECT, INSERT, UPDATE, DELETE (configurar via django)
}

resource "digitalocean_database_user" "migrations" {
  cluster_id = digitalocean_database_cluster.this.id
  name       = "${var.env}_migrations"
  # usado por: ci/cd pipeline
  # permissoes: DDL - CREATE, ALTER, DROP (configurar via django)
}

resource "digitalocean_database_user" "readonly" {
  cluster_id = digitalocean_database_cluster.this.id
  name       = "${var.env}_readonly"
  # usado por: reports, bi, analytics
  # permissoes: SELECT only em views especificas (configurar via django)
}

resource "digitalocean_database_user" "maintenance" {
  cluster_id = digitalocean_database_cluster.this.id
  name       = "${var.env}_maintenance"
  # usado por: debug, suporte tecnico
  # permissoes: SELECT only em views de manutencao (dados anonimizados)
  # NUNCA dar acesso direto a tabelas com dados de clientes
}

// users - keycloak

resource "digitalocean_database_user" "keycloak" {
  cluster_id = digitalocean_database_cluster.this.id
  name       = "${var.env}_keycloak"
  # usado por: keycloak container no droplet
  # permissoes: full no database keycloak (keycloak gerencia proprio schema)
}

// connection pools - app
# pgbouncer gerencia conexoes - evita esgotar limite do postgres
# mode transaction: conexao liberada ao fim de cada transacao

resource "digitalocean_database_connection_pool" "app" {
  cluster_id = digitalocean_database_cluster.this.id
  name       = "${var.env}-app-pool"
  mode       = "transaction"
  size       = var.pool_size
  db_name    = digitalocean_database_db.main.name
  user       = digitalocean_database_user.app.name
  # django usa essa pool, nao conexao direta
}

resource "digitalocean_database_connection_pool" "readonly" {
  cluster_id = digitalocean_database_cluster.this.id
  name       = "${var.env}-readonly-pool"
  mode       = "transaction"
  size       = 5
  db_name    = digitalocean_database_db.main.name
  user       = digitalocean_database_user.readonly.name
  # reports usam pool menor - menos conexoes simultaneas
}

// connection pools - keycloak
# mode session: keycloak usa conexoes longas, nao funciona com transaction mode
# size 5: keycloak nao precisa de muitas conexoes simultaneas

resource "digitalocean_database_connection_pool" "keycloak" {
  cluster_id = digitalocean_database_cluster.this.id
  name       = "${var.env}-keycloak-pool"
  mode       = "session"
  size       = 5
  db_name    = digitalocean_database_db.keycloak.name
  user       = digitalocean_database_user.keycloak.name
}

// trusted sources
# controle de acesso do managed database
# vpc cidr: qualquer recurso na vpc pode conectar
# sem isso: banco fica aberto pra internet (risco grave)

resource "digitalocean_database_firewall" "this" {
  cluster_id = digitalocean_database_cluster.this.id

  rule {
    type  = "ip_addr"
    value = var.vpc_cidr
  }
}

// outputs - cluster

output "id" {
  value = digitalocean_database_cluster.this.id
}

output "name" {
  value = digitalocean_database_cluster.this.name
}

output "host" {
  value     = digitalocean_database_cluster.this.private_host
  sensitive = true
  # usar apenas pra debug - django usa pool
}

output "port" {
  value = digitalocean_database_cluster.this.port
}

output "database" {
  value = digitalocean_database_db.main.name
}

output "uri" {
  value     = digitalocean_database_cluster.this.private_uri
  sensitive = true
  # conexao direta - usar apenas pra debug ou migrations
}

output "urn" {
  value = digitalocean_database_cluster.this.urn
}

// outputs - app

output "app_user" {
  value = digitalocean_database_user.app.name
}

output "app_password" {
  value     = digitalocean_database_user.app.password
  sensitive = true
}

output "app_pool_uri" {
  value     = digitalocean_database_connection_pool.app.private_uri
  sensitive = true
  # USAR ESSE NO DJANGO - conexao via pgbouncer
}

output "app_pool_host" {
  value     = digitalocean_database_connection_pool.app.private_host
  sensitive = true
}

output "app_pool_port" {
  value = digitalocean_database_connection_pool.app.port
}

// outputs - migrations

output "migrations_user" {
  value = digitalocean_database_user.migrations.name
}

output "migrations_password" {
  value     = digitalocean_database_user.migrations.password
  sensitive = true
  # ci/cd usa pra rodar django migrate
}

// outputs - readonly

output "readonly_user" {
  value = digitalocean_database_user.readonly.name
}

output "readonly_password" {
  value     = digitalocean_database_user.readonly.password
  sensitive = true
}

output "readonly_pool_uri" {
  value     = digitalocean_database_connection_pool.readonly.private_uri
  sensitive = true
  # USAR ESSE EM REPORTS - conexao via pgbouncer
}

output "readonly_pool_host" {
  value     = digitalocean_database_connection_pool.readonly.private_host
  sensitive = true
}

output "readonly_pool_port" {
  value = digitalocean_database_connection_pool.readonly.port
}

// outputs - maintenance

output "maintenance_user" {
  value = digitalocean_database_user.maintenance.name
}

output "maintenance_password" {
  value     = digitalocean_database_user.maintenance.password
  sensitive = true
  # usar pra debug/suporte - so acessa views anonimizadas
}

// outputs - keycloak

output "keycloak_user" {
  value = digitalocean_database_user.keycloak.name
}

output "keycloak_password" {
  value     = digitalocean_database_user.keycloak.password
  sensitive = true
}

output "keycloak_pool_uri" {
  value     = digitalocean_database_connection_pool.keycloak.private_uri
  sensitive = true
  # USAR ESSE NO KEYCLOAK - conexao via pgbouncer (session mode)
}

output "keycloak_pool_host" {
  value     = digitalocean_database_connection_pool.keycloak.private_host
  sensitive = true
}

output "keycloak_pool_port" {
  value = digitalocean_database_connection_pool.keycloak.port
}