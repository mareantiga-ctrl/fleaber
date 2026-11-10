# BulkGate + Supabase Auth (SMS OTP)

A app usa `PhoneVerificationService` → Supabase Auth (`updateUser` / `resend` / `verifyOTP`).  
O Supabase **não tem** BulkGate built-in — activa o **Send SMS Hook** para esta função.

## Kill-switch (ZIP 190)

| Secret | Valor | Efeito |
|--------|--------|--------|
| `OPS_SMS_SEND_ENABLED` | `0` (default seguro) | Hook responde 503 — **não** chama BulkGate |
| `OPS_SMS_SEND_ENABLED` | `1` | Permite envio real (só com GO) |

Mesmo com Phone hook ligado, SMS pagos ficam bloqueados até `OPS_SMS_SEND_ENABLED=1`.

## Produção Fleaber

| Item | Valor |
|------|--------|
| **Project ref** | `bpmpkzwnrbmuqnhgdscf` |
| **URL hook** | `https://bpmpkzwnrbmuqnhgdscf.supabase.co/functions/v1/send-sms-bulkgate` |

ZIP 190: função deployada; `BULKGATE_SENDER_LABEL` + kill-switch presentes; **faltam** ID/token/hook secret + activar Phone provider.

## Staging Fleaber (projecto histórico / testes)

| Item | Valor |
|------|--------|
| **Project ref** | `fxdknzrqjenzqcvnwqqq` |
| **URL** | `https://fxdknzrqjenzqcvnwqqq.supabase.co` |
| **Confirmação app** | `lib/backend/supabase/supabase.dart` → `_kSupabaseUrl` deve apontar para o ref acima |

Se o erro mencionar `SEND_SMS_HOOK_SECRET`, o hook SMS **não está configurado** (ou o secret não coincide) neste projecto.

## 1. Segredos (Dashboard ou CLI — nunca no Git)

### Dashboard

