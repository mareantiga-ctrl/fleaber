# FROZEN_REPORT — RED TEAM CEGO DE · Hub / follow / favorite / tip / Mux · POS_CVDA

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 0

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado? NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_DE_HUB_EDGE_POS_CVDA_v1
FROZEN_AT: 2026-09-06T15:45:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DE1, DE2, DE3, DE4, DE5, DE6, DE7]
probes_na_tabela: 16
VEREDICTO: PASS_CEGO_SATURADO
prefix: RTDE-20260906T1538
staging: fxdknzrqjenzqcvnwqqq
```

Staging · Stripe TEST (`cs_test_*` criadas, **não** pagas — `sk_test_` ausente no env local) · actores JWT B1/S1/B2(comprador)/S2(vendedor) · `service_role` só fixture / observação / restore. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

CVDA `batata_profile_is_hub_published` / `batata_product_is_favorite_allowed` SECURITY DEFINER: A1 follow published **201**, A3 favorite published **201**. CORS chrome-extension e `https://evil.fleaber.pt` → ACAO `https://fleaber.pt` (não eco).

S1 `980f4fa1-0004-42f9-abca-69f1a9c29588` `hub_published=true` após B1. Lives de fixture + Mux `9fdd06e0-…` `status=ended`. B2 `user_type=comprador`.

--------------------------------------------------
## TABELA DE PROVAS (16)
--------------------------------------------------

| probe_id | poço | published? | HTTP/RPC | BD | HOLD\|FAIL\|SKIP |
|----------|------|------------|----------|-----|------------------|
| A1 | DE-A | **sim** S1 | POST follows B1→S1 **201** | follow `7b67572d-…` following=S1 | **HOLD** (feliz CVDA; não conta) |
| A2 | DE-A | não S2 (controlo clássico) | POST follows 403 42501 | raffle tickets 0 | HOLD residual (não conta) |
| A3 | DE-A | **sim** SKU S1 | POST favorites **201** | fav `befb560c-…` product `368a8faa-…` | **HOLD** (feliz CVDA; não conta) |
| A4 | DE-A | não SKU S2 | POST favorites 403 42501 | — | HOLD residual (não conta) |
| A5 | DE-A | ghost / self / spoof follower | todos 403 42501 | — | HOLD |
| A6 | DE-A | race unpublish ∥ follow | follow 403; hub_after=false | tickets 0; follow_id null | HOLD |
| A7 | DE-A | DEFINER RPC | B1 pub=true unpub=false ghost=false; anon **401**; favPub=true favUnpub=false | — | HOLD |
| A8 | DE-A | sim sold/qty0/unlisted | 403 42501 ×3 | — | HOLD |
| A9 | DE-A | PATCH/UPSERT unpublished | PATCH **200 []** sem mutação; UPSERT 403 | following_id **ainda S1** (`confirm_a9.json`) | HOLD |
| A10 | DE-A | sim + user_id spoof B2 | POST favorites 403 42501 | — | HOLD |
| B1 | DE-B | sim→não (RPC S1) | Session 200 `cs_test_a1LkT3cE…`; unpub ok; GET unpaid pending; restore true | tip `pending`; Δwallet 0; S1 republicado | HOLD |
| B2 | DE-B | sim S1 | amount 0/0.01/-1/0.5/501 + tip_id cliente → 400; seller≠owner 400 | — | HOLD |
| B3 | DE-B | sim unpaid | GET B2/anon não credita; RPC settle ≠ credit; status pending Δ=0 | tip pending | HOLD |
| C1 | DE-C | body hostil | B1+B2 **403** authz; S2 200 live.owner=**S2** (body.seller_id ignorado); live ended | Mux `9fdd06e0-…` ended | HOLD |
| C2 | DE-C | CORS | OPTIONS Origin `chrome-extension://…` ACAO=`https://fleaber.pt`; OPTIONS `https://evil.fleaber.pt` ACAO=`https://fleaber.pt`; null/evil.example/file → fleaber.pt | `confirm_c2.json` | **HOLD** (controlo; não conta) |
| C3 | DE-C | não (live S2 unpublished) | anon/B1 **404** `live_not_public`; dono S2 **200** playback studio | live `49d6f4ae-…` ended | HOLD |

