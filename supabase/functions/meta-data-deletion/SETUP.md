# meta-data-deletion (Meta / Facebook)

Callback opcional para o App Dashboard da Meta.

## Deploy

```bash
npx supabase functions deploy meta-data-deletion
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

O callback valida `signed_request`, regista o pedido em `app_logs` e devolve
`url` + `confirmation_code` conforme a documentação Meta.
A eliminação efectiva da conta Fleaber continua a ser processada pela equipa
via email / fluxo na app (ver `data-deletion.html`).
