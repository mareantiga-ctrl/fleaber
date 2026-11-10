# FROZEN_REPORT — RED TEAM CEGO CG · Hub / Edge / Mux / tip · POS_BXCC · DEEP

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: SIM → quantos: 3
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 3

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado? SIM
6. Quantos P2: 3
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_CG_HUB_EDGE_POS_BXCC_v1
FROZEN_AT: 2026-09-06T12:42:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CG1, CG2, CG3, CG4, CG5, CG6, CG7]
VEREDICTO: FAIL_P2
prefix: RTCG-20260906T1235
staging: fxdknzrqjenzqcvnwqqq
```

Staging · Stripe TEST · actors JWT B1/S1/B2/S2 · `service_role` só fixture / observação. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

Exactos BXCC **reprovados e não contados:** `batata_resolve_handle` handle unpublished → `found=false`; `hub_profiles_discovery_public` / `hub_lives_discovery_public` / `hub_lives_public` unpublished → `[]`; FOMO unpublished → `live_not_public`; resolve-mux unpublished anon/B1 → 404 `live_not_public`; SELECT `mux_playback_id` JWT B1/dono → 403 lives (revoke auth).

--------------------------------------------------
## CHECKLIST (28)
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 3
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (tip amount teto servidor)
10. Buyer manipula qty autoritativa — NÃO COMPROVADO (poço Hub/Edge)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (tip unpaid status=pending; GET «ainda não confirmado»)
13. Refund excede captura — NÃO COMPROVADO
14. Release+refund cria dinheiro líquido — NÃO COMPROVADO
15. Payout duplica Transfer — NÃO COMPROVADO
16. Stock=1 duas vendas válidas — NÃO COMPROVADO
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO
18. Bypass capacidade/reserva — NÃO (FOMO unpublished `live_not_public`)
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO CONTADO (GET `chat_media` público = residual conhecido; list prefix alheio `[]`; traversal `[]`)
21. Buyer assume seller/admin — NÃO (`create-mux` buyer 403; PATCH/INSERT lives 403)
22. Seller assume buyer/admin — NÃO (complete-mux cruzado 403)
23. Reviews forjadas — NÃO (`hub_reviews_public` unpublished `[]`; `reviews_gerais` B1 só a própria)
24. RPC SECURITY DEFINER perigoso executável — NÃO (`batata_settle_live_tip_from_stripe` 403 JWT)
25. RLS crítico quebrado — PARCIAL (tabela `lives` live+active e `scheduled` visível a authenticated **sem** `hub_published`; views Hub escondem)
26. Edge confia total do cliente — NÃO (`tip_id` recusado; complete-mux 403; webhook assinatura 400)
27. Regressão funcional (happy path partido) — NÃO
28. Saturação atingida — SIM (poços A–D · lentes 7/7 · tácticas 1–4)

Poços CG exercitados: Hub discovery matriz=SIM · origin/CORS/IPv6=SIM · tip unpaid + unpublished=SIM · Edge Mux=SIM · storage=SIM · composição=SIM  
ATROFIA (só redescobriu exactos fechados): NÃO  
Pagamento TEST gorjeta: Session criada, **não** paga. Captura paga NÃO COMPROVADA — lacuna honesta do poço unpaid.

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

### CG-P2-001 · CG1/CG3/CG7 · Loja `hub_published=false` no ar: Hub esconde; REST lives + live_items + stock RPC + tip checkout não

**Actor:** B1 (JWT qualquer) · anon no RPC stock · B2 no tip  
**Pré:** S2 `hub_published=false`. Live `status=live` `is_active=true` (`ef845cc5-…`). Item live_only qty=4 price=17,50 (`dd3ba0ed-…`).  
**Request:**
1. Anon `GET hub_lives_public` / `hub_lives_discovery_public` / `hub_live_items_*` unpublished → **[]**
2. FOMO unpublished → `live_not_public`
3. resolve-mux anon/B1 unpublished → **404** `live_not_public` (dono S2 → 200 playback — split studio, não contar sozinho)
4. B1 `GET lives?status=eq.live&is_active=eq.true` → inclui lives unpublished alheias (confirm: `RTBN-…`, `RTBC-… S2-UNPUB-ON`, `RTAE-…`, `RTT-…`; sellers `hub_published=false`)
5. B1 `GET lives?seller_id=eq.{S2}&select=id,status,title` → air + scheduled unpublished
6. B1 `GET live_items?id=eq.{item}` → title/price/**quantity=4**
7. Anon **e** B1 `POST batata_live_item_stock` → `ok:true` price=17.5 total_qty=4 `live_status=live`
8. B2 `POST create-live-tip-checkout` live unpublished air → **200** Session Stripe TEST (`cs_test_a1UEbw…`)

**Esperado:** política BXCC published-only alinhada em **todas** as entradas (views Hub, REST `lives`/`live_items`, RPC stock, Edge tip).  
**Obtido:** vitrine Hub e Edge playback públicos escondem; o feed REST authenticated, o stock (incl. **anon RPC**) e o checkout de gorjeta tratam o directo unpublished como no ar.  
**Impacto:** «Desligar loja» não desliga o catálogo JWT nem o tip enquanto o vendedor transmite. Sem HLS para não-dono (resolve-mux 404). Sem crédito unpaid.  
**Repro:** fixture S2 unpublished + live broadcasting; contrastar views Hub vs REST/RPC/tip. Confirm feed global: `confirm.dart`.  
**Sev:** P2 (não P1: sem Mux HLS a não-dono; tip Session não paga; directo no ar é acto do vendedor).  
**Prova:** `pass1.json` `CG1-LIVES-DIR-UNPUB`, `CG1-LIVEITEM-UNPUB-AIR`; `pass2.json` `CG3-TIP-UNPUB-AIR`; `confirm.dart` UNPUB IN FEED.

### CG-P2-002 · CG1 · `hub_products_public` esconde; JWT `products` mostra SKU unpublished e montra qty=0

**Actor:** B1 (anon 401 products)  
**Pré:** S2 unpublished + produto listado qty=5 price=22 (`16dec8a6-…`). S1 publicado + produto qty=0 price=33 (`3a0d67e6-…`).  
**Request:**
1. Anon/B1 `GET hub_products_public?id=eq.{unpub|qty0}` → **[]**
2. B1 `GET products?id=eq.{unpub}` → 200 title/price/**quantity=5** `list_on_marketplace=true`
3. B1 `GET products?list_on_marketplace=eq.true&order=created_at.desc` → o SKU unpublished entra no enum (confirm `mkt has unpub sku=true`)
4. B1 `GET products?id=eq.{qty0}` → quantity=0 (Hub TU exige qty>0)

**Esperado:** tabela `products` alinhada à vitrine Hub (sem loja morta unpublished; sem qty=0).  
**Obtido:** RLS `products` ignora `hub_published` e `quantity>0`. Qualquer login enumera stock/preço que o Hub oculta.  
**Impacto:** montra morta + loja «desligada» continua no marketplace REST autenticado. Anon bloqueado (401).  
**Repro:** `pass1.json` `CG1-STOCK-REST-UNPUB` + `CG1-STOCK-REST-QTY0`; `confirm.dart`.  
**Sev:** P2  
**Prova:** pass1 + confirm.

### CG-P2-003 · CG1 · `batata_resolve_handle` 301 via `profile_handle_redirects` para destino unpublished

**Actor:** anon  
**Pré:** redirect `rtcg-old-unpub-1235` → `rtcg1235s2` (S2 `hub_published=false`). Lookup directo do handle unpublished → `found=false` (exacto BXCC HOLD).  
**Request:** `POST /rest/v1/rpc/batata_resolve_handle {"p_handle":"rtcg-old-unpub-1235"}`  
**Esperado:** `found=false` / `not_found` se o destino não está publicado (mesmo critério do lookup directo).  
**Obtido:** `found=true`, `http_status=301`, `redirect_to=rtcg1235s2`, `hub_published=null`, `profile_id=null`. O ramo redirect **não** aplica o gate `hub_published`.  
**Impacto:** handle antigo de quem despublicou (ou rename+ocultar) continua a oráculo público `found=true`. Não devolve UUID neste caso (`profile_id` null porque o handle actual não bateu no SELECT). Variante **nova** vs resolve unpublished clássico.  
**Repro:** insert `profile_handle_redirects` destino unpublished; RPC resolve old_handle.  
**Sev:** P2  
**Prova:** `pass1.json` `CG1-RESOLVE-REDIRECT-UNPUB`.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| resolve_handle handle unpublished directo | `found=false` — HOLD exacto BXCC |
| hub_profiles_* / hub_lives_* unpublished | `[]` — HOLD exacto |
| FOMO unpublished | `live_not_public` — HOLD |
| resolve-mux unpublished anon/B1 | 404 `live_not_public` — HOLD |
| Dono S2 resolve-mux unpublished air | 200 playback studio — split intencional |
| B1/S2 SELECT mux_playback_id / playback_id | 403 lives — HOLD exacto revoke |
| Anon GET lives / live_items / products / profiles | 401 profiles/products — HOLD |
| Ended unpublished REST B1 | `[]` — HOLD |
| Embed `lives(*)` | 403 — HOLD |
| IPv6 `[::1]` / mapped / nip.io / sslip / decimal / 127.1 web_return | 200 HTML, **sem** 303 hostil — HOLD |
| CORS Origin hostil / `null` / IPv6 | `ACAO=https://fleaber.pt` — HOLD |
| CORS `http://localhost:5173` | reflecte (dev allowlist) — residual |
| complete-mux / livekit / egress B2 vs S1 | 403 — HOLD |
| create-mux buyer | 403 — HOLD |
| PATCH/INSERT lives JWT | 403 — HOLD |
| egress-cleanup secret errado | 401 — HOLD |
| tip `tip_id` cliente | 400 — HOLD |
| tip seller ≠ owner | 400 — HOLD |
| tip amount 0 / 0.01 / −1 / 0.5 / 501 | 400 — HOLD |
| GET settle unpaid B2/anon + replay | «Pagamento ainda não confirmado»; tip `pending` — HOLD |
| RPC settle JWT | 403 — HOLD |
| webhook Stripe assinatura forjada | 400 `invalid_signature` — HOLD |
| Follow / favorite unpublished | 201 com UUID já obtido noutro poço — **não contar à parte** |
| `reviews_gerais` B1 | só a própria review; hub_reviews unpublished `[]` — HOLD |
| `chat_media` GET público / B2 lê objecto B1 | residual conhecido bucket public=true (BU); path traversal `[]` — **não P1** |
| List prefix storage alheio | `[]` — HOLD |
| Δwallet S1 −3 durante unpaid | ruído staging (tip `pending`); não crédito da Session |

