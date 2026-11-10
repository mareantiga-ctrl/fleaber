# FROZEN_REPORT — RED TEAM CEGO CA · Hub / Edge / Mux / tip · POS_BRBW

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: SIM → quantos: 2
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 2

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado? SIM
6. Quantos P2: 2
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_CA_HUB_EDGE_POS_BRBW_v1
FROZEN_AT: 2026-09-06T11:50:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CA1, CA2, CA3, CA4, CA5, CA6, CA7]
VEREDICTO: FAIL_P2
prefix: RTCA-20260906T1137
staging: fxdknzrqjenzqcvnwqqq
```

Staging · Stripe TEST · actors JWT B1/S1/B2/S2 · `service_role` só fixture / observação. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

Exactos BRBW **reprovados e não contados:** discovery unpublished → `[]`; resolve-mux unpublished anon/B1 → 404 `live_not_public`; FOMO scheduled/inactive → `live_not_public`; anon `GET lives` Mux/VOD → 401 profiles (sem colunas VOD).

--------------------------------------------------
## CHECKLIST (28)
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 2
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (tip amount teto servidor)
10. Buyer manipula qty autoritativa — NÃO COMPROVADO (poço Hub/Edge)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (tip unpaid Δwallet=0)
13. Refund excede captura — NÃO COMPROVADO (poço não era refund)
14. Release+refund cria dinheiro líquido — NÃO COMPROVADO
15. Payout duplica Transfer — NÃO COMPROVADO
16. Stock=1 duas vendas válidas — NÃO COMPROVADO
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO
18. Bypass capacidade/reserva — NÃO (FOMO unpublished/inactive `live_not_public`)
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (storage GET alheio 400; list prefix alheio `[]`)
21. Buyer assume seller/admin — NÃO (`user_type` PATCH bloqueado; create-mux buyer 403)
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO COMPROVADO
24. RPC SECURITY DEFINER perigoso executável — NÃO (`batata_settle_live_tip_from_stripe` 403 JWT)
25. RLS crítico quebrado — PARCIAL (tabela `lives` visível a authenticated em broadcasting/scheduled, incl. loja unpublished; VOD ended unpublished `[]`)
26. Edge confia total do cliente — NÃO (`tip_id` recusado; complete-mux 403; stream_key inject 403)
27. Regressão funcional (happy path partido) — NÃO
28. Saturação atingida — SIM (poços IPv6/nip.io/CORS/embed/tip unpaid/complete-mux/storage/dono-vs-anon)

Poços CA exercitados: Hub/FOMO=SIM · origin/CORS=SIM · tip settle unpaid=SIM · Edge body=SIM · Mux/LiveKit=SIM · storage=SIM · composição JWT∥views∥Edge=SIM  
ATROFIA (só redescobriu exactos fechados): NÃO  
Pagamento TEST gorjeta: Session criada, **não** paga (poço unpaid B2). Captura paga NÃO COMPROVADA — lacuna honesta.

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

### CA-P2-001 · CA5/CA7 · JWT authenticated lê `mux_playback_id` de loja unpublished (Hub e resolve-mux escondem)

**Actor:** B1 / B2 (qualquer sessão autenticada, não-dono)  
**Pré:** S2 `hub_published=false`. Lives: `status=live` `is_active=true` **e** `status=scheduled` `is_active=false`, ambas com `mux_playback_id` real copiado.  
**Request:**
1. Anon `GET /rest/v1/lives?id=eq.{airUnpub}&select=id,mux_playback_id,playback_id` → **401** `permission denied for table profiles`
2. B1 mesmo GET → **200** row + `mux_playback_id` + `playback_id`
3. Anon `POST /functions/v1/resolve-mux-playback {"live_id": airUnpub}` → **404** `live_not_public`
4. B1 resolve-mux unpublished → **404** `live_not_public`
5. Anon `GET hub_lives_discovery_public` / `hub_lives_public` unpublished → **[]**
6. B1 `GET lives?seller_id=eq.{S2}&select=id,status,mux_playback_id,playback_id` → **2 rows** (scheduled + live) com playback

**Esperado:** se Hub unpublished esconde o vendedor no feed e o Edge recusa playback, o REST `lives` alinhado (anon **e** authenticated não-dono sem `mux_playback_id`).  
**Obtido:** split JWT vs anon vs Edge. Qualquer login lê o id HLS da loja desligada (directo no ar **e** agendado). Colunas VOD/`mux_stream_key` no mesmo GET → 403 (pedido com colunas secretas mascara o leak).  
**CDN:** `GET https://stream.mux.com/{id}.m3u8` do id copiado → **412** (stream Mux não estava a emitir). Leak do **id** comprovado; assistir HLS real **não** demonstrado neste id.  
**Impacto:** política BRBW (`hub_published` no discovery + resolve-mux) furada pela tabela `lives` + grant `mux_playback_id` a `authenticated` + RLS que deixa ver todas as lives `live+active` e **todas** as `scheduled`. Loja «desligada» continua visível a qualquer conta.  
**Repro:** fixture S2 unpublished; GET REST com **só** colunas `id,mux_playback_id,playback_id` (não pedir `mux_stream_key`).  
**Sev:** P2 (não P1: sem HLS real neste id; directo no ar é acto do vendedor; sem dinheiro).  
**Prova:** `pass2.json` `CA7-B1-RESTPB-airUnpub`, `CA7-B1-RESTPB-schedUnpub`, `CA7-B1-S2-LIVES-PB`; `pass1.json` `CA5-B1-SCHED-DIRECTORY`. Lives `940ed1f3-…` (air) e `6c5706a1-…` (scheduled).

