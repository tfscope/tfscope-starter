# terraform/modules/cdn/cdn.tf

# cdn storage
#
# o que é: bucket R2 (storage da cloudflare) pra servir arquivos estáticos
# pra que serve: centraliza imagens, fontes, scripts, css, JSON de configuração
# como funciona: sites fazem request → cloudflare serve o arquivo do R2
#
# exemplos de uso:
# - imagens de assinatura de email (Gmail, Outlook, Yahoo precisam acessar)
# - fontes, ícones, assets públicos
# - JSON de configuração consumido pelos sites
#
# segurança:
# - WAF bloqueia métodos que não sejam GET/HEAD
# - CORS wildcard (*) — público, qualquer origin pode ler
# - proxied pelo cloudflare (DDoS protection)
# - operationally read-only via custom domain (upload precisa de API key S3/R2)
# - dados sensíveis ficam no backend (Django), não no CDN
#
# custo: R2 não cobra egress (transferência), só armazenamento
# isso é o diferencial vs S3 da AWS que cobra por GB transferido

terraform {
  required_providers {
    cloudflare = { source = "cloudflare/cloudflare" }
  }
}

// variables

variable "env" {
  type        = string
  description = "CDN layers só rodam em prod. Dev usa os buckets de prod diretamente."

  validation {
    condition     = var.env == "prod"
    error_message = "CDN layers só existem em prod. Dev usa os buckets de prod diretamente."
  }
}

variable "account_id" {
  type        = string
  description = "Cloudflare account ID - vem do output do dns-zone"
}

variable "zone_ids" {
  type        = map(string)
  description = "Map de domínio -> zone_id - vem do output do dns-zone"
}

variable "bucket_name" {
  type        = string
  description = "Nome do bucket R2 (ex: cdn-site-com-br)"
}

variable "location" {
  type        = string
  description = "Região do bucket: WNAM, ENAM, WEUR, EEUR, APAC"
}

variable "custom_domain" {
  type        = string
  description = "Subdomínio completo (ex: cdn.site.com.br)"
}

// locals
//
// aqui fica a lógica do módulo
// extrai o domínio base do custom_domain pra buscar o zone_id correto

locals {
  # custom_domain = "cdn.site.com.br"
  # split(".") = ["cdn", "site", "com", "br"]
  # queremos: "site.com.br" (últimos 3 elementos pra domínio .com.br)
  #
  # lógica: pega tudo depois do primeiro elemento (remove "cdn")
  domain_parts = split(".", var.custom_domain)

  # junta de volta sem o primeiro elemento
  # slice(list, start, end) - pega do índice 1 até o final
  zone_domain = join(".", slice(local.domain_parts, 1, length(local.domain_parts)))

  # busca o zone_id no map
  zone_id = var.zone_ids[local.zone_domain]
}

// resources

# bucket R2
# é como uma "pasta" no cloud onde os arquivos ficam
# compatível com API S3 da AWS (pode usar aws cli, rclone, etc)
resource "cloudflare_r2_bucket" "bucket" {
  account_id = var.account_id
  name       = var.bucket_name
  location   = var.location
}

# CORS nativo do R2
# wildcard (*) porque é público — Gmail, Outlook, Yahoo precisam acessar
# sem CORS configurado, browsers podem bloquear fetch() cross-origin
#
# por que wildcard é seguro aqui:
# - conteúdo é público (imagens, fontes, assets, JSON de configuração)
# - não há cookies/credentials envolvidos
# - operationally read-only via custom domain
# - dados sensíveis ficam no backend, não no CDN
#
# headers: só o necessário pra cache/ETag/range
# Origin / Accept: compatibilidade com preflight e clients variados
# Content-Type: tipo do arquivo
# If-Modified-Since / If-None-Match: cache condicional (304 Not Modified)
# Range: download parcial (fontes, arquivos grandes)
resource "cloudflare_r2_bucket_cors" "cors" {
  account_id  = var.account_id
  bucket_name = cloudflare_r2_bucket.bucket.name

  rules = [{
    allowed = {
      methods = ["GET", "HEAD"]
      origins = ["*"]
      headers = ["Origin", "Accept", "Content-Type", "If-Modified-Since", "If-None-Match", "Range"]
    }
    id              = "Public access"
    max_age_seconds = 86400
  }]
}

# custom domain R2
# vincula o domínio customizado ao bucket R2
# sem isso, o Cloudflare retorna erro 1014
resource "cloudflare_r2_custom_domain" "cdn" {
  account_id  = var.account_id
  bucket_name = cloudflare_r2_bucket.bucket.name
  domain      = var.custom_domain
  zone_id     = local.zone_id
  enabled     = true
}

# record DNS
# aponta cdn.site.com → bucket R2
# proxied = true significa que tráfego passa pelo cloudflare (CDN, WAF, DDoS protection)
# se proxied = false, expõe o endpoint direto (não queremos isso)
resource "cloudflare_dns_record" "cdn" {
  zone_id = local.zone_id
  name    = var.custom_domain
  type    = "CNAME"
  content = "${cloudflare_r2_bucket.bucket.id}.r2.cloudflarestorage.com"
  proxied = true
  ttl     = 1

  comment = "Managed by Terraform - R2 CDN"
}

# WAF rule - bloqueia métodos que não sejam GET/HEAD
# CDN serve arquivos, não aceita POST/PUT/DELETE/PATCH
# reduz superfície de ataque e ruído de scanners
resource "cloudflare_ruleset" "waf" {
  zone_id = local.zone_id
  name    = "R2 CDN - WAF rules"
  kind    = "zone"
  phase   = "http_request_firewall_custom"

  rules = [
    {
      action      = "block"
      expression  = "(http.host eq \"${var.custom_domain}\" and http.request.method ne \"GET\" and http.request.method ne \"HEAD\")"
      description = "Block non-GET/HEAD methods"
      enabled     = true
    }
  ]
}

// outputs

output "bucket_id" {
  value       = cloudflare_r2_bucket.bucket.id
  description = "R2 bucket ID"
}

output "bucket_name" {
  value       = cloudflare_r2_bucket.bucket.name
  description = "R2 bucket name"
}

output "endpoint" {
  value       = "${cloudflare_r2_bucket.bucket.id}.r2.cloudflarestorage.com"
  description = "Endpoint S3-compatible - usa pra upload via aws cli ou rclone"
}

output "public_url" {
  value       = "https://${var.custom_domain}"
  description = "URL pública - seus sites usam essa URL pra consumir os arquivos"
}
