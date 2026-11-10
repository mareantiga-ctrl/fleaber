# 01 — Arquitectura actual da Fleaber

## Visão geral

A Fleaber é um marketplace de segunda mão com **directos de venda**, **FleaHub** (vitrine web pública) e **carteira Stripe Connect**. O cliente principal é uma app **Flutter** (Android em produção; Hub = mesmo código compilado para web).

```
[ Android APK ] ----\
                     +--> Supabase Auth + PostgREST + Realtime + Storage
[ FleaHub Web  ] ----/         |
                               +--> Edge Functions (Deno)
                                      |-- Stripe (TEST / LIVE gated)
                                      |-- DPD (via proxy VPS egress)
                                      |-- BulkGate SMS (hook Auth, gated)
                                      |-- LiveKit + Mux (directos / VOD)
                                      |-- Meta / PS Face (comentários)
                                      |-- Moloni (C2) / Amazon (C2)
                                      +-- Email (Auth SMTP Amen + notify)
```

## Camadas

### 1. Android (app)

- Código: `lib/` (Flutter), build `android/`
- Entrada: `lib/main.dart` → GoRouter (`lib/flutter_flow/nav/`)
- Cliente BD: `lib/backend/supabase/`
- Superfícies: Início, anúncios, favoritos, chat, encomendas, carteira, perfil, studio de directo, importador (C2)

### 2. FleaHub (web)

- Código: `lib/hub/`
- Deploy FTP: `fleaber.pt/fleahub/` (artefacto `deploy/fleaber_pt/fleahub/`)
- Perfis públicos `@handle`, loja, gravados, live viewer, saco/checkout web, páginas institucionais
- Mesmas políticas RLS que a app (mesmo projecto Supabase quando em produção)

### 3. Supabase

| Ambiente | Project ref (público) | Uso |
|----------|----------------------|-----|
| Produção | `bpmpkzwnrbmuqnhgdscf` | App PROD / Hub PROD |
| Staging | `fxdknzrqjenzqcvnwqqq` | Testes isolados, secrets históricos BulkGate |

- Schema / hardening: `docs/SCHEMA_SOURCE_OF_TRUTH.md`, `supabase/migrations/`
- RPCs financeiras: família `batata_*` (autoridade server-side; JWT não inventa saldos)
- **Nunca** reaplicar SQL em quarentena (ver SCHEMA doc)

### 4. Vídeo

- **LiveKit** — WebRTC no telemóvel do vendedor
- **Mux** — ingest/playback/VOD
- Edges: `create-mux-live`, `livekit-mux-publish`, `resolve-mux-playback`, `complete-mux-live`, `livekit-egress-cleanup`
- UI: `lib/fleaber_live_player/`, `lib/vendedor/`, `lib/hub/pages/hub_live_page.dart`
- **Custo:** lives activas cobram; após testes → `status=ended`, `is_active=false`

### 5. Integrações (resumo)

| Integração | Onde corre | Nota C3 |
|------------|------------|---------|
| Stripe Connect / checkout | Edge + webhooks | TEST livre com contas teste; LIVE gated |
| DPD | Edge → proxy VPS `135.125.254.159` → API DPD | OAuth PROD OK; create PROD OFF |
| BulkGate | `send-sms-bulkgate` | Secrets/hook PROD incompletos; SMS OFF |
| Email Auth | SMTP Amen no Supabase Auth | Limite diário fornecedor |
| Meta / Facebook Live | Edges `meta-*`, `ps-*`, ingest OCR | Fora do núcleo C3 salvo IDOR/reservas |
| Moloni / Amazon | C2 | Não alterar; só observar superfície se no exame |

## Proxy DPD (egress)

- Host: `vps-27d76f35.vps.ovh.net`
- IP de saída: `135.125.254.159`
- Allowlist (ZIP 190): `qabusiness.dpd.pt` + `business.dpd.pt`
- Erro histórico `host_not_allowed` = rejeição do **proxy**, não da DPD

## Princípios de segurança já aplicados (contexto)

- Montantes de pagamento / refund / wallet: **servidor** (Edge + RPC), não confiar no cliente
- Create DPD comercial e SMS: **kill-switches**
- Stripe LIVE dinheiro: `OPS_STRIPE_LIVE_PILOT_MONEY_GO` (deve permanecer off até GO)
- RLS seller/buyer em chats, encomendas, wallets (hardening documentado em SCHEMA)