[Supabase Dashboard](https://supabase.com/dashboard/project/fxdknzrqjenzqcvnwqqq/settings/functions) → **Project Settings** → **Edge Functions** → **Secrets**:

| Secret | Valor |
|--------|--------|
| `BULKGATE_APPLICATION_ID` | ID da app no portal BulkGate |
| `BULKGATE_APPLICATION_TOKEN` | Token da app |
| `BULKGATE_SENDER_LABEL` | Opcional — texto remetente (ex. `Fleaber`) |
| `SEND_SMS_HOOK_SECRET` | Gerado no passo 3 (`v1,whsec_…`) — **nome exacto, case-sensitive** |

### Supabase CLI (staging)

```powershell
cd c:\Users\Casa\Desktop\Fleaber\fleaber
npx supabase login

# Substituir pelos valores reais (nunca commitar)
npx supabase secrets set BULKGATE_APPLICATION_ID="SEU_ID" --project-ref fxdknzrqjenzqcvnwqqq
npx supabase secrets set BULKGATE_APPLICATION_TOKEN="SEU_TOKEN" --project-ref fxdknzrqjenzqcvnwqqq
npx supabase secrets set BULKGATE_SENDER_LABEL="Fleaber" --project-ref fxdknzrqjenzqcvnwqqq
npx supabase secrets set SEND_SMS_HOOK_SECRET="v1,whsec_COPIAR_DO_DASHBOARD" --project-ref fxdknzrqjenzqcvnwqqq
```

Listar secrets (nomes apenas): `npx supabase secrets list --project-ref fxdknzrqjenzqcvnwqqq`

**Se colaste as chaves no chat:** revoga/regenera no [BulkGate Portal](https://portal.bulkgate.com) e usa só os novos valores nos Secrets.

## 2. Deploy da função

```powershell
cd c:\Users\Casa\Desktop\Fleaber\fleaber
npx supabase functions deploy send-sms-bulkgate --no-verify-jwt --project-ref fxdknzrqjenzqcvnwqqq
```

(`--no-verify-jwt` — o hook é chamado pelo serviço Auth, não pelo cliente.)

## 3. Activar o hook

**Authentication** → **Hooks** → **Send SMS**:

1. Enable **Send SMS hook**
2. Type: **HTTPS**
3. URL: `https://fxdknzrqjenzqcvnwqqq.supabase.co/functions/v1/send-sms-bulkgate`
4. Copiar o **Hook secret** → colar em `SEND_SMS_HOOK_SECRET` (formato `v1,whsec_…`) — **tem de ser idêntico** ao secret da Edge Function

## 4. Auth — Phone

**Authentication** → **Providers** → **Phone**: activar.

Opcional (testes): **Authentication** → **Phone** → test OTP para o teu número.

## 5. BulkGate Portal

- App API **HTTP Simple API** (Modules & APIs) — **não** Marketing, **não** Advanced
- Copiar **Application ID** + **Application token** (só estes dois campos)
- Remetente `gText` / label **Fleaber** aprovado para PT
- Saldo / limite diário

### Dois tokens parecidos no portal?

Só precisas de **Application token** (par com o Application ID). O portal por vezes mostra:

| O que vês | Usar para Supabase? |
|-----------|---------------------|
| **Application token** | **Sim** → `BULKGATE_APPLICATION_TOKEN` |
| Token antigo após **Regenerate** | **Não** — só o token activo |
| Universal token / conta | **Não** |
| Segredo de webhook / delivery report | **Não** |

Se não tiveres a certeza: **Regenerate application token** na app HTTP Simple (ID 37873), copia **só o token novo**, ou testa objectivamente:

```powershell
$env:BULKGATE_APPLICATION_ID = "37873"
$env:BULKGATE_APPLICATION_TOKEN = "colar_token_1"
$env:BULKGATE_APPLICATION_TOKEN_2 = "colar_token_2"
dart run tool/bulkgate_credentials_probe.dart
```

O que der **PASS** é o correcto para `BULKGATE_APPLICATION_TOKEN` no Supabase.

## Diagnóstico objectivo (B2)

Script: **`dart run tool/sms_hook_staging_diagnose.dart`**

Verifica (sem expor secrets):

| # | Check |
|---|--------|
| 0 | App aponta para `fxdknzrqjenzqcvnwqqq` |
| 1 | Function `send-sms-bulkgate` deployada (HTTP) |
| 2 | Secrets `SEND_SMS_HOOK_SECRET`, `BULKGATE_*` listados (CLI) |
| 4 | Auth Hook enabled + URI correcta (Management API) |
| 5 | Fingerprint Auth secret ↔ local `SEND_SMS_HOOK_SECRET` |
| 6–7 | Probe directo à Edge Function (secrets runtime + assinatura) |
| 8 | Erro real GoTrue (`updateUser phone`) |

**Comparação completa de secrets (passos 4–5–7):**

```powershell
$env:SUPABASE_ACCESS_TOKEN = "sbp_..."   # Dashboard → Account → Access Tokens
$env:SEND_SMS_HOOK_SECRET = "v1,whsec_..."   # o MESMO valor do Hook Auth
dart run tool/sms_hook_staging_diagnose.dart
```

Relatório JSON: `tool/reports/sms_hook_staging_diagnose_*.json`  
Saída inclui `PRIMARY_CAUSE` e `PRIMARY_FIX`.

**Erro mais comum:** secret do **Authentication → Hooks → Send SMS** ≠ `SEND_SMS_HOOK_SECRET` na Edge Function (são dois sítios; têm de ser idênticos).


1. Registo na app → sheet «Verificar telemóvel»
2. Número PT `9xxxxxxxx` → receber SMS
3. Logs: **Edge Functions** → `send-sms-bulkgate`

## Erros comuns

| Erro | Acção |
|------|--------|
| `401 Unknown identity` / `empty application_id` | **ID ou token BulkGate incorrectos** — regenera no portal (app **transactional**), actualiza secrets, confirma sem espaços/aspas |
| Hook 500 / `Invalid payload sent to hook` | `SEND_SMS_HOOK_SECRET` não coincide **ou** payload GoTrue não parseado (ver `sms.phone` / `user.new_phone` na função) |
| SMS não chega | Verificar remetente PT no BulkGate; evitar spam filters |
