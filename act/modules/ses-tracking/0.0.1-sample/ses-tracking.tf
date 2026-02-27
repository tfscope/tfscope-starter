# ses tracking
#
# Configuration Set + SNS topic para tracking de eventos de email
# rastreia: SEND, DELIVERY, BOUNCE, COMPLAINT, OPEN, CLICK, REJECT
#
# cada domínio tem seu próprio configuration set (isolamento de reputação)
# Django consome eventos via SNS → webhook
#
# --- bugs conhecidos (AWS provider v5) ---
#
# 1. matching_event_types drift (issue #36896, fix v5.67.0)
#    provider reordena a lista alfabeticamente no state, causando diff falso a cada plan.
#    solução: declarar matching_event_types em ordem alfabética.
#
# 2. delivery_options.max_delivery_seconds (issue #40591, #40836)
#    se declarar delivery_options com tls_policy sem max_delivery_seconds, dá erro
#    "must be greater than or equal to 300".
#    solução: não declarar delivery_options — SES usa defaults (TLS opportunistic).
#
# 3. suppressed_reasons lista vazia (issue #28669)
#    suppressed_reasons = [] dá erro "requires 1 item minimum".
#    solução: sempre passar pelo menos 1 item — usamos ["BOUNCE", "COMPLAINT"].
#
# --- como usar no Django ---
#
# 1. ENVIO: ao enviar email pelo SES (boto3), passar o configuration set:
#
#    ses_client.send_email(
#        ConfigurationSetName="tracking-site-com-br",
#        FromEmailAddress="noreply@site.com.br",
#        ...
#    )
#
# 2. WEBHOOK: criar endpoint no Django pra receber notificações do SNS:
#
#    POST /webhooks/ses/  (público, sem auth)
#
#    - primeira request do SNS é SubscriptionConfirmation → Django faz GET na SubscribeURL pra confirmar
#    - requests seguintes são Notification → body contém JSON com o evento SES
#
# 3. EVENTOS: o JSON do SNS contém eventType com um destes valores:
#
#    | eventType  | Significado                          | Ação no Django                           |
#    |------------|--------------------------------------|------------------------------------------|
#    | Send       | email enviado ao SES                 | log                                      |
#    | Delivery   | SES entregou ao servidor destino     | log                                      |
#    | Bounce     | email voltou (endereço inválido)     | marcar email como inválido, não reenviar |
#    | Complaint  | destinatário marcou como spam        | marcar email, parar de enviar            |
#    | Open       | destinatário abriu o email           | log (tracking pixel 1x1)                 |
#    | Click      | destinatário clicou num link         | log (redirect via SES)                   |
#    | Reject     | SES rejeitou antes de enviar         | log + alerta                             |
#
# 4. SNS SUBSCRIPTION: após o terraform apply, criar a subscription no SNS:
#
#    AWS Console → SNS → Topics → ses-tracking-{tenant} → Create subscription
#    Protocol: HTTPS
#    Endpoint: https://{domain}/webhooks/ses/
#
#    ou via Terraform (quando o Django estiver pronto):
#    aws_sns_topic_subscription com protocol = "https" e endpoint = url do webhook
#
# 5. VERIFICAÇÃO: SNS valida o endpoint antes de enviar eventos.
#    Django precisa responder ao SubscriptionConfirmation fazendo GET na SubscribeURL.
#    Sem isso, o SNS não envia notificações.
#
# 6. SEGURANÇA: validar header x-amz-sns-message-type e verificar assinatura SNS
#    pra garantir que requests vêm da AWS e não de terceiros.
#    lib: https://github.com/aws/aws-php-sns-message-validator (conceito, adaptar pra Python)

terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "env" {
  type = string

  validation {
    condition     = var.env == "prod"
    error_message = "SES tracking layers só existem em prod."
  }
}

variable "domain" {
  type        = string
  description = "Domínio associado (ex: site.com.br)"
}

variable "tenant" {
  type        = string
  description = "Nome do tenant/locatário SES (ex: site-com-br). Usado nos nomes dos recursos."
}

# --- SNS topic ---

resource "aws_sns_topic" "ses_events" {
  name = "ses-tracking-${var.tenant}"

  tags = {
    ManagedBy = "Terraform"
    Env       = var.env
  }
}

# --- SNS topic policy ---
# permite que o SES publique no topic

data "aws_caller_identity" "current" {}

resource "aws_sns_topic_policy" "ses_publish" {
  arn = aws_sns_topic.ses_events.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSESPublish"
        Effect    = "Allow"
        Principal = { Service = "ses.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.ses_events.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# --- Configuration Set ---

resource "aws_sesv2_configuration_set" "tracking" {
  configuration_set_name = "tracking-${var.tenant}"

  # não declarar delivery_options (bug #40591 — max_delivery_seconds required)

  reputation_options {
    reputation_metrics_enabled = true
  }

  sending_options {
    sending_enabled = true
  }

  # não usar lista vazia (bug #28669 — requires 1 item minimum)
  suppression_options {
    suppressed_reasons = ["BOUNCE", "COMPLAINT"]
  }

  tags = {
    ManagedBy = "Terraform"
    Env       = var.env
    Domain    = var.domain
  }
}

# --- Event Destination ---
# matching_event_types em ordem alfabética (bug #36896 — evita drift)

resource "aws_sesv2_configuration_set_event_destination" "sns" {
  configuration_set_name = aws_sesv2_configuration_set.tracking.configuration_set_name
  event_destination_name = "sns-${var.tenant}"

  event_destination {
    enabled = true

    matching_event_types = [
      "BOUNCE",
      "CLICK",
      "COMPLAINT",
      "DELIVERY",
      "OPEN",
      "REJECT",
      "SEND",
    ]

    sns_destination {
      topic_arn = aws_sns_topic.ses_events.arn
    }
  }
}

# --- outputs ---

output "configuration_set_name" {
  value = aws_sesv2_configuration_set.tracking.configuration_set_name
}

output "sns_topic_arn" {
  value = aws_sns_topic.ses_events.arn
}

output "sns_topic_name" {
  value = aws_sns_topic.ses_events.name
}
