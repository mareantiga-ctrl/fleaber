# FROZEN_REPORT — RED TEAM CEGO CM · Hub / Edge / Mux / tip · POS_CDCI · DEEP v2

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 1
P2 aberto: SIM → quantos: 1
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 2

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? SIM
4. Quantos P1: 1
5. P2 hygiene encontrado? SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_CM_HUB_EDGE_POS_CDCI_v1
FROZEN_AT: 2026-09-06T13:40:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CM1, CM2, CM3, CM4, CM5, CM7]
probes_na_tabela: 30
VEREDICTO: FAIL_P1
prefix: RTCM-20260906T1318
staging: fxdknzrqjenzqcvnwqqq
```

Staging · Stripe TEST · actors JWT B1/S1/B2/S2 · `service_role` só fixture / observação. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

Exactos CDCI **reprovados e não contados:** `batata_resolve_handle` unpublished + redirect unpublished → `found=false`; views Hub unpublished → `[]`; REST `lives` live+active / scheduled unpublished → `[]`; `batata_live_item_stock` unpublished → `live_item_not_found`; tip unpublished clássico → 400 `Tips only allowed for published hub sellers.`; SELECT `mux_playback_id` JWT → 403 lives; resolve-mux unpublished anon/B1 → 404 `live_not_public`.

S2 fixture ficou sem `handle` (PATCH handle não persistiu) → `hub_published=true` também não pegou. B1 mid-unpublish correu em **S1** com restore imediato (`hub_published=true` confirmado no fecho). B2 do harness nasceu `user_type=vendedor` (não comprador) — create-mux 200 do B2 **não** conta como buyer Mux.

--------------------------------------------------
## TABELA DE PROVAS (30)
--------------------------------------------------

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | resultado |
|----------|------|----------------|----------|-----------|-----------|
| A1 | CM-A | GET hub_lives_public unpublished air | 200 `[]` | live `fae4dd16-…` hub off | HOLD |
| A2 | CM-A | GET hub_lives_discovery_public unpublished | 200 `[]` | idem | HOLD |
| A3 | CM-A | GET hub_live_items_public + discovery unpublished (id,title,price) | 200 `[]` / 200 `[]` | item live_only qty=4 | HOLD |
| A4 | CM-A | GET hub_products_public unpublished SKU | 200 `[]` | prod `da955394-…` qty=5 | HOLD |
| A5 | CM-A | B1 GET lives live+active unpublished + feed | 200 `[]`; inFeed=false feedN=0 | CDCI gate | HOLD |
| A6 | CM-A | B1 GET lives scheduled unpublished | 200 `[]` | sched `d84cfd35-…` | HOLD |
| A7 | CM-A | GET live_items unpublished anon+B1 | anon 401 profiles; B1 200 `[]` | — | HOLD |
| A8 | CM-A | RPC batata_live_item_stock unpublished anon+B1 | `ok:false live_item_not_found` | — | HOLD |
| A9 | CM-A | B1 POST follows following_id=S2 unpublished | **201** follow id `973db7f7-…` | raffle tickets **1** | **FAIL** |
| A10 | CM-A | B1 POST follows S1 published (controlo) | 201 | — | HOLD |
| A11 | CM-A | B2 follow unpublished vs ghost UUID | unpub 201; ghost **201** | sem oráculo de status | HOLD (classe A9) |
| A11b | CM-A | BD follows following_id=ghost | 200 1 row `00000000-…000c1` | sem FK following_id | FAIL (classe A9, não conta à parte) |
| A12 | CM-A | anon POST follows | 401 permission denied follows | — | HOLD |
| A13 | CM-A | B1 POST favorites product unpublished | **201** fav `9cc52811-…` | GET 200 mesma row | **FAIL** |
| A13b | CM-A | B1 POST favorites product ghost UUID | 409 23503 FK products | oracle vs A13 | HOLD (contraste) |
| A14 | CM-A | hub_reviews_public + reviews_gerais unpublished | hub 200 `[]`; rg B1 só a própria; anon 401 | review fixture | HOLD |
| A15 | CM-A | resolve handle/slug/redirect + discovery ilike + profiles eq | found=false 404 ×3; ilike `[]` | redirect old→S2 | HOLD |
| A16 | CM-A | B1 GET products unpublished + qty=0 + enum mkt | 200 `[]` / `[]`; enumHasUnpub=false | CDCI qty>0+hub | HOLD |
| B1 | CM-B | S1 Session tip published → unpublish S1 → GET unpaid → restore S1 | create 200 `cs_test_a1iEFS…`; GET unpaid; status pending | Δwallet não creditou; S1 republished | HOLD |
| B2 | CM-B | tip bind live S1 → end live → GET settle unpaid | create 200 `cs_test_a1uZJ9…`; GET; status pending | live `3e208b20-…` ended | HOLD |
| B3 | CM-B | amount 0/0.01/-1/0.5/501 + tip_id cliente + seller≠owner | todos 400 Invalid/too high / tip_id recusado / seller mismatch | — | HOLD |
| B4 | CM-B | GET settle unpaid B2/anon/replay + RPC settle JWT | GET «ainda não confirmado»; RPC ≠ true | tip pending; Δ=0 | HOLD |
| B5 | CM-B | stripe-webhook assinatura forjada | 400 `invalid_signature` | — | HOLD |
| C1 | CM-C | create-mux body hostil B1 + B2 + S2 seller_id=S1 | B1 **403** authz; B2 200 (fixture `user_type=vendedor`, não conta); S2 200 live.owner=**S2** (body ignorado) | lives Mux ended | HOLD |
| C2 | CM-C | complete-mux B2/anon/S2 vs live S1 + livekit token B2 | 403 / 401 / 403; livekit recusado | — | HOLD |
| C3 | CM-C | OPTIONS/POST Origin `null` / evil / chrome-ext / evil.fleaber.pt | ACAO=`https://fleaber.pt` (não reflecte) | — | HOLD |
| C4 | CM-C | resolve-mux unpublished anon/B1/dono S2 | anon/B1 404 `live_not_public`; dono 200 playback (studio) | — | HOLD |
| R1 | residual | resolve_handle unpublished clássico | found=false 404 | — | HOLD |
| R2 | residual | tip unpublished clássico (loja já off) | 400 published hub sellers | — | HOLD |
| R3 | residual | SELECT mux_playback_id JWT B1 vs dono | 403 lives ambos | revoke cols | HOLD |

