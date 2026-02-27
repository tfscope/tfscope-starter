# dns bots management
#
# controla acesso de bots e AI crawlers ao site
# configura robots.txt gerenciado e proteção contra scrapers
#
# depende do módulo dns-zone (usa zone_ids como input)
#
# não usa prevent_destroy porque destruir apenas reseta pro padrão da cloudflare

terraform {
  required_providers {
    cloudflare = { source = "cloudflare/cloudflare" }
  }
}

// variables

variable "zone_ids" {
  type        = map(string)
  description = "Map de domínio -> zone_id (output do módulo dns-zone)"
}

variable "ai_bots_protection" {
  type        = string
  description = "Bloquear AI crawlers: 'block' (todos), 'only_on_ad_pages' (só páginas com ads), 'disabled' (permite)"
}

variable "crawler_protection" {
  type        = string
  description = "Labirinto de links falsos pra AI scrapers: 'enabled' ou 'disabled'"
}

variable "managed_robots_txt" {
  type        = bool
  description = "Cloudflare gerencia robots.txt com regras de AI bots"
}

variable "enable_js" {
  type        = bool
  description = "JavaScript detection invisível pra identificar bots (requerido se fight_mode = true)"
}

variable "fight_mode" {
  type        = bool
  description = "Bot Fight Mode - desafia bots suspeitos com JS challenge (free plan)"
}

// resources

# bot management por zona
# controla como cloudflare lida com bots e AI crawlers
resource "cloudflare_bot_management" "bots" {
  for_each = var.zone_ids

  zone_id = each.value

  # bloqueia AI crawlers (GPTBot, ClaudeBot, Bytespider, etc)
  # "block" = bloqueia todos
  # "only_on_ad_pages" = bloqueia só em páginas com anúncios
  # "disabled" = permite (default)
  ai_bots_protection = var.ai_bots_protection

  # labirinto de links falsos pra AI scrapers
  # crawlers ficam presos seguindo links infinitos
  # "enabled" = ativa armadilha
  # "disabled" = desativado (default)
  crawler_protection = var.crawler_protection

  # robots.txt gerenciado pela cloudflare
  # prepende regras de bloqueio ao seu robots.txt existente
  # se não tiver robots.txt, cloudflare cria um
  is_robots_txt_managed = var.managed_robots_txt

  # javascript detection invisível
  # injeta JS pra identificar bots
  # requerido se fight_mode = true
  enable_js = var.enable_js

  # bot fight mode (disponível no free plan)
  # desafia bots suspeitos com javascript challenge
  fight_mode = var.fight_mode
}

// outputs

output "bot_management_ids" {
  value       = { for k, v in cloudflare_bot_management.bots : k => v.id }
  description = "Map de domínio -> bot_management resource id"
}

output "ai_bots_protection" {
  value       = var.ai_bots_protection
  description = "Proteção contra AI crawlers: block/only_on_ad_pages/disabled"
}

output "crawler_protection" {
  value       = var.crawler_protection
  description = "Proteção crawler maze: enabled/disabled"
}

output "managed_robots_txt" {
  value       = var.managed_robots_txt
  description = "Cloudflare gerencia robots.txt"
}

output "enable_js" {
  value       = var.enable_js
  description = "JavaScript detection ativo"
}

output "fight_mode_enabled" {
  value       = var.fight_mode
  description = "Bot Fight Mode está ativo"
}
