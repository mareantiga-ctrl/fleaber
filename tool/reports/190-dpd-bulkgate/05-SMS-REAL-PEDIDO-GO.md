# SMS real — pedido de GO (ainda NÃO enviado)

## Estado técnico

- Phone Auth PROD: activado  
- Send SMS Hook → `send-sms-bulkgate`  
- `OPS_SMS_SEND_ENABLED=0` → **nenhum SMS pago sai** até GO  
- Falta: `BULKGATE_APPLICATION_TOKEN` em CredMan/Edge (ficheiro local)

## Quando autorizares

| Campo | Valor |
|-------|--------|
| Conta BulkGate | App **Fleaber Auth** · Application ID **37873** |
| Destino | número que indicares (mascarado `***XXXX` nas provas) |
| Fluxo | App → Verificar telemóvel → OTP 6 dígitos → confirmar |
| Custo estimado | ~0,014–0,05 € / SMS PT (confirmar lista de preços; saldo ~788 créditos) |
| Acção C1 | `OPS_SMS_SEND_ENABLED=1` → 1 envio → verificar → preferível voltar a `0` |

Responde no chat apenas: **GO SMS** + número (ou «usa o meu número de teste X»).  
Não coloques o Application Token no chat.
