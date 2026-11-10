# FROZEN_REPORT — RED TEAM CEGO CY · Hub / follow / favorite / tip / Mux · POS_CPCU

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
AUDITOR: REDTEAM_BLIND_CY_HUB_EDGE_POS_CPCU_v1
FROZEN_AT: 2026-09-06T15:05:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CY1, CY2, CY3, CY4, CY5, CY6, CY7]
probes_na_tabela: 16
VEREDICTO: FAIL_P2
prefix: RTCY-20260906T1450
staging: fxdknzrqjenzqcvnwqqq
```

Staging · Stripe TEST (`cs_test_*` criadas, **não** pagas — `sk_test_` ausente no env local) · actores JWT B1/S1/B2(comprador)/S2(vendedor) · `service_role` só fixture / observação / restore. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

CS da ronda POS_ALLOWLIST **não tinha corrido** — esta ronda CY preenche essa quota (follow/favorite published + tip/Mux residual).

S1 `980f4fa1-0004-42f9-abca-69f1a9c29588` restaurado `hub_published=true` após B1. Lives de fixture + Mux `39a8c246-…` `status=ended`. B2 `user_type=comprador` (não o erro CM).

--------------------------------------------------
## TABELA DE PROVAS (16)
--------------------------------------------------

| probe_id | poço | alvo published? | HTTP/RPC | BD | resultado |
|----------|------|-----------------|----------|-----|-----------|
| A1 | CY-A | **sim** S1 | POST follows B1→S1 **403 42501** | JWT vê `profiles` S1 `[]` | **FAIL** |
| A2 | CY-A | não S2 (controlo clássico, 1 linha) | POST follows B1→S2 403 42501 | raffle tickets 0 | HOLD residual (não conta) |
| A3 | CY-A | **sim** SKU S1 + SKU Hub visível | POST favorites **403 42501** (fixture e `de64a58b-…`) | REST product Hub 200; insert 403 | **FAIL** |
| A4 | CY-A | não SKU S2 (controlo) | POST favorites 403 42501 | — | HOLD residual (não conta) |
| A5 | CY-A | ghost / self / spoof follower | todos 403 42501 | — | HOLD |
| A6 | CY-A | race unpublish ∥ follow | follow 403; S2 sem handle — PATCH publish não isolável | tickets 0 | HOLD (TOCTOU não isolável: INSERT published já 42501) |
| A7 | CY-A | sim sold | 403 42501 | — | HOLD (mesma lockout, não prove deny sold) |
| A8 | CY-A | sim qty=0 | 403 42501 | — | HOLD (idem) |
| A9 | CY-A | sim unlisted | 403 42501 | — | HOLD (idem) |
| A10 | CY-A | PATCH/UPSERT unpublished | PATCH n/a (sem row A1); UPSERT 403 | — | HOLD |
| B1 | CY-B | sim→não (RPC S1) | create Session 200 `cs_test_a1yEqq2b…`; `batata_publish_hub(false)` ok; GET unpaid pending; restore true | tip `pending`; Δwallet 0; S1 republicado | HOLD |
| B2 | CY-B | sim S1 | amount 0/0.01/-1/0.5/501 + tip_id cliente → 400; seller≠owner 400 | — | HOLD |
| B3 | CY-B | sim unpaid | GET B2/anon «ainda não confirmado»; RPC settle ≠ credit; status pending Δ=0 | tip pending | HOLD |
| C1 | CY-C | body hostil | B1+B2(comprador) **403** authz; S2 200 live.owner=**S2** (body.seller_id ignorado); live ended | Mux `39a8c246-…` ended | HOLD |
| C2 | CY-C | CORS | OPTIONS Origin `chrome-extension://…` ACAO=**mesmo**; OPTIONS `https://evil.fleaber.pt` ACAO=**mesmo**; null/evil.example/file → fleaber.pt; POST não reflecte | — | **FAIL** |
| C3 | CY-C | não (live S2 activa) | anon/B1 **404** `live_not_public`; dono S2 **200** playback studio | live `810396df-…` ended após probe | HOLD |

