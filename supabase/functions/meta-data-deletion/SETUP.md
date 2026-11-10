# meta-data-deletion (Meta / Facebook)

Callback para o App Dashboard da Meta (Data Deletion Request URL).

## Deploy

```bash
npx supabase functions deploy meta-data-deletion --project-ref <REF>
```

## Secrets

| Secret | Obrigatório |
|--------|-------------|
| `FACEBOOK_APP_SECRET` ou `META_APP_SECRET` | Sim |
| `FLEABER_WEB_APP_URL` | Não (default `https://fleaber.pt`) |
| `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` | Sim (ambiente Edge) |

## Meta Dashboard

1. **Privacy Policy URL:** `https://fleaber.pt/privacy.html`
2. **User data deletion instructions URL:** `https://fleaber.pt/data-deletion.html`
3. **Data Deletion Request URL (callback):**  
   `https://<PROJECT_REF>.supabase.co/functions/v1/meta-data-deletion`

## Comportamento (Block C3)

1. Valida `signed_request` (HMAC SHA-256, timing-safe).
2. Extrai `user_id` Facebook do payload.
3. Resolve conta Fleaber via `auth.identities` (`provider=facebook`) ou `batata_facebook_id_map`.
4. Chama `batata_anonymize_account_for_deletion` (`p_force_pii_only=true`) — **idempotente**.
5. Bane Auth (não apaga UUID — FK `orders` → `auth.users`).
6. Responde `{ url, confirmation_code }` conforme docs Meta.
7. Histórico financeiro **não** é apagado (retenção / obrigações).

Se não existir utilizador Fleaber para o Facebook ID: regista pedido `completed` com nota `no_fleaber_user_for_facebook_id`.
