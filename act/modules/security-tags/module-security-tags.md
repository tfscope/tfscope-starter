# module: security-tags

## Descrição

Gerenciamento centralizado de tags de segurança e informativas.

Este módulo cria tags que controlam acesso a recursos e identificam recursos para billing/organização. Centralizar as tags em um único módulo facilita auditoria e compliance (ISO 27001, SOC 2).

## Tipos de tags

Este módulo cria três tipos de tags com propósitos diferentes:

1. **Tags de firewall** — controlam regras de rede via Cloud Firewall
2. **Tags de role** — identificam recursos para Load Balancer
3. **Tags informativas** — identificam recursos para billing/organização (sem função de segurança)

**Importante:** Esses são os únicos tipos de tags. Outros tipos comuns (ambiente, custo, projeto, ownership) não são criados aqui.

## Por que centralizar?

- Mudanças de permissão rastreadas em um único lugar
- Auditor pergunta "quem tem acesso ao banco?" → olha um arquivo só
- Evita tags avulsas fora de controle
- Facilita compliance (SOC 2, ISO 27001)

---

## Diferença importante: firewall vs role vs info

**Tags de firewall (`fw_*`):**
- Tag identifica quais Droplets recebem as regras do Cloud Firewall
- **PRECISA de outro módulo** (`fw-inet-out`) que cria as regras (portas 80, 443, 53, 123)
- Sem o módulo de firewall, a tag não faz nada

**Tags de role (`role_*`):**
- Tag é usada diretamente pelo serviço
- LB: `droplet_tag = role_app` → já funciona
- **NÃO precisa de módulo extra**

**Tags informativas (`info_*`):**
- Tag é apenas para identificação (billing, organização, filtros no painel)
- **NÃO tem função de segurança**
- Managed Databases usam VPC CIDR no Trusted Sources, não tags

---

## Tags de firewall

### O que são

Tags aplicadas a Droplets para que o Cloud Firewall aplique regras de rede.

### Como funcionam

1. Droplet recebe a tag no momento da criação
2. Cloud Firewall tem regras associadas a essa tag
3. Firewall aplica as regras apenas aos Droplets com a tag

**Exemplo:** Droplet com tag `dev:fw:inet-out` → Cloud Firewall libera saída HTTPS pra internet.

### ⚠️ Tag de firewall sozinha não faz nada

A tag `fw_inet_out` identifica quais Droplets recebem as regras.

**Você PRECISA aplicar o módulo `fw-inet-out`** que cria as regras de firewall (portas, protocolos).

Sem o módulo de firewall aplicado, a tag existe mas não faz nada.

### Tags disponíveis

Prefixo: `{env}:fw:*`

| Tag | Output | O que permite | Módulo necessário |
|-----|--------|---------------|-------------------|
| `{env}:fw:inet-out` | `fw_inet_out` | Saída pra internet (HTTP, HTTPS, DNS, NTP) | `fw-inet-out` |

### Onde são definidas as portas?

A tag só identifica o recurso. As **portas e protocolos** são definidos no módulo de firewall:

| Módulo | Portas |
|--------|--------|
| `fw-inet-out` | 80, 443 (HTTP/S), 53 (DNS), 123 (NTP) |

### Serviços cobertos por tags de firewall

| Serviço | Como funciona |
|---------|---------------|
| **DO Monitoring** | Agente envia métricas via HTTPS → usa `fw_inet_out` |
| **DO Spaces** | Django acessa via HTTPS API → usa `fw_inet_out` |
| **Tailscale** | VPN mesh via UDP/HTTPS → usa `fw_inet_out` |
| **DO Managed OpenSearch** | Envia logs via HTTPS → usa `fw_inet_out` |

### Tags de firewall que não existem (e por quê)

**`{env}:fw:postgres`** — Postgres é managed, usa Trusted Sources com VPC CIDR (não Cloud Firewall).