CM-A: 18 linhas (A1–A16 + A11b + A13b) · CM-B: 5 · CM-C: 4 · residual CDCI: 3 · **total 30**.

--------------------------------------------------
## CHECKLIST (28)
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 1
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (tip amount teto 400)
10. Buyer manipula qty autoritativa — NÃO COMPROVADO (poço Hub/Edge)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (tip unpaid pending; GET não confirma)
13. Refund excede captura — NÃO COMPROVADO
14. Release+refund cria dinheiro líquido — NÃO COMPROVADO
15. Payout duplica Transfer — NÃO COMPROVADO
16. Stock=1 duas vendas válidas — NÃO COMPROVADO
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO
18. Bypass capacidade/reserva — NÃO (stock RPC unpublished not_found)
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (Mux cols 403; resolve unpublished 404)
21. Buyer assume seller/admin — NÃO (B1 create-mux 403; complete-mux 403)
22. Seller assume buyer/admin — NÃO (complete-mux cruzado 403; body seller_id ignorado)
23. Reviews forjadas — NÃO (hub_reviews unpublished `[]`)
24. RPC SECURITY DEFINER perigoso executável — NÃO (settle JWT não credita)
25. RLS crítico quebrado — PARCIAL (`follows` insert sem gate hub_published nem FK following; `favorites` insert sem gate hub_published mas com FK)
26. Edge confia total do cliente — NÃO (tip_id/amount/CORS/complete-mux)
27. Regressão funcional (happy path partido) — NÃO
28. Saturação atingida — SIM (matriz A≥16 B≥4 C≥4 residual≤3 · lentes 6/7 · tabela 30)

Poços CM: discovery/follow/stock/reviews=SIM · tip mid-unpub + settle=SIM · Edge Mux/CORS=SIM · composição follow→rifa=SIM  
ATROFIA (só exactos CDCI): NÃO  
Pagamento TEST gorjeta: Session criada, **não** paga (`sk_test_` ausente no env local). Captura paga NÃO COMPROVADA — lacuna honesta. Mid-unpublish unpaid HOLD.

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

### CM-P1-1 · CM1/CM7 · `follows` aceita UUID de loja unpublished e dispara rifa (+1 ticket)

**Actor:** B1 (JWT comprador real)  
**Pré:** S2 `hub_published=false`, handle não público; live air unpublished; rifa `status=active` `6841b07b-…`. Hub views / REST lives / resolve_handle escondem S2 (A1–A8, A15, A5 HOLD).  
**Request:** `POST /rest/v1/follows` `{"follower_id": B1, "following_id": S2}`  
**Esperado:** recusa (loja desligada / alvo não publicado), alinhado à vitrine Hub.  
**Obtido:** **201** row `973db7f7-…`. Trigger `batata_live_raffle_on_follow_insert` gravou `live_raffle_entries.ticket_balance=1` na rifa unpublished.  
**Variante mesma classe (não conta à parte):** B2 follow UUID fantasma `00000000-…000c1` também **201** e persiste na BD — `follows.following_id` **sem FK** para `profiles`. Anon 401 (A12 HOLD).  
**Impacto:** «Desligar loja» não desliga seguir nem a rifa. Quem já tem o UUID (partilha antiga, chat, período published) continua a criar aresta social e a **ganhar tickets** num directo que o Hub trata como inexistente. Sem leak novo de UUID nas views REST (A5 HOLD) — o caminho exige UUID prévio.  
**Repro:** fixture S2 unpublished + rifa active; POST follows; SELECT live_raffle_entries.  
**Sev:** P1 (prémio de rifa explorável; não P0: sem dinheiro Stripe).  
**Prova:** `pass1.json` A9; `pass1b.json` A11b.

