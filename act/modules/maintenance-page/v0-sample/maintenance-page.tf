# cloudflare worker for maintenance page
#
# when origin returns 502/503/504, shows custom html from github
# update the html anytime without redeploy

terraform {
  required_providers {
    cloudflare = { source = "cloudflare/cloudflare" }
  }
}

// data source - get zone and account info

data "cloudflare_zone" "zone" {
  name = var.maintenance_domain
}

// variables

variable "env" {
  type = string
}

variable "maintenance_domain" {
  type        = string
  description = "Domain to attach worker (e.g. site.com.br)"
}

variable "maintenance_page_url" {
  type        = string
  description = "URL to fetch maintenance page HTML"
}

// worker script

resource "cloudflare_workers_script" "maintenance" {
  account_id = data.cloudflare_zone.zone.account_id
  name       = "${var.env}-maintenance"
  content    = <<-JS
addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  const response = await fetch(request)
  
  // intercept server errors
  if (response.status === 502 || response.status === 503 || response.status === 504) {
    try {
      const maintenancePage = await fetch('${var.maintenance_page_url}')
      const html = await maintenancePage.text()
      
      return new Response(html, {
        status: response.status,
        headers: { 
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'no-cache, no-store, must-revalidate'
        }
      })
    } catch (e) {
      // fallback if github is unreachable
      return new Response('Sistema em manutenção. Tente novamente em alguns minutos.', {
        status: response.status,
        headers: { 'Content-Type': 'text/plain; charset=utf-8' }
      })
    }
  }
  
  return response
}
JS
}

// route - attach worker to domain

resource "cloudflare_workers_route" "maintenance" {
  zone_id     = data.cloudflare_zone.zone.id
  pattern     = "${var.maintenance_domain}/*"
  script_name = cloudflare_workers_script.maintenance.name
}

// outputs

output "worker_name" {
  value       = cloudflare_workers_script.maintenance.name
  description = "Worker script name"
}

output "route_pattern" {
  value       = cloudflare_workers_route.maintenance.pattern
  description = "Route pattern"
}
