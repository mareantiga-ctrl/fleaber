# FROZEN_REPORT — REDTEAM_BLIND_EH_PAYMETHOD_POS_OPEN_v1

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
AUDITOR: REDTEAM_BLIND_EH_PAYMETHOD_POS_OPEN_v1
FROZEN_AT: 2026-09-06T19:20:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [EH-A, EH-B, EH-C]
probes_na_tabela: 16
classes_novas: 16
stripe_test_pago: true
VEREDICTO: PASS_CEGO_SATURADO
prefix: RTEH-20260906T1908
staging: fxdknzrqjenzqcvnwqqq
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTEH-20260906T1908-` · pasta: `tool/redteam_blind_eh_20260906T1908/`.  
Atacantes: buyer JWT · seller JWT · buyer2. `service_role` só fixture / observação / restore.

Pago TEST: encomenda `ab1f4713-…` SKU `e1a2e812-…` PI `pi_3UCkZQH7FWYUN3jh1ISdSCkT` `succeeded` 590¢ qty 2→1 `applied=1` pm `Pagamento na app`.

--------------------------------------------------
## Missão
--------------------------------------------------

Multibanco, Ifthenpay, COD, SIBS, wraps MB WAY/transf **nunca** abrem `cs_`. Pagamento na App / card / applepay / googlepay **abrem**. JSON/`notes` hostis não substituem a coluna. RPC `batata_is_off_platform_payment` alinhado ao checkout.

**Resposta:** denylist cobre exactos + JSON `{"psp":"ifthenpay"}` + wraps novos (MBNet, IBAN) + array `["multibanco"]` + `referência` (não-ASCII fail-closed). CPI lê só `orders.payment_method` (body `card` / notes ifthenpay ignorados). PATCH `ifthenpay` após `cs_` → 403 `order_money_fields_immutable`. buyer2 em encomenda off alheia → 400 belong, sem sid. App feliz confirmado (buyer1+buyer2) com `cs_test_`. 1× pago 4242 coerente. Unknown ASCII/Paysafe/JSON sem token da denylist **abre** Session (fail-open do desenho denylist, não bypass off).

--------------------------------------------------
## TABELA DE PROVAS (16)
--------------------------------------------------

| probe_id | poço | payload/resumo | classe_nova? | HTTP/RPC | BD / Stripe | HOLD\|FAIL\|SKIP |
|----------|------|----------------|--------------|----------|-------------|------------------|
| A1 | EH-A | `multibanco` | **SIM** | CPI **400** off-platform; RPC **true** | pm `multibanco`; sem sid | FAIL |
| A2 | EH-A | `ifthenpay` + JSON `{"psp":"ifthenpay"}` | **SIM** | CPI **400**+**400**; RPC **true**/**true** | pm gravados; insert JSON 201 texto; sem sid | FAIL |
| A3 | EH-A | `contra reembolso` / `contra_reembolso` / `COD` | **SIM** | CPI **400**×3; RPC **true**×3 | pm gravados; sem sid | FAIL |
| A4 | EH-A | `sibs` / `Referência Multibanco` / `referência` | **SIM** | CPI **400**×3; RPC **true**×3 | inclui `referência` sozinha (não-ASCII); sem sid | FAIL |
| A5 | EH-A | `MB WAY (MBNet) ref 88321` wrap novo | **SIM** | CPI **400**; RPC **true** | pm persistido; sem sid | FAIL |
| A6 | EH-A | `transferência bancária IBAN PT50` | **SIM** | CPI **400**; RPC **true** | pm persistido; sem sid | FAIL |
| A7 | EH-A | array `["multibanco"]` + notes ifthenpay em App + body `card` em `sibs` | **SIM** | array **400** off; sibs+body **400** off; App+notes **200** `cs_` (confirm) | array persistido texto; App pm intacto | FAIL |
| B1 | EH-B | `Pagamento na App` → `cs_` | **SIM** | confirm **200** `cs_test_a1rwDxHR…` / `a1fNP5Ng…`; RPC **false** | pass1 teve claim contention; refutado | FAIL |
| B2 | EH-B | `card` → `cs_` | **SIM** | confirm **200** `cs_test_a1uWE5PS…` / `a16nVfvS…`; RPC **false** | idem | FAIL |
| B3 | EH-B | `applepay` / `googlepay` | **SIM** | confirm **200**+**200** `cs_test_a15pPSB2…` / `a1MRuTZo…`; RPC **false** | pass1 googlepay já 200; applepay contention refutado | FAIL |
| B4 | EH-B | 1× pago 4242 App | **SIM** | e2e **200** succeeded | `pago` 590¢ qty 2→1 applied=1 PI `pi_3UCkZQH7FWYUN3jh1ISdSCkT` | FAIL |
| C1 | EH-C | PATCH `ifthenpay` após `cs_` | **SIM** | open **200** `cs_test_a174KE50…`; PATCH B/S **403** 42501 immutable | pm ficou `Pagamento na App`; sid intacto | FAIL |
| C2 | EH-C | buyer2 CPI order `multibanco` alheia | **SIM** | own **400** off; b2 **400** does not belong | sem sid; pm `multibanco` | FAIL |
| C3 | EH-C | RPC vs CPI 6 labels | **SIM** | off 400 ⇔ sql true; App/card/applepay 200 ⇔ sql false | alinhados | FAIL |
| C4 | EH-C | empty / null method | **SIM** | insert **201**/**201**; RPC **false**; CPI **200** `cs_test_a1S7mMz9…` | unlabeled = App (denylist); não é bypass off | FAIL |
| C5 | EH-C | Paysafe / lixo ASCII / JSON `{"psp":"paysafe"}` | **SIM** | RPC **false**×3; CPI **200**×3 `cs_` | unknown ≠ denylist → App; JSON *com* ifthenpay já 400 em A2 | FAIL |

Linhas na tabela: **16**. classe_nova=**16**. Residual clássico (`mb way` exact / `mb way x` / mbωay) = **0/16** → **não** ATROFIA_ABORT.  
Stripe TEST pago: **sim**. P0–P2=0. Findings contados: **0**.

HOLD na tabela = finding (nenhum após confirm). FAIL = ataque bloqueado ou feliz alinhado. SKIP = 0.

--------------------------------------------------
## Lentes
--------------------------------------------------

| Lente | Evidência |
|-------|-----------|
| EH-A off | A1–A6 400+RPC true; A7 array/body off 400 |
| EH-B App | B1–B3 confirm `cs_`; B4 PI succeeded; A7 notes não mata App |
| EH-C forge | C1 immutable; C2 IDOR deny; C3 alinhado; C4/C5 unknown=App |

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

Nenhum. P0=0 P1=0 P2=0 P3=0.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| pass1 B1/B2/A7-notes/applepay `order claim contention` | mutex comprador 120 s (`batata_checkout_mutex`) no mesmo JWT — **não** é App morto. Confirm buyer2+buyer1: todos `cs_`. **não conta** |
| C5 Paysafe / `asdfghjklpay` / JSON paysafe abre `cs_` | denylist fail-open para label **sem** token off; A2 JSON ifthenpay **400**. Missão JSON hostil = PSP off no JSON, não allowlist. **não conta** |
| C4 empty/null abre `cs_` | RPC false (não off); App-default do desenho denylist. **não conta** |
| `mb way` exact / `mb way x` / unicode mbωay | **não corridos** (anti-atrofia HOLD ≤1) |
| A1–A3 exactos DZEE | reteste obrigatório da matriz EH-A; defesa **400**; não é wrap `x` |

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
9. Buyer manipula preço autoritativo — NÃO COMPROVADO (poço método)
10. Buyer manipula qty autoritativa — NÃO COMPROVADO
11. Seller falsifica pagamento plataforma — NÃO (C1 PATCH 403; A7 body card ignorado)
12. JWT cria saldo/fundos — NÃO (B4 e2e; Δ wallet não medido aqui)
13. Refund excede captura — NÃO COMPROVADO
14. Release+refund cria dinheiro líquido — NÃO COMPROVADO
15. Payout duplica Transfer — NÃO COMPROVADO
16. Stock=1 duas vendas válidas — NÃO COMPROVADO (fora da matriz)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO (C2 sem sid)
20. Cross-user dados sensíveis — NÃO (C2 belong, não vaza método)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO (C1 seller PATCH pm 403)
23. Reviews forjadas — NÃO (fora da matriz)
24. RPC SECURITY DEFINER perigoso executável — NÃO (boolean off-platform)
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO (body/notes não substituem BD)
27. Regressão funcional (happy path partido) — NÃO (confirm App `cs_`; B4 pago)
28. Saturação atingida — SIM (16 probes; 16 classe_nova; 1 pago; P0–P2=0; residual 0%)

Poços EH: off=SIM · App=SIM · forge=SIM  
ATROFIA: NÃO (0/16 residual clássico; 0 `mb way x` / omega)  
**NÃO CORRIGIR.**

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
