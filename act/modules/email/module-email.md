# module: email

Records DNS para email (MX, SPF, DKIM, DMARC, MAIL FROM).

---

## Provider Cloudflare v4 vs v5

| | v4 (atual) | v5 (futuro) |
|--|-----------|-------------|
| Resource | `cloudflare_record` | `cloudflare_dns_record` |
| Atributo | `content` (v4.52.5 já aceita, `value` depreciado) | `content` |
| Provider | `4.52.5` | `5.x` |

Módulo usa v4 com `content`. Quando migrar pro v5, trocar apenas `cloudflare_record` → `cloudflare_dns_record`.

---

## O que cria

- MX records (servidores de email + MAIL FROM)
- TXT records (SPF, DMARC)
- CNAME records (DKIM via SES — gerados automaticamente a partir dos dkim_tokens)

---

## Stack de email

| Função | Tecnologia | Custo |
|--------|-----------|-------|
| Envio transacional (30k/mês) | Amazon SES (us-east-1) | ~$3/mês |
| Recebimento | Amazon SES Inbound → SNS → webhook → Django | incluso no SES |
| DNS (MX, SPF, DKIM, DMARC) | Cloudflare DNS via Terraform | grátis |
| Monitoramento DMARC | Cloudflare DMARC Management | grátis |
| Sistema de tickets | Django (próprio) | — |

**Decisão:** Não usa Google Workspace. Todo email é transacional (sistema envia/recebe automaticamente).

**Decisão:** Dmarcian substituído por Cloudflare DMARC Management (economia ~$240/ano).

---

## Autenticação de email

Quatro camadas de proteção:

| Record | Tipo | O que faz | Exemplo |
|--------|------|-----------|---------|
| SPF | TXT em `@` | Lista servidores autorizados a enviar | `v=spf1 include:amazonses.com ~all` |
| DKIM | CNAME em `selector._domainkey` | Assinatura digital no email | 3 CNAMEs gerados pelo SES |
| DMARC | TXT em `_dmarc` | Regra: rejeita se SPF/DKIM falharem | `v=DMARC1; p=reject` |
| MAIL FROM | MX + TXT em `mail.` | Alinha envelope domain com From header | `mail.dominio.com.br` |

**Como funciona:** Quando alguém recebe email do seu domínio, o servidor (Gmail, Outlook, etc) verifica automaticamente SPF + DKIM. Se não passar → email rejeitado. A pessoa nem recebe na caixa de entrada.

**MAIL FROM customizado:** Sem MAIL FROM customizado, o envelope sender é `amazonses.com`. Com MAIL FROM customizado (`mail.seudominio.com.br`), o SPF alinha com o From header → DMARC passa por alinhamento SPF → pré-requisito pra BIMI.

---

## DMARC políticas

| Política | Ação |
|----------|------|
| `p=none` | Só monitora (relatórios) |
| `p=quarantine` | Manda pra spam |
| `p=reject` | Rejeita o email |

**Decisão:** Usando `p=reject` desde o início. Todos os emails saem do SES com SPF + DKIM configurados — não há risco de rejeitar emails legítimos.

---

## Como usar

### Passo 1: Aplicar zona I (SES)

A zona I cria as identities no SES via Terraform (módulo `ses`). Cada layer gera 3 DKIM tokens automaticamente.
```bash
# no menu make tf, aplica os 4 layers SES:
# ia--ses-alvaramunicipal
# ib--ses-bydavi
# ic--ses-empresamais
# id--ses-ofisek
```

### Passo 2: Preencher tfvars

DKIM CNAMEs vêm automaticamente do `terraform_remote_state` da zona I. Não precisa declarar `cname_records` — o módulo monta internamente.
```terraform
email_domains = {
  alias-mais = [
    {
      name = "empresamais.com.br"

      mx_records = [
        # recebimento (SES Inbound)
        { name = "@", priority = 10, value = "inbound-smtp.us-east-1.amazonaws.com" },
        # MAIL FROM customizado
        { name = "mail", priority = 10, value = "feedback-smtp.us-east-1.amazonses.com" },
      ]

      txt_records = [
        # SPF domínio raiz: só SES pode enviar
        { name = "@", value = "v=spf1 include:amazonses.com ~all" },
        # SPF MAIL FROM
        { name = "mail", value = "v=spf1 include:amazonses.com ~all" },
        # DMARC
        { name = "_dmarc", value = "v=DMARC1; p=reject" },
      ]
    },

    # domínio secundário — proteção contra spoofing
    {
      name = "empresamais.com"

      mx_records = []

      txt_records = [
        { name = "@", value = "v=spf1 -all" },
        { name = "_dmarc", value = "v=DMARC1; p=reject" },
      ]
    }
  ]
}
```