### CM-P2-1 · CM1 · `favorites` aceita SKU unpublished (oráculo UUID vs ghost)

**Actor:** B1  
**Pré:** produto S2 `da955394-…` qty=5 `list_on_marketplace=true`; `hub_products_public` e REST `products` escondem o SKU (A4/A16 HOLD).  
**Request:** `POST /rest/v1/favorites` `{"user_id": B1, "product_id": unpublished}` → **201**. Contraste ghost `00000000-…000c2` → **409** `favorites_product_id_fkey`.  
**Esperado:** mesma recusa que a vitrine (SKU não listável / loja off).  
**Obtido:** favorite persiste; GET favorites devolve o `product_id`. Quem tem o UUID distingue SKU real oculto (201) de UUID inventado (409).  
**Impacto:** lista de desejos / oráculo de existência sobre catálogo que o Hub e o REST marketplace já escondem. Sem enum novo (A16 `[]`).  
**Repro:** `pass1.json` A13; `pass1b.json` A13b.  
**Sev:** P2  
**Prova:** A13 201 vs A13b 409.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| A1–A8 Hub views / REST lives / live_items / stock RPC unpublished | HOLD exacto CDCI |
| A14 hub_reviews unpublished | `[]` |
| A15 resolve/slug/redirect | found=false (redirect CG-P2-003 **fechado**) |
| A16 products unpublished + qty=0 | `[]` |
| R1–R3 residual | HOLD |
| B1 mid-unpublish unpaid S1 | Session + GET pending; S1 restaurado published |
| B2 live ended unpaid | pending |
| B3 amount/tip_id/seller | 400 |
| B4 GET/RPC unpaid | pending Δ=0 |
| B5 webhook forjado | 400 invalid_signature |
| C1 B1 create-mux | 403 «Apenas contas de vendedor» |
| C1 B2 create-mux 200 | fixture B2 `user_type=vendedor` — **não** buyer |
| C1 S2 body.seller_id=S1 | live.owner=S2; extra fields ignorados |
| C2 complete-mux cruzado | 403/401 |
| C3 CORS null/evil | ACAO fleaber.pt |
| C4 resolve-mux unpublished não-dono | 404 live_not_public; dono 200 studio |
| Tip clássico unpublished | 400 published-only (R2) |
| Pagamento 4242 gorjeta | SKIP sem `sk_test_` local |

--------------------------------------------------
## LENTES
--------------------------------------------------

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| CM1 Hub | SIM matriz A1–A16 | P1-1 follow+rifa; P2-1 favorite |
| CM2 origin/CORS | SIM Origin null/evil/ext | não |
| CM3 tip | SIM mid-unpub + bind end + amount + unpaid + webhook | não |
| CM4 Edge | SIM create-mux / complete-mux / livekit | não |
| CM5 Mux | SIM resolve dono vs buyer; REST cols | não |
| CM6 storage | NÃO (fora da matriz v2 CM) | — |
| CM7 composição | SIM follow unpublished → ticket rifa | mesmo P1-1 |

Lentes 6/7 (mín. 5). CM6 storage não era quota deste prompt.

--------------------------------------------------
## INVARIANTES (órbita Hub/Edge)
--------------------------------------------------

Tip amount/`tip_id` autoridade HOLD. JWT saldo unpaid HOLD. Mid-unpublish não creditou Session não paga. Captura paga após unpublish **não** exercitada (sem chave Stripe TEST local).

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_cm_20260906T1318/_rtcm.dart`
- `pass1.dart` + `pass1.json` + `pass1_ids.json`
- `confirm.dart` + `pass1b.json`
- `pass2.dart` + `pass2.json`
- `pass3.dart` (C1; timeout no complete-mux Mux real — lives ended via service)
- `pass3b.dart` + `pass3b.json` (C2–C4, B1 fallback S1, B2, B5)
- `end_lives.dart` — fixtures `RTCM-20260906T1318*` `status=ended`; S1 `hub_published=true`

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. NÃO INICIAR FASE 4.**