DE-A: 10 · DE-B: 3 · DE-C: 3 · **total 16** (≥12). Residual clássico A2+A4 = 2/16 ≪ 50%.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
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
20. Cross-user dados sensíveis — NÃO (resolve unpublished 404; DEFINER só boolean)
21. Buyer assume seller/admin — NÃO (create-mux 403 comprador)
22. Seller assume buyer/admin — NÃO (body.seller_id ignorado; owner=JWT)
23. Reviews forjadas — NÃO (fora da matriz DE)
24. RPC SECURITY DEFINER perigoso executável — NÃO (settle JWT não credita; DEFINER hub só boolean; anon 401)
25. RLS crítico quebrado — NÃO (published allow; unpublished deny)
26. Edge confia total do cliente — NÃO (tip_id/amount/seller mismatch 400; create-mux body ignorado; CORS não ecoa)
27. Regressão funcional (happy path partido) — NÃO (A1+A3 201)
28. Saturação atingida — SIM (A1+A3 201; unpublished deny; CORS não ecoa; P0–P2=0)

Poços DE: follow published=SIM · favorite=SIM · tip mid-unpub+amount+unpaid=SIM · Mux/Edge=SIM · CORS=SIM · race=SIM · composição=SIM  
ATROFIA: NÃO (2/16 residual clássico; 0 PaysafeCash/PicPay/Coptic; ângulos novos A5–A10/B/C1/C3)  
Pagamento TEST gorjeta: Session criada, **não** paga. Captura paga após unpublish NÃO COMPROVADA — lacuna honesta.

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

Nenhum. P0=0 P1=0 P2=0 P3=0.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| A1 follow published 201 | **não conta** (anti-atrofia / feliz CVDA) |
| A2 follow unpublished clássico | 403 — **não conta** (anti-atrofia) |
| A3 favorite published 201 | **não conta** (anti-atrofia / feliz CVDA) |
| A4 favorite unpublished clássico | 403 — **não conta** |
| A5 ghost/self/spoof | 403 |
| A6 race | follow 403; hub false; tickets 0 |
| A7 DEFINER RPC | B1 boolean correcto; anon 401 |
| A8 sold/qty0/unlisted | 403 |
| A9 PATCH 200 [] | **oráculo BD**: following_id ainda S1; UPSERT 403. Classificador HTTP 200 sem body **não** prova retarget. |
| A10 favorite user_id spoof | 403 |
| B1 mid-unpublish unpaid | Session + GET pending; S1 restaurado `hub_published=true` |
| B1 pago 4242 | SKIP sem `sk_test_` local |
| B2 amount/tip_id/seller | 400 |
| B3 GET/RPC unpaid | pending Δ=0 |
| C1 B1/B2 create-mux | 403 «Apenas contas de vendedor»; B2 é comprador |
| C1 S2 body.seller_id=S1 | live.owner=S2; PATCH ended |
| C2 CORS ext + evil.fleaber.pt | ACAO `https://fleaber.pt` — **não conta** (controlo) |
| C3 resolve unpublished | anon/B1 404; dono 200 studio |
| PaysafeCash / PicPay / Coptic | não corridos |

--------------------------------------------------
## LENTES
--------------------------------------------------

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| DE1 follow published | SIM A1/A2/A5 | não |
| DE2 favorite | SIM A3/A4/A8/A10 | não |
| DE3 tip | SIM B1 RPC mid-unpub + B2 + B3 | não |
| DE4 Mux | SIM C1 create + C3 resolve | não |
| DE5 CORS | SIM C2 OPTIONS ext + evil.fleaber.pt | não |
| DE6 race | SIM A6 | não |
| DE7 composição | SIM DEFINER RPC; PATCH/UPSERT; follow→rifa 0 | não |

Lentes 7/7 (mín. 5).

--------------------------------------------------
## INVARIANTES (órbita Hub/Edge)
--------------------------------------------------

Tip amount/`tip_id` autoridade HOLD. JWT saldo unpaid HOLD. Mid-unpublish RPC não creditou Session não paga. Captura paga após unpublish **não** exercitada. create-mux ignora `seller_id` do body. Buyer Mux 403. CORS preflight hostil → `https://fleaber.pt`. Follow/favorite published 201; unpublished 42501.

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_de_20260906T1538/_rtde.dart`
- `pass1.dart` + `pass1.json` + `pass1_ids.json`
- `confirm_a9.json` (PATCH 200 [] ≠ retarget)
- `pass2.dart` + `pass2.json`
- `pass3.dart` + `pass3.json`
- `confirm_c2.json` (ACAO por Origin + lives ended)
- este `FROZEN_REPORT.md` + `FROZEN_REPORT.json`

**NÃO CORRIGIR.**
