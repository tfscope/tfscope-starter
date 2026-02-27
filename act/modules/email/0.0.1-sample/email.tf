# email dns records
#
# MX, SPF, DKIM, DMARC, MAIL FROM para email
# independente de infra (não precisa de LB/Droplet)
#
# DKIM CNAMEs: montados a partir dos dkim_tokens (zona I → SES)
#
# PROVIDER v4: usa cloudflare_record + content (value depreciado na v4.52.5)
# quando migrar pro v5: trocar cloudflare_record → cloudflare_dns_record
#
# TXT RECORDS: módulo adiciona aspas automaticamente no content (RFC 1035)
# no tfvars, escreva valores SEM aspas — o módulo envolve com \" automaticamente

terraform {
  required_providers {
    cloudflare = { source = "cloudflare/cloudflare" }
  }
}

variable "env" {
  type        = string
  description = "Email layers só rodam em prod."

  validation {
    condition     = var.env == "prod"
    error_message = "Email layers só existem em prod."
  }
}

variable "email_domains" {
  type = list(object({
    name = string

    mx_records = optional(list(object({
      name     = optional(string, "@")
      priority = number
      value    = string
    })), [])

    txt_records = optional(list(object({
      name  = string
      value = string # escreva SEM aspas — módulo adiciona automaticamente
    })), [])
  }))

  description = "List of domains with email records"
  default     = []
}

variable "dkim_tokens" {
  type        = list(string)
  description = "3 DKIM tokens do SES (via terraform_remote_state). Vazio pra domínios defensivos."
  default     = []
}

variable "ttl" {
  type        = number
  default     = 1 # auto
  description = "TTL in seconds (1 = auto)"
}

// data source

data "cloudflare_zone" "zones" {
  for_each = { for d in var.email_domains : d.name => d }
  name     = each.key
}

// locals

locals {
  mx_records = merge([
    for d in var.email_domains : {
      for idx, mx in d.mx_records : "${d.name}-mx-${idx}" => {
        domain   = d.name
        name     = mx.name
        priority = mx.priority
        value    = mx.value
      }
    }
  ]...)

  txt_records = merge([
    for d in var.email_domains : {
      for idx, txt in d.txt_records : "${d.name}-txt-${idx}" => {
        domain = d.name
        name   = txt.name
        value  = txt.value
      }
    }
  ]...)

  # DKIM CNAMEs — montados a partir dos tokens do SES
  # associados ao domínio que tem mx_records (domínio principal)
  primary_domain = try([for d in var.email_domains : d.name if length(d.mx_records) > 0][0], "")

  cname_records = {
    for idx, token in var.dkim_tokens : "${local.primary_domain}-cname-${idx}" => {
      domain = local.primary_domain
      name   = "${token}._domainkey"
      value  = "${token}.dkim.amazonses.com"
    }
  }
}

// MX records

resource "cloudflare_record" "mx" {
  for_each = local.mx_records

  zone_id  = data.cloudflare_zone.zones[each.value.domain].id
  name     = each.value.name
  content  = each.value.value
  type     = "MX"
  priority = each.value.priority
  ttl      = var.ttl
  proxied  = false # email não pode ser proxied

  comment = "Managed by Terraform"
}

// TXT records (SPF, DMARC)
# content envolve valor com aspas (RFC 1035)
# sem aspas, Cloudflare dashboard mostra warning amarelo

resource "cloudflare_record" "txt" {
  for_each = local.txt_records

  zone_id = data.cloudflare_zone.zones[each.value.domain].id
  name    = each.value.name
  content = "\"${each.value.value}\""
  type    = "TXT"
  ttl     = var.ttl
  proxied = false

  comment = "Managed by Terraform"
}

// CNAME records (DKIM via SES)

resource "cloudflare_record" "cname" {
  for_each = local.cname_records

  zone_id = data.cloudflare_zone.zones[each.value.domain].id
  name    = each.value.name
  content = each.value.value
  type    = "CNAME"
  ttl     = var.ttl
  proxied = false # DKIM não pode ser proxied

  comment = "Managed by Terraform"
}

// outputs

output "mx_records" {
  value = [for k, v in local.mx_records : "${v.domain} ${v.name} -> ${v.value} (priority ${v.priority})"]
}

output "txt_records" {
  value = [for k, v in local.txt_records : "${v.domain} ${v.name}"]
}

output "cname_records" {
  value = [for k, v in local.cname_records : "${v.domain} ${v.name}"]
}

output "domains_configured" {
  value = [for d in var.email_domains : d.name]
}
