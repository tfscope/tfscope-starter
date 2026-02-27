# tailscale acl - regras de acesso da vpn
#
# o que faz:
#   - configura quem pode acessar o que dentro do tailscale
#   - define regras de ssh (quem pode conectar nos droplets)
#
# regras configuradas:
#   - acesso de rede: so membros do tailnet acessam porta 22 (ssh)
#   - ssh: so o usuario configurado pode conectar
#   - ssh em dev/staging: accept (sem re-autenticacao)
#   - ssh em prod: check (pede re-autenticacao)
#
# como funciona o ssh via tailscale:
#   1. usuario faz login no tailscale (google sso)
#   2. tenta conectar no droplet: tailscale ssh user@dev-app
#   3. se prod: pede re-autenticacao (check mode)
#   4. se dev/staging: conecta direto (accept mode)
#   5. root nao eh permitido (so o ssh_user)
#
# sobre root:
#   - root existe no droplet (nao eh removido)
#   - ssh via tailscale como root: bloqueado pela acl
#   - apos conectar como ssh_user, pode usar sudo su
#
# token do tailscale:
#   - gerar em: https://login.tailscale.com/admin/settings/keys
#   - expira em 90 dias (renovar antes)
#   - cada env tem seu proprio tailnet (conta google separada)

terraform {
  required_providers {
    tailscale = { source = "tailscale/tailscale" }
  }
}

// variables

variable "env" {
  type = string
}

variable "ssh_user" {
  type        = string
  description = "Username for SSH access via Tailscale (non-root)"
}

// locals

locals {
  # dev/staging: accept (pratico) | prod: check (seguro)
  ssh_action = var.env == "prod" ? "check" : "accept"
}

// acl

resource "tailscale_acl" "this" {
  reset_acl_on_destroy       = false # ao destruir, mantem acl no tailscale
  overwrite_existing_content = true  # sobrescreve acl existente sem erro

  acl = jsonencode({
    # regra de rede: membros do tailnet acessam so porta 22
    acls = [
      {
        action = "accept"
        src    = ["autogroup:member"]
        dst    = ["autogroup:self:22"]
      }
    ]
    # regra de ssh: membros podem ssh como ssh_user
    ssh = [
      {
        action = local.ssh_action     # check (prod) ou accept (dev/staging)
        src    = ["autogroup:member"] # quem pode conectar
        dst    = ["autogroup:self"]   # onde pode conectar
        users  = [var.ssh_user]       # como qual usuario
      }
    ]
  })
}

// outputs

output "ssh_user" {
  value       = var.ssh_user
  description = "SSH user configured in ACL"
}

output "ssh_action" {
  value       = local.ssh_action
  description = "SSH action mode (check or accept)"
}