CY-A: 10 · CY-B: 3 · CY-C: 3 · **total 16** (≥12). Residual clássico A2+A4 = 2/16 ≪ 50%.

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
9. Buyer manipula preço autoritativo — NÃO (tip amount 400)
10. Buyer manipula qty autoritativa — NÃO COMPROVADO (poço Hub)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (GET unpaid pending; Δ=0)
13. Refund excede captura — NÃO COMPROVADO
14. Release+refund cria dinheiro líquido — NÃO COMPROVADO
15. Payout duplica Transfer — NÃO COMPROVADO
16. Stock=1 duas vendas válidas — NÃO COMPROVADO
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO
18. Bypass capacidade/reserva — NÃO COMPROVADO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (resolve unpublished 404; Mux cols não pedidas além playback dono)
21. Buyer assume seller/admin — NÃO (create-mux 403 comprador)
22. Seller assume buyer/admin — NÃO (body.seller_id ignorado; owner=JWT)
23. Reviews forjadas — NÃO (fora da matriz CY)
24. RPC SECURITY DEFINER perigoso executável — NÃO (settle JWT não credita)
25. RLS crítico quebrado — PARCIAL (insert follows/favorites **over-closed**: published e unpublished 42501; SELECT `profiles` own-row × EXISTS CJCO)
26. Edge confia total do cliente — NÃO (tip_id/amount/seller mismatch 400; create-mux body ignorado). **OPTIONS CORS** reflecte 2 origens hostis.
27. Regressão funcional (happy path partido) — **SIM** (Seguir + Favoritar published 42501)
28. Saturação atingida — NÃO (A1+A3 não OK; P2 aberto)

Poços CY: follow published=SIM · favorite=SIM · tip mid-unpub+amount+unpaid=SIM · Mux/Edge=SIM · CORS=SIM · race=SIM (não isolável) · composição=SIM  
ATROFIA: NÃO (2/16 residual clássico; 0 PaysafeCash/PicPay/Coptic)  
Pagamento TEST gorjeta: Session criada, **não** paga. Captura paga após unpublish NÃO COMPROVADA — lacuna honesta.

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

### CY-P2-1 · CY1/CY2/CY7 · Seguir e Favoritar published recusados (composição own-row × EXISTS)

**Actor:** B1 JWT comprador real (`bfcbeeee-…`, uid confere com env).  
**Pré:** S1 `hub_published=true` handle `fleahub-demo-ux`. Vitrine `hub_products_public` e `hub_lives_public` mostram a loja. SKU Hub `de64a58b-…` visível a B1 no REST `products` (200).  
**Request:** `POST /rest/v1/follows` `{"follower_id":B1,"following_id":S1}` → **403 42501**. `POST /rest/v1/favorites` no SKU Hub visível → **403 42501**. Oráculo: B1 `GET profiles?id=eq.S1` → **200 `[]`**.  
**Esperado:** A1+A3 201 (política published = allow). Unpublished deny à parte.  
**Obtido:** INSERT published **e** unpublished falham com a **mesma** 42501. A2/A4 não provam o fecho CJCO — o botão Seguir/Favoritar está morto para conteúdo que o Hub já mostra.  
**Causa provável (não corrigida):** `profiles` SELECT own-row (`id = auth.uid()`) + WITH CHECK CJCO `exists (profiles.hub_published)` / `exists (products ⨝ profiles)` avaliados como o comprador — o EXISTS não vê a loja published.  
**Impacto:** quem usa a app como o Flutter (`FollowsTable().insert` / `FavoritesTable().insert`) não consegue seguir nem favoritar lojas/SKUs à venda. Não é P0 (sem dinheiro). Não é P1 explorável para prémio/rifa (tickets 0).  
**Repro:** `confirm_a1.json`, `confirm_fav_visible.json`, `confirm_views.json`, pass1 A1/A3.  
**Sev:** P2 (happy path partido + hygiene RLS).  
**Prova:** A1 403; A3 403; favorite SKU visível 403.

### CY-P2-2 · CY5 · OPTIONS CORS reflecte `chrome-extension://` e `https://evil.fleaber.pt`

