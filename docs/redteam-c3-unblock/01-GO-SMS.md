# Pedido GO SMS — verificação Cláudia (…5912)

## Confirmação técnica (pré-GO)

| Check | Estado |
|-------|--------|
| Phone Auth PROD | ligado |
| Send SMS Hook | ligado → `…/functions/v1/send-sms-bulkgate` |
| Secrets BulkGate (ID/token/sender/hook) | presentes em PROD |
| CredMan local | Application ID + Token + Hook secret |
| `OPS_SMS_SEND_ENABLED` | **0** (nenhum SMS pago) |
| Limites | `sms_max_frequency=60s`, `rate_limit_sms_sent=30`, OTP 6 dígitos |
| Diagnóstico falha Cláudia | Auth→Hook→Edge; bloqueio kill-switch; BulkGate **não** chamada |
| APK 1881 | **não** precisa update para este teste |

## O que o GO activa

1. C1 põe temporariamente `OPS_SMS_SEND_ENABLED=1` em PROD Edge secrets.
2. **Uma** tentativa controlada: verificar telemóvel na app (número …5912).
3. C1 lê Auth + Edge + (se visível) aceitação BulkGate — **sem** registar OTP.
4. Confirma contigo se o SMS chegou e se a verificação fechou.
5. C1 põe de imediato `OPS_SMS_SEND_ENABLED=0` (mesmo se falhar).

## Destino / custo

| Campo | Valor |
|-------|--------|
| Destino | número da Cláudia terminado em **5912** (E.164 PT) |
| Conta BulkGate | App Fleaber Auth · Application ID **37873** |
| Custo estimado | ~0,02–0,05 € / SMS PT (saldo ~7,9 créditos na última sonda) |
| Retries | **proibidos** sem novo GO |
| DPD / Stripe LIVE | **não** alterados |

## Como autorizar

Responde no chat exactamente:

`GO SMS …5912`

Sem essa frase, o interruptor permanece em `0`.
