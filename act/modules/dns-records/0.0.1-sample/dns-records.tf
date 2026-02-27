# dns records for origin
#
# aponta domínios pro origin (LB)
# só cria records de origin quando lb_enabled = true
# page rules para redirects (.com → .com.br)
# www sempre redireciona pro root (www.site.com → site.com)
#
# nota: authenticated origin pulls (mTLS) removido
# motivo: proteção atual é suficiente:
# - LB faz SSL passthrough (não termina SSL)
# - firewall do LB só aceita IPs Cloudflare
# - droplet termina SSL com Origin CA certificate

terraform {
  required_providers {
    cloudflare   = { source = "cloudflare/cloudflare" }
    digitalocean = { source = "digitalocean/digitalocean" }
  }
}

// variables

variable "env" {
  type = string
}

variable "dns_records" {
  type = list(object({
    name        = string           # domínio sem www (ex: site.com.br)
    type        = string           # "origin" = aponta pro LB | "redirect" = redireciona pra outro domínio
    redirect_to = optional(string) # destino do redirect (só quando type = "redirect")
    create_api  = optional(bool)   # cria api.dominio? (default: false)

    subdomains = optional(list(object({
      name  = string           # nome do subdomínio (ex: "app" vira app.dominio.com)
      type  = string           # "A" = IP | "CNAME" = alias pra outro domínio
      value = optional(string) # valor do CNAME (A usa IP do LB automaticamente)
    })))
  }))

  # valida que type só pode ser "origin" ou "redirect"
  validation {
    condition = alltrue([
      for d in var.dns_records : contains(["origin", "redirect"], d.type)
    ])
    error_message = "Each domain type must be 'origin' or 'redirect'."
  }

  # valida que redirect_to é obrigatório quando type = "redirect"
  validation {
    condition = alltrue([
      for d in var.dns_records : d.type == "redirect" ? d.redirect_to != null : true
    ])
    error_message = "redirect_to is required when type is 'redirect'."
  }
}

variable "lb_enabled" {
  type = bool
  # true = LB existe, cria records apontando pro IP dele
  # false = LB não existe ainda, não cria records de origin (só redirects)
}

variable "proxied" {
  type = bool
  # true = tráfego passa pelo Cloudflare (CDN, WAF, DDoS protection)
  # false = DNS only, tráfego vai direto pro servidor (expõe IP real)
}

variable "ttl" {
  type = number
  # tempo em segundos que DNS fica em cache
  # se proxied = true, Cloudflare ignora esse valor
}

// data sources

# busca dados das zonas no Cloudflare pelo nome do domínio
data "cloudflare_zone" "zones" {
  for_each = { for d in var.dns_records : d.name => d }
  name     = each.key
}

# busca IP do Load Balancer (só se existir)
data "digitalocean_loadbalancer" "lb" {
  count = var.lb_enabled ? 1 : 0
  name  = "${var.env}-lb"
}

// locals

locals {
  # IP do LB ou null se não existir
  lb_ip = var.lb_enabled ? data.digitalocean_loadbalancer.lb[0].ip : null

  # separa domínios por tipo
  origin_domains   = { for d in var.dns_records : d.name => d if d.type == "origin" }
  redirect_domains = { for d in var.dns_records : d.name => d if d.type == "redirect" }

  # domínios origin só ficam ativos se LB existir
  # sem LB não tem pra onde apontar
  active_origin_domains = var.lb_enabled ? local.origin_domains : {}

  # monta map de subdomínios extras
  # chave: "dominio.com-subdominio" pra evitar conflito
  subdomains = var.lb_enabled ? merge([
    for d in var.dns_records : {
      for sub in coalesce(d.subdomains, []) : "${d.name}-${sub.name}" => {
        domain = d.name
        name   = sub.name
        type   = sub.type
        value  = sub.value
      }
    } if d.type == "origin"
  ]...) : {}
}

// origin domains - root (só se lb_enabled)
# record A: dominio.com → IP do LB

resource "cloudflare_record" "origin_root" {
  for_each = local.active_origin_domains

  zone_id = data.cloudflare_zone.zones[each.key].id
  name    = "@" # @ = root do domínio
  content = local.lb_ip
  type    = "A"
  ttl     = var.ttl
  proxied = var.proxied

  comment = "Managed by Terraform"
}

// origin domains - www (só se lb_enabled)
# record CNAME necessário pra page rule de redirect funcionar
# www.site.com → site.com (CNAME)
# page rule redireciona www → root (301)

