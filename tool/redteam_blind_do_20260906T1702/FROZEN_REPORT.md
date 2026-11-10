# FROZEN_REPORT — REDTEAM_BLIND_DO_PAYMETHOD_HUB_POS_DHDM_v1

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
AUDITOR: REDTEAM_BLIND_DO_PAYMETHOD_HUB_POS_DHDM_v1
FROZEN_AT: 2026-09-06T17:12:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DO1, DO2, DO3, DO4, DO5, DO6, DO7]
probes_na_tabela: 16
classes_novas: 12
stripe_test_pago: true
VEREDICTO: PASS_CEGO_SATURADO
prefix: RTDO-20260906T1702
staging: fxdknzrqjenzqcvnwqqq
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTDO-20260906T1702-` · pasta: `tool/redteam_blind_do_20260906T1702/`.  
Atacantes: anon · buyer JWT · seller JWT · buyer2 · seller2. `service_role` só fixture / observação / restore.

Pago TEST: encomenda `eb82daf3-…` SKU `95e8daab-…` PI `pi_3UCic9H7FWYUN3jh1F1PzSKc` `succeeded` 590¢ qty 2→1 `applied=1`.

S1 `980f4fa1-…` `hub_published=true` à saída. Lives de fixture `ended`.

--------------------------------------------------
## Missão
--------------------------------------------------

Off-platform (MB WAY / transf) **nunca** abre `cs_`. `Pagamento na App` / card **sempre** pode. Hub: stock efectivo (orders hold + live accepted) = o que a montra mostra. Atacar mismatch CPI body ≠ BD, wrap novo, Hub qty parcial, unpublish+list, favorite+hold.

**Resposta:** CPI lê só `orders.payment_method` (body `card` / notes / array ignorados para o gate). Exacto + wrap emoji/!!! + array `["MB WAY"]` → 400 sem sid. Card com ZWSP/NBSP no meio **abre** Stripe (App a salvo). Hub esconde qty efectiva 0 (live accepted e `reservado`); leftover 1 continua visível e comprável. Anon e JWT concordam. Unpublish esconde a vitrine; checkout marketplace de encomenda já criada ainda abre Session (produto continua listado). Favorite unpublished 403; favorite em live-hold 201 sem caminho de compra (não conta).

--------------------------------------------------
## TABELA DE PROVAS (16)
--------------------------------------------------

| probe_id | poço | payload/resumo | classe_nova? | HTTP/RPC | BD / Hub / Stripe | HOLD\|FAIL\|SKIP |
|----------|------|----------------|--------------|----------|-------------------|------------------|
| A1 | DO-A | BD `MB WAY` + CPI body `card` | **SIM** | CPI **400** off-platform | SQL `true`; pm BD `MB WAY`; sem sid | FAIL |
| A2 | DO-A | `Pagamento na app` + notes/body MB WAY | **SIM** | CPI **200** `cs_test_a144GyA9…` | coluna `notes` inexistente (PGRST204); pm App; App **não** morreu | FAIL |
| A3 | DO-A | `ca\u200Brd` + `ca\u00A0rd` | **SIM** | CPI **200**+**200** `cs_test_a1T64Tt3…` / `a1sidPyN…` | SQL `false`/`false`; App a salvo | FAIL |
| A4 | DO-A | pm array / número / JSON; confirm `["MB WAY"]` | **SIM** | insert arr/num **201** (texto); obj 400 hold; confirm CPI array-off **400** | persistido `["card"]` / `1` / `["MB WAY"]`; SQL off true no wrap MB WAY; sem sid | FAIL |
| A5 | DO-A | `MB WAY 🎉` + `MB WAY!!!` | **SIM** | CPI **400**+**400** off-platform | SQL `true`/`true`; pm persistido; sem sid | FAIL |
| B1 | DO-B | live accepted qty=1 → Hub + insert (reteste 1 linha) | NÃO | insert **400** hold; Hub **200 []** | sellable `false` held=1; qty=1 listed; fav 201 (descartado) | FAIL residual |
| B2 | DO-B | live accepted 1 de stock=2 | **SIM** | Hub **1** linha; insert qty=1 **201**; qty=2 **400** hold | qty=2 held=1 sellable true; CPI leftover OK | FAIL |
| B3 | DO-B | order `reservado` marketplace hold | **SIM** | Hub **200 []**; insert 2.º **400** hold | status `reservado`; held=1 sellable false | FAIL |
| B4 | DO-B | Future.wait accept ∥ unlist ∥ Hub | **SIM** | accept 200; unlist 200 listed=false; insert 400 | Hub 0/0; held=1 | FAIL |
| B5 | DO-B | pago leftover qty=1 → Hub 1 | **SIM** | Hub **1** anon+JWT; insert **201**; CPI **200** `cs_` | qty=1; PI `pi_3UCic9H7…` 590¢ | FAIL |
| C1 | DO-C | `list_on_marketplace=true` + `is_sold=true` | NÃO | Hub **200 []**; insert **400** hold | sold+listed; sellable RPC true (view filtra `is_sold`) | FAIL residual |
| C2 | DO-C | unpublish mid-browse + CPI | **SIM** | Hub 1→**0**; unpub 200; CPI **200** `cs_test_a1L2tcZZ…` | listed=true; loja restaurada `true` | FAIL |
| C3 | DO-C | favorite SKU loja unpublished | NÃO | POST favorites **403** 42501 | Hub n=0; allowed=false | FAIL residual |
| C4 | DO-C | hub_products_public anon vs JWT | **SIM** | pub 1=1; sold 0=0; unpub 0=0; hold 0=0 | sem divergência | FAIL |
| D1 | DO-D | 1× pago 4242 card limpo | **SIM** | e2e **200** succeeded | `pago` 590¢ qty 2→1 applied=1 PI `pi_3UCic9H7FWYUN3jh1F1PzSKc` | FAIL |
| D2 | DO-D | off exact `MB WAY` | NÃO | CPI **400** off-platform | SQL `true`; sid vazio | FAIL residual |

Linhas na tabela: **16**. classe_nova=**12**. Residual clássico B1+C1+C3+D2 = **4/16 = 25%** ≪ 40% → **não** ATROFIA_ABORT.  
Stripe TEST pago: **sim**. P0–P2=0. Findings contados: **0**.

HOLD na tabela = finding (nenhum). FAIL = ataque bloqueado ou feliz alinhado. SKIP = 0.

--------------------------------------------------
## Lentes (≥5/7)
--------------------------------------------------

| Lente | Evidência |
|-------|-----------|
| DO1 method mismatch | A1 body card ignorado; D2 exact 400 |
| DO2 wrap novo | A5 emoji/!!! 400; A3 ZWSP card ainda App |
| DO3 Hub hold | B1 Hub 0 + insert deny; B3 reservado; B4 race |
| DO4 partial stock | B2 Hub mostra leftover; B5 Hub 1 após pago |
| DO5 published | C1 sold escondido; C2 unpub esconde Hub; C3 fav 403; C4 anon=JWT |
| DO6 App safe | A2 notes não mata; A3 ZWSP/NBSP abre `cs_` |
| DO7 caixa | D1 PI succeeded 590¢ qty 2→1 |

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

Nenhum. P0=0 P1=0 P2=0 P3=0.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| B1 Hub hide qty=1 live accepted | **residual** fecho DHDM — não conta |
| C1 sold+listed Hub 0 | residual view `is_sold=false` — não conta |
| C3 favorite unpublished 403 | residual CVDA — não conta |
| D2 `MB WAY` exact 400 | anti-atrofia exacto — não conta |
| A4 persist array/número como texto | PostgREST coerção `["card"]` / `1`; wrap `["MB WAY"]` **ainda 400** (`confirm_a4.json`) — não é bypass off-platform |
| B1 favorite 201 em SKU live-hold | Hub 0 + insert deny; `fav_allowed=true` porque qty coluna>0 listed not sold. Wishlist ≠ compra. Sem sid. **não conta** |
| C2 CPI `cs_` após unpublish | encomenda já criada; produto **ainda** `list_on_marketplace=true`; vitrine Hub 0. Superfícies distintas, não oversell |
| Wraps ASCII `mb way x` / `xxmbway` / `via mb way` / omega / math | **não repetidos** (HOLD DHDM) |

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
9. Buyer manipula preço autoritativo — NÃO COMPROVADO (poço método/Hub)
10. Buyer manipula qty autoritativa — NÃO (B2 qty=2 deny)
11. Seller falsifica pagamento plataforma — NÃO (A1 BD off manda)
12. JWT cria saldo/fundos — NÃO (D1 e2e; Δ não creditado aqui)
13. Refund excede captura — NÃO COMPROVADO
14. Release+refund cria dinheiro líquido — NÃO COMPROVADO
15. Payout duplica Transfer — NÃO COMPROVADO
16. Stock=1 duas vendas válidas — NÃO (B1/B3 insert deny)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (C4 anon=JWT)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora da matriz)
24. RPC SECURITY DEFINER perigoso executável — NÃO (sql off / sellable / held só boolean/int)
25. RLS crítico quebrado — NÃO (fav unpublished 403)
26. Edge confia total do cliente — NÃO (CPI body card/notes/array não substituem BD)
27. Regressão funcional (happy path partido) — NÃO (A2/A3 App abre; D1 pago; B5 leftover)
28. Saturação atingida — SIM (16 probes; 12 classe_nova; 1 pago; P0–P2=0; residual 25%)

Poços DO: off mismatch=SIM · wrap novo=SIM · Hub hold=SIM · partial=SIM · published=SIM · App safe=SIM · caixa=SIM  
ATROFIA: NÃO (4/16 residual; 0 `mb way x` / omega / hide clássico como finding)  
**NÃO CORRIGIR.**

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
