# dns zone settings
#
# configura SSL, security, cache, performance
# zona deve existir no cloudflare (criada manualmente uma vez)
#
# não usa prevent_destroy porque zone_settings_override só customiza settings
# destruir o recurso apenas reseta pro padrão da cloudflare, não deleta a zona
#
# AVISO: cloudflare_zone_settings_override foi removido no provider v5
# quando migrar pro v5, substituir por cloudflare_zone_setting (recursos individuais)
# cloudflare vai lançar ferramenta de migração em março/2026
#
# EMERGÊNCIA: under_attack mode usar via CLI ou UI (não gerenciado aqui)

terraform {
  required_providers {
    cloudflare = { source = "cloudflare/cloudflare" }
  }
}

// variables

variable "zone_domains" {
  type        = list(string)
  description = "Domínios sem www (ex: ['site.com.br', 'site.com'])"
}

// data sources

# busca dados da zona pelo nome do domínio
# retorna zone_id e account_id que serão usados nos outros recursos
data "cloudflare_zone" "zones" {
  for_each = toset(var.zone_domains)
  name     = each.key
}

// resources

# aplica configurações na zona
# settings não especificados mantêm o valor atual da cloudflare
resource "cloudflare_zone_settings_override" "settings" {
  for_each = toset(var.zone_domains)

  zone_id = data.cloudflare_zone.zones[each.key].id

  settings {
    # ssl/tls
    ssl                      = "strict" # valida certificado do origin server
    always_use_https         = "on"     # redireciona http -> https
    min_tls_version          = "1.2"    # bloqueia TLS 1.0 e 1.1 (inseguros)
    tls_1_3                  = "on"     # habilita TLS 1.3 (mais rápido e seguro)
    automatic_https_rewrites = "on"     # reescreve links http para https no html
    opportunistic_encryption = "on"     # permite https mesmo sem certificado no origin

    # hsts - força browser a só acessar via https
    # max_age = 6 meses (padrão recomendado)
    # include_subdomains = true (api.dominio também)
    # preload = false (requer submissão manual em hstspreload.org)
    # nosniff = true (bloqueia MIME type sniffing)
    security_header {
      enabled            = true
      max_age            = 15552000 # 6 meses em segundos
      include_subdomains = true
      preload            = false
      nosniff            = true
    }

    # security
    security_level = "medium" # emergência: usar CLI pra "under_attack"
    challenge_ttl  = 1800     # tempo (seg) que visitante fica liberado após captcha
    browser_check  = "on"     # bloqueia bots com headers suspeitos

    # performance (free plan)
    brotli      = "on" # compressão melhor que gzip
    early_hints = "on" # envia hints 103 antes da resposta (preload assets)
    http3       = "on" # habilita QUIC/HTTP3

    # cache
    # Django controla via headers Cache-Control
    # não setamos browser_cache_ttl, cache_level nem development_mode aqui

    # websocket
    websockets = "on" # necessário para django channels

    # network
    ip_geolocation = "on" # adiciona header CF-IPCountry
    ipv6           = "on" # habilita IPv6

    # outros
    always_online      = "on"  # mostra cache se origin cair (pode estar deprecated)
    email_obfuscation  = "on"  # ofusca emails no html contra scrapers
    hotlink_protection = "off" # permite embed de imagens em outros sites
  }
}

# dnssec - assina respostas DNS pra proteger contra spoofing
# domínios .com (Cloudflare Registrar): DS record é configurado automaticamente
# domínios .com.br (Registro.br): copiar DS record do output e adicionar manualmente
resource "cloudflare_zone_dnssec" "dnssec" {
  for_each = toset(var.zone_domains)

  zone_id = data.cloudflare_zone.zones[each.key].id
}

// outputs

output "zone_ids" {
  value       = { for k, v in data.cloudflare_zone.zones : k => v.id }
  description = "Map de domínio -> zone_id"
}

output "account_id" {
  value       = data.cloudflare_zone.zones[var.zone_domains[0]].account_id
  description = "Account ID da Cloudflare"
}

output "dnssec_ds_records" {
  value = { for k, v in cloudflare_zone_dnssec.dnssec : k => {
    ds_record  = v.ds
    algorithm  = v.algorithm
    digest     = v.digest
    key_tag    = v.key_tag
    public_key = v.public_key
  } }
  description = "DS records pra configurar no registrador (Registro.br pra .com.br)"
}

output "dnssec_status" {
  value       = { for k, v in cloudflare_zone_dnssec.dnssec : k => v.status }
  description = "Status do DNSSEC por domínio (active, pending, disabled)"
}

output "settings_applied" {
  value = { for k, v in cloudflare_zone_settings_override.settings : k => {
    ssl              = v.settings[0].ssl
    min_tls_version  = v.settings[0].min_tls_version
    tls_1_3          = v.settings[0].tls_1_3
    always_use_https = v.settings[0].always_use_https
    security_level   = v.settings[0].security_level
    hsts_enabled     = v.settings[0].security_header[0].enabled
    hsts_max_age     = v.settings[0].security_header[0].max_age
    brotli           = v.settings[0].brotli
    http3            = v.settings[0].http3
    websockets       = v.settings[0].websockets
    ipv6             = v.settings[0].ipv6
  } }
  description = "Settings aplicados por domínio"
}