resource "cloudflare_record" "origin_www" {
  for_each = local.active_origin_domains

  zone_id = data.cloudflare_zone.zones[each.key].id
  name    = "www"
  content = each.key # aponta pro domínio root
  type    = "CNAME"
  ttl     = var.ttl
  proxied = var.proxied # precisa ser true pra page rule funcionar

  comment = "Managed by Terraform - Redirects to root"
}

// origin domains - www redirect (só se lb_enabled)
# redireciona www.site.com → site.com
# motivo: www é legado, ninguém digita www hoje
# mas redirect evita quebrar links antigos indexados no Google

resource "cloudflare_page_rule" "origin_www_redirect" {
  for_each = local.active_origin_domains

  zone_id  = data.cloudflare_zone.zones[each.key].id
  target   = "www.${each.key}/*"
  priority = 1

  actions {
    forwarding_url {
      url         = "https://${each.key}/$1"
      status_code = 301 # permanente - browser cacheia
    }
  }
}

// origin domains - api (só se lb_enabled)
# record A: api.dominio.com → IP do LB
# usa A em vez de CNAME pra ter IP direto (alguns clients não resolvem CNAME bem)

resource "cloudflare_record" "origin_api" {
  for_each = { for k, v in local.active_origin_domains : k => v if coalesce(v.create_api, false) }

  zone_id = data.cloudflare_zone.zones[each.key].id
  name    = "api"
  content = local.lb_ip
  type    = "A"
  ttl     = var.ttl
  proxied = var.proxied

  comment = "Managed by Terraform"
}

// redirect domains - root (sempre cria, usa IP do LB ou placeholder)
# record A necessário pra page rule funcionar
# 192.0.2.1 = IP reservado pra documentação (RFC 5737)
# tráfego nunca chega nesse IP, Cloudflare intercepta antes e faz redirect

resource "cloudflare_record" "redirect_root" {
  for_each = local.redirect_domains

  zone_id = data.cloudflare_zone.zones[each.key].id
  name    = "@"
  content = coalesce(local.lb_ip, "192.0.2.1") # usa IP do LB se existir, senão placeholder
  type    = "A"
  ttl     = var.ttl
  proxied = var.proxied # precisa ser true pra page rule funcionar

  comment = "Managed by Terraform - Redirects to ${each.value.redirect_to}"
}

// redirect domains - www

resource "cloudflare_record" "redirect_www" {
  for_each = local.redirect_domains

  zone_id = data.cloudflare_zone.zones[each.key].id
  name    = "www"
  content = each.key
  type    = "CNAME"
  ttl     = var.ttl
  proxied = var.proxied

  comment = "Managed by Terraform - Redirects to ${each.value.redirect_to}"
}

// page rules - redirects
# redireciona todo tráfego do domínio pra outro
# 301 = redirect permanente (browser cacheia)
# $1 = captura o path e mantém no destino (ex: /about → destino/about)

resource "cloudflare_page_rule" "redirect_root" {
  for_each = local.redirect_domains

  zone_id  = data.cloudflare_zone.zones[each.key].id
  target   = "${each.key}/*" # * = qualquer path
  priority = 1

  actions {
    forwarding_url {
      url         = "https://${each.value.redirect_to}/$1"
      status_code = 301
    }
  }
}

resource "cloudflare_page_rule" "redirect_www" {
  for_each = local.redirect_domains

  zone_id  = data.cloudflare_zone.zones[each.key].id
  target   = "www.${each.key}/*"
  priority = 2

  actions {
    forwarding_url {
      url         = "https://${each.value.redirect_to}/$1"
      status_code = 301
    }
  }
}

// extra subdomains (só se lb_enabled)
# subdomínios customizados além de www e api

resource "cloudflare_record" "subdomain" {
  for_each = local.subdomains

  zone_id = data.cloudflare_zone.zones[each.value.domain].id
  name    = each.value.name
  content = each.value.type == "A" ? local.lb_ip : each.value.value # A usa IP do LB, CNAME usa value
  type    = each.value.type
  ttl     = var.ttl
  proxied = var.proxied

  comment = "Managed by Terraform"
}

// outputs

output "lb_ip" {
  value = local.lb_ip
}

output "lb_enabled" {
  value = var.lb_enabled
}

output "zone_ids" {
  value = { for k, v in data.cloudflare_zone.zones : k => v.id }
}

output "origin_domains" {
  value = keys(local.origin_domains)
}

output "redirect_domains" {
  value = keys(local.redirect_domains)
}

output "active_origin_domains" {
  value = keys(local.active_origin_domains)
}

output "urls" {
  value = var.lb_enabled ? {
    for k, v in local.origin_domains : k => {
      root = "https://${k}"
      api  = coalesce(v.create_api, false) ? "https://api.${k}" : null
    }
  } : {}
}