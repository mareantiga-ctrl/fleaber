# BulkGate + Supabase Auth (SMS OTP)

A app usa `PhoneVerificationService` → Supabase Auth (`resend` / `verifyOTP`).  
O Supabase **não tem** BulkGate built-in — activa o **Send SMS Hook** para esta função.

## 1. Segredos (Dashboard, nunca no Git)

[Supabase](https://supabase.com/dashboard) → **Project Settings** → **Edge Functions** → **Secrets**:

| Secret | Valor |
|--------|--------|
| `BULKGATE_APPLICATION_ID` | ID da app no portal BulkGate |
| `BULKGATE_APPLICATION_TOKEN` | Token da app |
| `BULKGATE_SENDER_LABEL` | Opcional — texto remetente (ex. `Fleaber`) |
| `SEND_SMS_HOOK_SECRET` | Gerado no passo 3 (`v1,whsec_…`) |

**Se colaste as chaves no chat:** revoga/regenera no [BulkGate Portal](https://portal.bulkgate.com) e usa só os novos valores nos Secrets.

## 2. Deploy da função

```powershell
cd c:\Users\Casa\Desktop\Fleaber\fleaber
npx supabase functions deploy send-sms-bulkgate --no-verify-jwt
```

(`--no-verify-jwt` — o hook é chamado pelo serviço Auth, não pelo cliente.)

## 3. Activar o hook

**Authentication** → **Hooks** → **Send SMS**:

1. Enable **Send SMS hook**
2. Type: **HTTPS**
3. URL: `https://<PROJECT_REF>.supabase.co/functions/v1/send-sms-bulkgate`
4. Copiar o **Hook secret** → colar em `SEND_SMS_HOOK_SECRET` (formato `v1,whsec_…`)

## 4. Auth — Phone

**Authentication** → **Providers** → **Phone**: activar.

Opcional (testes): **Authentication** → **Phone** → test OTP para o teu número.

## 5. BulkGate Portal

- App API **transactional** (não marketing)
- Remetente `gText` / label **Fleaber** aprovado para PT
- Saldo / limite diário

## 6. Testar

1. Registo na app → sheet «Verificar telemóvel»
2. Número PT `9xxxxxxxx` → receber SMS
3. Logs: **Edge Functions** → `send-sms-bulkgate`

## Erros comuns

| Erro | Acção |
|------|--------|
| `401 Unknown identity` | ID/token errados ou app inactiva |
| Hook 500 / `Invalid payload sent to hook` | `SEND_SMS_HOOK_SECRET` não coincide; ou a função devolveu HTTP ≠ 200 (erros devem ser JSON com status **200**) |
| SMS não chega | Verificar remetente PT no BulkGate; evitar spam filters |
