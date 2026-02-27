# cloudflare origin ca certificate
#
# - covers: domain + *.domain (one level only)
# - not covered: nested subdomains (sub.api.domain)
#
# important:
# - valid 15 years, no auto-renewal
# - expires ~2041: recreate via terraform (downtime expected)
#
# redirect handling:
# - .com domains redirect to .com.br via cloudflare page rules (dns-records module)
# - only .com.br domains need origin ca certificate this module
# - .com traffic never reaches origin server (no certificate needed)

terraform {
  required_providers {
    cloudflare = { source = "cloudflare/cloudflare" }
    tls        = { source = "hashicorp/tls" }
  }
}

// variables

variable "cert_ca_origin_domain" {
  type        = string
  description = "Domain for Origin CA certificate (e.g., site.com.br). Wildcard *.domain included automatically."
}

// private key

resource "tls_private_key" "origin" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

// certificate signing request

resource "tls_cert_request" "origin" {
  private_key_pem = tls_private_key.origin.private_key_pem

  subject {
    common_name  = var.cert_ca_origin_domain
    organization = "Cloudflare Origin CA"
  }
}

// cloudflare origin certificate

resource "cloudflare_origin_ca_certificate" "origin" {
  csr                = tls_cert_request.origin.cert_request_pem
  hostnames          = [var.cert_ca_origin_domain, "*.${var.cert_ca_origin_domain}"]
  request_type       = "origin-rsa"
  requested_validity = 5475 # 15 years
}

// outputs

output "certificate" {
  value       = cloudflare_origin_ca_certificate.origin.certificate
  sensitive   = true
  description = "Origin CA certificate PEM"
}

output "private_key" {
  value       = tls_private_key.origin.private_key_pem
  sensitive   = true
  description = "Private key PEM"
}

output "expires_on" {
  value       = cloudflare_origin_ca_certificate.origin.expires_on
  description = "Certificate expiration date"
}

output "hostnames" {
  value       = cloudflare_origin_ca_certificate.origin.hostnames
  description = "Hostnames covered by certificate"
}