**Actor:** browser / Origin header.  
**Pré:** Edge `create-mux-live` OPTIONS + `resolve-mux-playback` POST.  
**Request:** OPTIONS Origin=`chrome-extension://abcdefghijklmnopqrstuvwxyz1234` → ACAO=**o mesmo**. OPTIONS Origin=`https://evil.fleaber.pt` → ACAO=**o mesmo**. Origin `null` / `https://evil.example` / `file://` → ACAO=`https://fleaber.pt` (HOLD). POST **não** reflecte (ACAO fleaber.pt).  
**Esperado:** allowlist exacta; hostil → `https://fleaber.pt` também no preflight.  
**Obtido:** preflight allowlist fura em extensão Chrome e subdomínio `*.fleaber.pt`. O POST real não espelha — o browser deve falhar o request final se ACAO do POST ≠ Origin. Residual de preflight.  
**Impacto:** hygiene CORS; não comprovámos leitura cross-origin autenticada.  
**Repro:** pass3b C2.  
**Sev:** P2  
**Prova:** `pass3b.json` opt.ext / opt.sub.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| A2 follow unpublished clássico | 403 — **não conta** (anti-atrofia). Não prova política: published também 403. |
| A4 favorite unpublished clássico | 403 — **não conta**. Idem. |
| A5 ghost/self/spoof | 403 (lockout total) |
| A6 race | follow 403; S2 sem handle — publish PATCH não equivalente a `batata_publish_hub` |
| A7–A9 sold/qty0/unlisted | 403 indistinguível da lockout A3 |
| A10 PATCH/UPSERT | sem row A1; UPSERT 403 |
| B1 mid-unpublish unpaid | Session + GET pending; S1 restaurado `hub_published=true` |
| B1 pago 4242 | SKIP sem `sk_test_` local |
| B2 amount/tip_id/seller | 400 |
| B3 GET/RPC unpaid | pending Δ=0 |
| C1 B1/B2 create-mux | 403 «Apenas contas de vendedor»; B2 é comprador |
| C1 S2 body.seller_id=S1 | live.owner=S2; extra fields ignorados; complete-mux timeout → PATCH ended |
| C3 resolve unpublished | anon/B1 404; dono 200 studio (`confirm_c3.json`) |
| PaysafeCash / PicPay / Coptic | não corridos |

--------------------------------------------------
## LENTES
--------------------------------------------------

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| CY1 follow published | SIM A1/A2/A5 | P2-1 |
| CY2 favorite | SIM A3/A4/A7–A9 + SKU Hub | P2-1 |
| CY3 tip | SIM B1 RPC mid-unpub + B2 + B3 | não |
| CY4 Mux | SIM C1 create + C3 resolve | não |
| CY5 Edge/CORS | SIM C2 OPTIONS/POST | P2-2 |
| CY6 race | SIM A6 (não isolável) | não |
| CY7 composição | SIM own-row × EXISTS; follow→rifa 0 | P2-1 |

Lentes 7/7 (mín. 5).

--------------------------------------------------
## INVARIANTES (órbita Hub/Edge)
--------------------------------------------------

Tip amount/`tip_id` autoridade HOLD. JWT saldo unpaid HOLD. Mid-unpublish RPC não creditou Session não paga. Captura paga após unpublish **não** exercitada. create-mux ignora `seller_id` do body. Buyer Mux 403.

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_cy_20260906T1450/_rtcy.dart`
- `pass1.dart` + `pass1.json` + `pass1_ids.json`
- `confirm_a1.dart` + `confirm_a1.json`
- `confirm_views.json` + `confirm_fav_visible.json`
- `pass2.dart` + `pass2.json` (B1 inicial SKIP S2 sem handle)
- `pass2b.dart` + `pass2b.json` (B1 válido em S1)
- `pass3.dart` (timeout complete-mux) + `pass3b.json`
- `confirm_c3.json`
- este `FROZEN_REPORT.md` + `FROZEN_REPORT.json`

**NÃO CORRIGIR.**
