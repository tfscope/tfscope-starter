# firewall: libera entrada do load balancer pro droplet
#
# dependencia: apply 'lb' antes deste modulo
# 
# fluxo:
#   internet -> cloudflare -> lb -> [este firewall] -> droplet:80
#
# regra:
#   - entrada: porta 80, somente do lb
#   - saida: automatica (firewall guarda estado da conexao, resposta volta sozinha)
#   - todo resto: bloqueado
#
# por que precisa do ID do LB:
#   digitalocean nao aceita tag como origem pra lb no firewall
#   so aceita o ID direto (source_load_balancer_uids)
#
# tags que o droplet precisa ter:
#   {env}:role:app    -> este firewall se aplica
#   {env}:fw:inet-out -> saida pra internet (outro firewall)

terraform {
  required_providers {
    digitalocean = { source = "digitalocean/digitalocean" }
  }
}

// variables

variable "env" {
  type = string
}

variable "tag_role_app" {
  type = string
}

variable "lb_id" {
  type        = string
  description = "LB UID - obtem do output do modulo lb"
}

// firewall

resource "digitalocean_firewall" "this" {
  lifecycle { create_before_destroy = true } # ⚠️

  name = "${var.env}-fw-app-in"
  tags = [var.tag_role_app]

  inbound_rule {
    protocol                  = "tcp"
    port_range                = "80"
    source_load_balancer_uids = [var.lb_id]
  }
}

// outputs

output "name" {
  value = digitalocean_firewall.this.name
}

output "id" {
  value = digitalocean_firewall.this.id
}