### CA-P2-002 · CA1 · `batata_resolve_handle` encontra loja unpublished (scheduled/ended); profiles discovery mostra-a enquanto o directo está no ar

**Actor:** anon  
**Pré:** S2 `hub_published=false`, handle slug `rtca-20260906t1137-s2`.  
**Request:**
1. Enquanto air unpublished: `GET hub_profiles_discovery_public?id=eq.{S2}` → row `hub_published=false` (lives discovery do mesmo id → `[]`)
2. `POST batata_resolve_handle {"p_handle":"rtca-20260906t1137-s2"}` → `found=true`, `hub_published=false`, `profile_id`
3. Depois de `status=ended` no air: profiles discovery → `[]`; lives discovery → `[]`; **resolve_handle continua** `found=true` (S2 ainda tem scheduled + ended)

**Esperado:** loja desligada sem vitrine = `not_found` / `[]` em todas as superfícies públicas (alinhado a discovery+resolve-mux).  
**Obtido:** oracle de handle/UUID de vendedor que despublicou o Hub mas tem (ou teve) lives scheduled/ended. Página Hub (`hub_profiles_public`) esconde; o RPC não. Com o UUID, CA-P2-001 lê playback no REST.  
**Impacto:** FleaHub «desligar loja» não apaga o mapa público por handle nem o card de discovery **enquanto** há directo no ar.  
**Repro:** pass2 `CA1-PROFDISC-UNPUB-AIR` + `CA1-RESOLVE-HANDLE-UNPUB-SLUG`; pass3 `CA1-RESOLVE-HANDLE-UNPUB-ENDED`.  
**Sev:** P2  
**Prova:** `pass2.json` / `pass3.json`. S2 `86819413-eae8-4b59-8319-3c904890bcea`.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| Discovery unpublished air/sched/ended | `[]` — HOLD exacto |
| resolve-mux unpublished anon/B1 | 404 `live_not_public` — HOLD exacto |
| FOMO unpublished / scheduled inactive / live inactive | `live_not_public` — HOLD exacto |
| Anon `GET lives` (qualquer col) | 401 `profiles` — HOLD exacto VOD/cols |
| B1 `mux_vod_playback_id` / `mux_asset_id` / `mux_stream_key` | 403 lives — HOLD |
| Ended unpublished REST B1 | `[]` (RLS ended exige published) — HOLD |
| Dono S2 resolve-mux unpublished **air** | 200 playback (studio); anon/B1 404 — split intencional, não contar sozinho |
| Embed `live_items→lives(*)` | 401/403 — HOLD |
| Hub items unpublished | `[]` — HOLD |
| IPv6 `[::ffff:127.0.0.1]` / `[::1]` / `[::ffff:7f00:1]` web_return | 200 HTML wallet, **sem** 303 hostil — HOLD |
| `127.0.0.1.nip.io` / sslip / localtest.me / lvh.me / fleaber.pt.nip.io | idem — HOLD |
| `https://2130706433` / `127.1` / `0x7f000001` | HTML, sem 303 — HOLD exacto decimal |
| `http://127.0.0.1` / `https://fleaber.pt` | 303 `/wallet` allowlist — residual |
| CORS Origin hostil | `ACAO=https://fleaber.pt` (não reflecte) — HOLD |
| CORS `http://localhost:5173` | reflecte (dev allowlist) — residual |
| complete-mux / livekit token / egress B2 vs S1 | 403 — HOLD |
| create-mux buyer | 403 — HOLD |
| egress-cleanup secret errado | 401 — HOLD |
| PATCH `lives` JWT | 403 — HOLD |
| tip `seller_id` ≠ owner | 400 — HOLD |
| GET settle unpaid B2/anon | «Pagamento ainda não confirmado»; tip `pending`; Δwallet=0 — HOLD |
| RPC settle JWT | 403 function denied — HOLD |
| Tip checkout em unpublished air | Session criada (live *broadcasting*); não é furto — **não contar** |
| `fleaber_private` object/public | 400; buckets list `[]` — HOLD |
| List/GET cruzado storage | B2 GET B1 400; prefix B2 `[]`. List top-level = prefixes dos *próprios* objectos — **não é P1** |
| OpenAPI `/rest/v1/` | 401 — HOLD |
| B1 PATCH `user_type` | 400 `handle_immutable_use_rpc` — HOLD |

--------------------------------------------------
## LENTES
--------------------------------------------------

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| CA1 Hub/FOMO | SIM | P2 resolve_handle + profiles discovery unpublished |
| CA2 origin/CORS/Connect | SIM | não (IPv6/nip.io HOLD) |
| CA3 tip settle unpaid B2 | SIM Session + GET + RPC | não (unpaid HOLD; tip unpublished não contado) |
| CA4 Edge body | SIM complete-mux / livekit / PATCH | não |
| CA5 Mux/LiveKit | SIM REST cols, embed, resolve, CDN | P2 REST playback unpublished |
| CA6 storage | SIM list/GET/upload | não |
| CA7 composição | SIM JWT∥views∥Edge∥handle | P2-001 + P2-002 |

--------------------------------------------------
## INVARIANTES (órbita Hub/Edge)
--------------------------------------------------

A–L núcleo checkout: não o poço. Nesta órbita: E (JWT saldo) HOLD; L (tip autoridade) HOLD.

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_ca_20260906T1137/pass1.dart` + `pass1.json`
- `pass2.dart` + `pass2.json`
- `pass3.dart` + `pass3.json`
- Fixtures lives `RTCA-20260906T1137*` terminadas após freeze (`status=ended`).

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. NÃO INICIAR FASE 4.**
