# module: dns-records

Records DNS apontando pro origin.

---

## O que cria

- Record A para root domain
- Record CNAME para www (redireciona pro root)
- Record A para api (opcional)
- Page rules para redirects (.com → .com.br)
- Page rule www → root (sem www)
- Subdomains extras (opcional)

---

## Data sources

Módulo busca tudo internamente, não precisa de remote_state:

| Recurso | Como busca |
|---------|------------|
| Cloudflare zones | pelo valor de `dns_records[].name` no tfvars |
| DigitalOcean LB | pelo nome `${env}-lb` (ex: `dev-lb`) |

---

## Fluxo

O módulo busca o IP do Load Balancer automaticamente.

| lb_enabled | Resultado |
|------------|-----------|
| false | Só redirects e page rules (sem LB) |
| true | Records apontam pro IP do LB |

---

## www

Sempre redireciona pro root (www.site.com → site.com).

Ninguém usa www hoje, mas redirect evita quebrar links antigos.

---

## Authenticated Origin Pulls (mTLS)

Removido. Proteção atual é suficiente:
- LB faz SSL passthrough (não termina SSL)
- Firewall do LB só aceita IPs Cloudflare
- Droplet termina SSL com Origin CA certificate

---

## Como usar

1. Cria LB (módulo loadbalancer)
2. Altera `{env}.tfvars`: `lb_enabled = true`
3. Roda `make tf` → dns-records → apply

---

## Subdomains (exemplos)

Infra flexível - subdomains são opcionais. Exemplos comentados no tfvars:

| Subdomain | Tipo | O que faz |
|-----------|------|-----------|
| app | A | `app.dominio.com.br` → IP do LB |
| admin | A | `admin.dominio.com.br` → IP do LB |
| mail | CNAME | `mail.dominio.com.br` → webmail Google |

---

## Múltiplos redirects

Redireciona `.com` → `.com.br`. Cada redirect cria records e page rules automaticamente.

---

## Dependências

**Pré-requisitos:** dns-zone, loadbalancer (se lb_enabled = true)

**Dependentes:** Nenhum