**`{env}:fw:valkey`** — Valkey é managed, usa Trusted Sources com VPC CIDR (não Cloud Firewall).

**`{env}:fw:load-balancer`** — Load Balancer não suporta Cloud Firewall. Proteção via allow-list de IPs (configurável via CLI/API).

**`{env}:fw:admin`** — SSH é via Tailscale only, sem porta 22 pra internet.

**`{env}:fw:storage`** — Spaces é acessado via HTTPS API com autenticação por API key. Django (no Droplet) precisa de `fw_inet_out` para fazer requests HTTPS, mas o controle de acesso é feito pelas credenciais do Spaces, não por tags de firewall.

**`{env}:fw:monitoring`** — Agente de monitoring envia dados via HTTPS (já coberto por `fw_inet_out`).

**`{env}:fw:opensearch`** — OpenSearch managed recebe logs via HTTPS (já coberto por `fw_inet_out`).

**`{env}:fw:uptime`** — Uptime faz health checks externos pro Load Balancer (proteção via configuração do próprio LB).

---

## Tags de role

### O que são

Tags que identificam o tipo/função do servidor. Usadas pelo Load Balancer.

### Como funcionam

1. Droplet recebe a tag de role no momento da criação
2. Load Balancer usa `role_app` pra saber quais Droplets recebem tráfego

### ✅ Tag funciona direto (não precisa de módulo extra)

Diferente das tags de firewall, as tags de role **funcionam sozinhas**.

Basta:
1. Droplet ter a tag
2. Load Balancer referenciar a tag

Exemplo:
- LB: `droplet_tag = role_app` → já funciona

**Não precisa de módulo extra.**

### Tags disponíveis

Prefixo: `{env}:role:*`

| Tag | Output | Função | Módulo necessário |
|-----|--------|--------|-------------------|
| `{env}:role:app` | `role_app` | Load Balancer manda tráfego pro Droplet | Nenhum |

### Serviços que usam tags de role

| Serviço | Como funciona |
|---------|---------------|
| **DO Load Balancer** | Droplets com `role_app` recebem tráfego do LB |

---

## Tags informativas

### O que são

Tags apenas para identificação de recursos. Usadas para billing, organização e filtros no painel da DigitalOcean.

### ⚠️ NÃO têm função de segurança

Essas tags **não controlam acesso**. A segurança dos Managed Databases é feita via Trusted Sources com VPC CIDR.

### Por que usar VPC CIDR em vez de tags nos databases?

- **Tag:** só droplets com tag específica conectam
- **VPC CIDR:** qualquer recurso na VPC conecta (droplets, postgres, valkey)
- **Log forwarding nativo só funciona com VPC CIDR** (recomendação DigitalOcean)

### Tags disponíveis

Prefixo: `{env}:info:*`

| Tag | Output | Função |
|-----|--------|--------|
| `{env}:info:postgres` | `info_postgres` | Identifica cluster Postgres (billing/organização) |
| `{env}:info:valkey` | `info_valkey` | Identifica cluster Valkey (billing/organização) |
| `{env}:info:opensearch` | `info_opensearch` | Identifica cluster OpenSearch (billing/organização) |

### Exemplo de uso
```hcl
resource "digitalocean_database_cluster" "postgres" {
  name   = "${var.env}-postgres"
  engine = "pg"
  # ...
  tags   = [data.terraform_remote_state.security_tags.outputs.info_postgres]
}
```

---

## Por que só essas tags?

Usamos **serviços managed** da DigitalOcean. Serviços managed não usam Cloud Firewall — cada um tem proteção própria:

| Serviço | Tipo | Proteção |
|---------|------|----------|
| Load Balancer | Managed | `droplet_tag = role_app` + IPs permitidos (Cloudflare) |
| Postgres | Managed Database | Trusted Sources (VPC CIDR) |
| Valkey | Managed Database | Trusted Sources (VPC CIDR) |
| OpenSearch | Managed | Trusted Sources (VPC CIDR) |
| Spaces (S3) | Managed | HTTPS API + API key |

