# LiveKit + Supabase (Fleaber)

## Secrets no Supabase (produção)

**Já aplicado via CLI** (2026-05-20): secrets `LIVEKIT_*` + deploy `livekit-mux-publish` no projeto `fxdknzrqjenzqcvnwqqq`.

Para repetir no futuro (PowerShell, na raiz do repo):

```powershell
.\tool\set_livekit_supabase_secrets.ps1
```

Ou manualmente:

```powershell
npx supabase login
npx supabase secrets set --project-ref fxdknzrqjenzqcvnwqqq `
  LIVEKIT_URL="wss://fleaber-3xlvvjjs.livekit.cloud" `
  LIVEKIT_API_KEY="SUA_KEY" `
  LIVEKIT_API_SECRET="SEU_SECRET"
npx supabase functions deploy livekit-mux-publish --project-ref fxdknzrqjenzqcvnwqqq
```

Alternativa: painel [Edge Functions → Secrets](https://supabase.com/dashboard/project/fxdknzrqjenzqcvnwqqq/settings/functions).

## SQL

Executa `supabase/sql/live_streaming_livekit_batata.sql` no SQL Editor.

## App

`lib/utils/live_publish_config.dart` → `kLivePublishBackend = livekitMuxEgress` (já é o default do POC).

## Teste

1. Vendedor: Novo Direto → Preparar / Iniciar Direto.
2. Logs: `app_logs` com passos `livekit.pre_connect`, `livekit.post_egress`, etc.
3. Viewer: mesmo player Mux HLS (egress RTMP → Mux).

## Local

`supabase/.env` (gitignored) — usado com `supabase functions serve`.