--------------------------------------------------
## LENTES
--------------------------------------------------

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| CG1 Hub | SIM matriz resolve/views/search/follow/stock/reviews | P2-001 lives/items; P2-002 products; P2-003 redirect |
| CG2 origin/CORS/IPv6 | SIM | não |
| CG3 tip settle unpaid + bind | SIM Session + GET + RPC + unpublished | P2-001 tip unpublished (sem crédito unpaid) |
| CG4 Edge Mux body | SIM complete-mux / livekit / PATCH | não |
| CG5 Mux | SIM REST cols, embed, resolve, dono vs anon | não (exactos HOLD) |
| CG6 storage | SIM list/GET/upload/traversal | não (public chat_media residual) |
| CG7 composição | SIM feed JWT unpublished + products enum + tip | mesmo P2-001 / P2-002 |

--------------------------------------------------
## INVARIANTES (órbita Hub/Edge)
--------------------------------------------------

A–L núcleo checkout: não o poço. Nesta órbita: E (JWT saldo) HOLD unpaid; L (tip autoridade amount/tip_id) HOLD.

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_cg_20260906T1235/_rtcg.dart`
- `pass1.dart` + `pass1.json` + `pass1_ids.json`
- `pass2.dart` + `pass2.json`
- `pass3.dart` + `pass3.json`
- `confirm.dart` (feed unpublished global + enum marketplace)
- `end_lives.dart` — fixtures `RTCG-20260906T1235*` `status=ended` após freeze

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. NÃO INICIAR FASE 4.**