### Passo 3: Aplicar DNS no Cloudflare
```bash
terraform apply
```

Verifica em https://dash.cloudflare.com → DNS → se os records MX, SPF, DKIM (CNAME) e DMARC foram criados.

### Passo 4: Verificar no SES

Volta no AWS Console → SES → Verified identities. Status deve mudar pra **Verified**.

**Nota:** Pode levar até 72h pro SES verificar os registros DNS.

### Passo 5: Configurar SES Inbound

1. SES → Email receiving → Rule sets
2. Cria rule set com ação SNS
3. SNS envia webhook pro Django
4. Django processa o email recebido

### Passo 6: Sair do Sandbox

SES começa em modo sandbox (só envia pra emails verificados). Pra enviar pra qualquer destinatário:

1. SES → Account dashboard → Request production access
2. Descreve teu caso de uso
3. AWS aprova em ~24h

### Passo 7: Monitorar DMARC no Cloudflare

1. Cloudflare dashboard → domínio → Email → DMARC Management
2. Ativa o monitoramento
3. Dashboard mostra relatórios de autenticação automaticamente

---

## Fluxo completo
```
Enviar: Django → SES API → cliente recebe email
Receber: cliente responde → SES Inbound → SNS → webhook → Django processa
```

---

## DKIM tokens (automático)

O módulo recebe `dkim_tokens` (list de 3 strings) via `terraform_remote_state` da zona I (SES). Internamente, monta os 3 CNAMEs:
```
token._domainkey → token.dkim.amazonses.com
```

Lógica: domínio com `mx_records` (principal) → recebe DKIM do SES. Domínio sem `mx_records` (secundário/defensivo) → sem DKIM.

Pra domínios defensivos (ofisec), `dkim_tokens = []` — nenhum CNAME é criado.

---

## Records por domínio (resumo)

Cada domínio principal cria 9 records no Cloudflare:

| # | Tipo | Nome | Função |
|---|------|------|--------|
| 1 | MX | `@` | Recebimento (SES Inbound) |
| 2 | MX | `mail` | MAIL FROM (envelope sender) |
| 3 | TXT | `@` | SPF (autorização de envio) |
| 4 | TXT | `mail` | SPF do MAIL FROM |
| 5 | TXT | `_dmarc` | DMARC (política de rejeição) |
| 6 | CNAME | `seletor1._domainkey` | DKIM assinatura 1 |
| 7 | CNAME | `seletor2._domainkey` | DKIM assinatura 2 |
| 8 | CNAME | `seletor3._domainkey` | DKIM assinatura 3 |

Cada domínio secundário (anti-spoofing) cria 2 records:

| # | Tipo | Nome | Função |
|---|------|------|--------|
| 1 | TXT | `@` | SPF `-all` (bloqueia envio) |
| 2 | TXT | `_dmarc` | DMARC `reject` (rejeita tudo) |

---

## Configuração SES por domínio

| Domínio | MAIL FROM | DKIM | MX Failure |
|---------|-----------|------|------------|
| alvaramunicipal.com.br | mail.alvaramunicipal.com.br | RSA_2048_BIT | Reject |
| bydavi.com.br | mail.bydavi.com.br | RSA_2048_BIT | Reject |
| empresamais.com.br | mail.empresamais.com.br | RSA_2048_BIT | Reject |
| ofisek.com | mail.ofisek.com | RSA_2048_BIT | Reject |

---

## Dependências

**Pré-requisitos:** dns-zone (zona E), ses (zona I)

**Dependentes:** Nenhum

---

## Domínios sem email (proteção contra spoofing)

Domínios que não usam email (ex: `.com` que redireciona pro `.com.br`) também precisam de proteção. Sem SPF/DMARC, golpistas podem falsificar emails usando esse domínio.

**Configuração bloqueadora:**
```terraform
{
  name = "exemplo.com"

  mx_records = []

  txt_records = [
    { name = "@", value = "v=spf1 -all" },
    { name = "_dmarc", value = "v=DMARC1; p=reject" },
  ]
}
```

| Record | Significado |
|--------|-------------|
| `v=spf1 -all` | Nenhum servidor pode enviar email por este domínio |
| `p=reject` | Rejeita qualquer email que tente usar este domínio |

**Resultado:** Se alguém tentar enviar email fingindo ser `@exemplo.com`, o servidor do destinatário rejeita automaticamente.

---

## URLs de referência

| Serviço | URL |
|---------|-----|
| AWS SES Console | https://console.aws.amazon.com/ses |
| Cloudflare DNS | https://dash.cloudflare.com |
| Cloudflare DMARC Management | https://dash.cloudflare.com → Email → DMARC Management |