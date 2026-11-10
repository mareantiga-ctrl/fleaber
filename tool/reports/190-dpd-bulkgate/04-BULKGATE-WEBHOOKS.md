# BulkGate delivery webhooks vs Supabase Send SMS Hook

## Não confundir

| Mecanismo | Dono | Para quê |
|-----------|------|----------|
| **Supabase Auth → Send SMS Hook** | Supabase | GoTrue chama a Edge `send-sms-bulkgate` para **enviar** o OTP |
| **BulkGate delivery / status webhooks** | BulkGate portal | Relatórios de entrega (delivered/failed) **depois** do envio |

## Precisamos dos webhooks de entrega BulkGate?

**Não**, para fechar verificação de telemóvel no Auth.

O fluxo Fleaber é:

1. App pede SMS (`updateUser` / `resend` phone)
2. Supabase gera OTP e chama o **Send SMS Hook**
3. Edge envia via BulkGate transactional API
4. Utilizador introduz o código → `verifyOTP`

A confirmação **não** depende de callback de entrega BulkGate. Sem webhooks de delivery, o OTP continua válido.

## Quando fariam sentido (fase futura)

- Painel ops «SMS falhou na operadora»
- Alertas de saldo / falhas em massa

Fora do âmbito ZIP 190 / fecho Auth.
