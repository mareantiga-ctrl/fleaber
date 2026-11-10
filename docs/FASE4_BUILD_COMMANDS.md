# Fase 4 — comandos de build oficiais (P4.5)

**Data:** 2026-09-14  
**Regra:** release de utilizadores reais **nunca** usa o default (staging).  
**Prod ref:** `bpmpkzwnrbmuqnhgdscf`  
**Stripe:** builds de smoke usam secrets **Test** no projecto Prod — **não** Stripe Live nesta fase.

## Staging (QA / default)

```powershell
flutter run
# ou
flutter build apk --debug
```

Sem dart-define → `lib/backend/supabase/supabase.dart` usa staging `fxdknzrqjenzqcvnwqqq`.

## Produção (P4.3+ secrets Test + Auth OK)

**Não** uses `--flavor` ainda (productFlavors Android adiados — partiam Maestro/CI).

Substitui `<PROD_ANON>` pela **anon public** do Dashboard Prod (Settings → API).  
**Não** commits da anon no Git; **não** coloques no chat.

```powershell
flutter build apk --release `
  --dart-define=FLEABER_ENV=production `
  --dart-define=FLEABER_SUPABASE_URL=https://bpmpkzwnrbmuqnhgdscf.supabase.co `
  --dart-define=FLEABER_SUPABASE_ANON_KEY=<PROD_ANON>

flutter build appbundle --release `
  --dart-define=FLEABER_ENV=production `
  --dart-define=FLEABER_SUPABASE_URL=https://bpmpkzwnrbmuqnhgdscf.supabase.co `
  --dart-define=FLEABER_SUPABASE_ANON_KEY=<PROD_ANON>
```

`FLEABER_ENV=production` **sem** URL/anon → crash ao arrancar (proposital).  
URL com ref de staging → crash (proposital).

## Hub web (`deploy/fleaber_pt`)

```powershell
flutter build web --release `
  --dart-define=FLEABER_ENV=production `
  --dart-define=FLEABER_SUPABASE_URL=https://bpmpkzwnrbmuqnhgdscf.supabase.co `
  --dart-define=FLEABER_SUPABASE_ANON_KEY=<PROD_ANON>
# depois copiar build/web → deploy/fleaber_pt conforme processo FTP actual
```

## iOS

Usar os mesmos `--dart-define` no `flutter build ipa`.  
Schemes Xcode = follow-up opcional.

## Android flavors

**Adiados:** activar `productFlavors` em `build.gradle` obriga `--flavor` em todos os builds QA.

**Gate de produção actual (obrigatório):**

- `--dart-define=FLEABER_ENV=production`
- `--dart-define=FLEABER_SUPABASE_URL=https://bpmpkzwnrbmuqnhgdscf.supabase.co`
- `--dart-define=FLEABER_SUPABASE_ANON_KEY=...`

Follow-up: activar flavors + actualizar Maestro/CI no mesmo PR.
