# SMS — causas comprovadas + estado

## SMS permanente

`OPS_SMS_SEND_ENABLED=1` em PROD (digest sha256("1"), desde 2026-11-10T10:00:32Z).  
**Não** será desligado automaticamente após testes.

## Falha ao introduzir o 1.º código

| Campo | Valor |
|-------|--------|
| Log | `POST /verify` @ **09:54:01Z** |
| Erro | `token has expired or is invalid` |
| `error_code` | **`otp_expired`** |
| Timeline | SMS aceite @ **09:40:08Z** → verify ~14 min depois |
| Config então | `sms_otp_exp=**60**` segundos |

**Causa:** OTP expirou (validade 60s demasiado curta).

**Correcção Auth:** `sms_otp_exp=600` (10 min). Mantido `sms_max_frequency=60`.

## Falha no reenvio

Após o GO SMS controlado, C1 voltou a pôr `OPS_SMS_SEND_ENABLED=0` (procedimento antigo).  
Reenvio da app → Auth → hook → kill-switch → erro genérico na UI.

**Causa:** kill-switch OFF (não rate-limit).  
**Correcção:** SMS permanente ON.

## App

Mensagens amigáveis para `otp_expired` / rate-limit / código inválido em  
`lib/utils/phone_verification_service.dart` (branch C3).  
APK 1881 continua a funcionar com Auth; UX melhor com build futuro.

## Verificação completa …5912

**FAIL** até confirmação na app (`phone_confirmed` ainda false).  
Pedir código **novo** agora (SMS ligado + 10 min).
