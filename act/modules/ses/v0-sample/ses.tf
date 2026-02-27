# SES identity + DKIM + MAIL FROM
#
# cria domínio verificado no SES com:
# - Easy DKIM (RSA_2048_BIT) — gera 3 tokens DKIM
# - MAIL FROM customizado (mail.dominio)
#
# outputs: dkim_tokens para zona J (Email DNS) criar CNAMEs no Cloudflare

terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "env" {
  type = string

  validation {
    condition     = var.env == "prod"
    error_message = "SES layers só existem em prod."
  }
}

variable "domain" {
  type        = string
  description = "Domínio principal (ex: empresamais.com.br)"
}

variable "mail_from_subdomain" {
  type        = string
  default     = "mail"
  description = "Subdomínio do MAIL FROM (ex: mail → mail.empresamais.com.br)"
}

# --- identity ---

resource "aws_sesv2_email_identity" "domain" {
  email_identity = var.domain

  dkim_signing_attributes {
    next_signing_key_length = "RSA_2048_BIT"
  }

  tags = {
    ManagedBy = "Terraform"
    Env       = var.env
  }
}

# --- MAIL FROM ---

resource "aws_sesv2_email_identity_mail_from_attributes" "mail_from" {
  email_identity         = aws_sesv2_email_identity.domain.email_identity
  mail_from_domain       = "${var.mail_from_subdomain}.${var.domain}"
  behavior_on_mx_failure = "REJECT_MESSAGE"
}

# --- outputs ---

output "domain" {
  value = var.domain
}

output "dkim_tokens" {
  description = "3 DKIM tokens gerados pelo SES — usar pra criar CNAMEs no Cloudflare"
  value       = aws_sesv2_email_identity.domain.dkim_signing_attributes[0].tokens
}

output "mail_from_domain" {
  value = "${var.mail_from_subdomain}.${var.domain}"
}

output "verified" {
  value = aws_sesv2_email_identity.domain.verified_for_sending_status
}