**Resultado:** Só o Droplet precisa de tags de segurança (único recurso que usa Cloud Firewall).

---

## Como usar na prática

1. Aplica este módulo primeiro (`make tf` → `security-tags`)
2. Outros módulos consomem as tags via `terraform_remote_state`
3. Droplet recebe as tags na criação
4. Load Balancer usa tag de role
5. Databases usam VPC CIDR no Trusted Sources + tag informativa

### Exemplo: Tag de firewall

⚠️ **Lembre-se:** precisa do módulo `fw-inet-out` aplicado pra funcionar.
```hcl
data "terraform_remote_state" "security_tags" {
  backend = "s3"
  config = { ... }
}

resource "digitalocean_firewall" "inet_out" {
  tags = [data.terraform_remote_state.security_tags.outputs.fw_inet_out]
}
```

### Exemplo: Tag de role (Load Balancer)

✅ Funciona direto, não precisa de módulo extra.
```hcl
resource "digitalocean_loadbalancer" "this" {
  name        = "${var.env}-lb"
  droplet_tag = data.terraform_remote_state.security_tags.outputs.role_app
}
```

### Exemplo: Trusted Sources com VPC CIDR

✅ Segurança via VPC CIDR (recomendação DigitalOcean).
```hcl
resource "digitalocean_database_firewall" "postgres" {
  cluster_id = digitalocean_database_cluster.postgres.id

  rule {
    type  = "ip_addr"
    value = var.vpc_cidr
  }
}
```

### Exemplo: Tag informativa (Database)

ℹ️ Apenas para billing/organização.
```hcl
resource "digitalocean_database_cluster" "postgres" {
  name   = "${var.env}-postgres"
  tags   = [data.terraform_remote_state.security_tags.outputs.info_postgres]
}
```

---

## Adicionando novas tags

1. Adiciona o resource em `modules/security-tags/security-tags.tf`
2. Adiciona o output correspondente
3. Atualiza esta documentação
4. Aplica: `make tf` → `security-tags` → `plan` → `apply`

---

## Por que não tem `prevent_destroy`?

Tags usam `create_before_destroy` mas não `prevent_destroy` porque:

- **Terraform já impede deleção acidental:** Tentar deletar tag em uso → Terraform falha (dependência)
- **Flexibilidade:** Remover tag obsoleta não fica travado
- **`create_before_destroy`:** Ao renomear tag → cria nova → atualiza recursos → deleta antiga

**Impacto de ficar sem tag:**

| Recurso | O que acontece |
|---------|----------------|
| Droplet | Firewall não aplica regras → tráfego bloqueado (deny by default) |
| Firewall | Sem tags associadas, regras não se aplicam a nenhum recurso |

---

## Uso
```hcl
module "security_tags" {
  source = "../../modules/security-tags"
  env    = var.env
}
```

---

## Comandos úteis
```bash
# listar tags
doctl compute tag list
```
```bash
# ver droplets com uma tag específica
doctl compute tag get dev:role:app
```
```bash
# listar firewalls com regras e tags
doctl compute firewall list --format ID,Name,InboundRules,OutboundRules,Tags
```
```bash
# ver portas liberadas pra uma tag específica
doctl compute firewall list --format Name,InboundRules,OutboundRules,Tags --no-header | grep "dev:fw:inet-out"
```

---

## Referências

- Cloud Firewall: https://docs.digitalocean.com/products/networking/firewalls/
- Cloud Firewall Limits: https://docs.digitalocean.com/products/networking/firewalls/details/limits/
- Database Trusted Sources: https://docs.digitalocean.com/products/databases/postgresql/how-to/secure/
- Load Balancer Firewall: https://docs.digitalocean.com/products/networking/load-balancers/how-to/manage/
- Monitoring Agent: https://docs.digitalocean.com/products/monitoring/how-to/install-metrics-agent/