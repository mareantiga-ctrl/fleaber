# FROZEN_REPORT — RED TEAM CEGO ET · bag∥single + Hub · GATE FASE 4

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 1
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 1

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? SIM
4. Quantos P1: 1
5. P2 hygiene encontrado? NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_ET_BAG_SINGLE_HUB_RETEST_v1
FROZEN_AT: 2026-09-06T21:18:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [ET-A, ET-B, ET-C]
probes_na_tabela: 12
classes_novas: 7
races: 7
stripe_test_pago: true
VEREDICTO: FAIL_P1
prefix: RTET-20260906T2113
staging: fxdknzrqjenzqcvnwqqq
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded`: `pi_3UCmSz*`, `pi_3UCmTV*`, `pi_3UCmTl*`; saco `setup_paid_bag` `pi_3UCmTRH*` 1115¢) · actores JWT B1/S1/B2/B3 + B4 fresco `bb3f3df4-…` · `service_role` só fixture / observação / restore. Código **não** corrigido. Produção intocada. Fase 4 **não**.

S1 `980f4fa1-…` `hub_published=true` à saída. Sem lives activas deixadas pelo pass1.

Sem `STRIPE_SECRET_KEY` `sk_test_` local → sessionOracle HTTP 0. Prova de dual = **2× HTTP 200** + **2 `cs_test_` distintas** + `reused=false`. **Não** pagámos as duas (missão ET = Hub/composição, não captura).

--------------------------------------------------
## P1-1 — Saco e artigo avulso ao mesmo tempo: dois links; Hub sem oversell

**O que isto é:** o comprador pede o pagamento do saco (3 artigos) e, no mesmo instante, o pagamento só do artigo do meio. O cadeado tinha de entregar no máximo um link. A loja (Hub) tinha de continuar a mostrar as unidades certas (sem vender a dobrar).

**Quem / onde:** Comprador B3 fresco `0c90fb4e-…` (pass1 A1) e B4 fresco `bb3f3df4-…` · Vendedor S1 · 3 artigos qty=2 visíveis na loja.

**O que fizemos:**
- A1: saco ABC ∥ avulso B, t=0 (`Future.wait`) no **primeiro** checkout do B3.
- A4: saco ∥ avulso ∥ saco (3 pedidos) no mesmo B3 **já quente** → 1 `cs_`.
- Confirm no mesmo B3: A1–A4 `cs_n=1`.
- Burst B3 quente: 6/6 com 1 link.
- Burst B4 **fresco**: 4 tiros t=0 → **1 dual** (ronda 0) + 3 reuse.

**Esperado vs resultado**
- API t=0 (frio): esperado ≤1 `cs_` útil · visto **2** `cs_test_` distintas, ambas HTTP 200, `reused=false` (pass1 A1 `a1sMBnDy…` + `a1Pnt02t…`; B4 ronda 0 `a1jOzDiq…` + `a1v2KOp0…`)
- API t=50 / avulso first / 3-way no quente: 1 `cs_` reused (A2, A3, A4) — cadeado **fecha** se o comprador já tem Session
- Ledger pass1 A1: as 3 linhas = Session do **saco**; a Session avulsa ficou órfã
- Loja: Hub n=1 nas 3 linhas (hold, **sem oversell** visível)
- Stripe: sem `sk_test_` local — **não pagámos as duas**

**Conclusão:** **P1** — bag∥single no fio com Hub ainda entrega dois links no **primeiro** tiro paralelo de um comprador fresco (1/1 no B3 A1; 1/4 no B4). Depois do primeiro claim, A2–A4 / burst quente / confirm = 1 `cs_`. 6∥4 / expand / idêntico **continuam fechados**. Não é P0: não há duas capturas nem stock a dobrar no Hub.
**Prova:** `pass1.json` A1 · `burst_fresh.json` ronda 0.

--------------------------------------------------
## TABELA DE PROVAS (12)
--------------------------------------------------

| probe_id | superfícies tocadas | acção | HTTP | oráculos multi-sítio | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|---------------------|-------|------|----------------------|------------------|--------------|
| A1 | bag ABC + single B + Hub + orders | **bag∥single t=0** | **2× 200** `cs_`; `reused=false` | **2 cs_**; ledger=saco×3; órfã single; Hub n=1×3 | **HOLD** | SIM |
| A2 | bag∥single t=50 + Hub leftover + orders | leftover pago + bag first →50ms single | 200+200 **1** `cs_` reused | leftover Hub n=1 qty=1 `pago`; Hub bag n=1×3 | FAIL | SIM |
| A3 | single first + bag + Hub + orders | avulso B →50ms saco ABC | 200+200 **mesmo** `cs_` reused | Hub n=1×3; ledger linha B | FAIL | SIM |
| A4 | bag∥single∥bag + Hub + orders | 3 corrotinas t=0 (B3 quente) | creates=1 3×200 | ledger 1 sid; Hub n=1×3; confirm `cs_n=1` | FAIL | SIM |
| A5 | bag 6∥4 + Hub + orders | **6∥4** regressão ≤1 | bag6 **400** overlapping; bag4 200 1 `cs_` | Hub n=1×6; confirm 400+200 `cs_n=1` | FAIL | NÃO |
| B1 | Hub + 2 buyers CPI qty=1 | Future.wait B2∥B3 | Hub0 n=1; 2.º insert 400 hold; 1 `cs_` | Hub após n=0; o2 null; ≤1 encomenda | FAIL | NÃO |
| B2 | bag expand + Hub + Session | subset AB →50ms ABCD | sub 200 1 `cs_`; super **400** overlapping | Hub n=1×4 | FAIL | NÃO |
| B3 | bag idêntico + Hub | 2× mesmo saco ABC | 2× 200 **1** `cs_` reused | sids=1; reused [false,true]; Hub n=1×3 | FAIL | NÃO |
| C1 | Hub + order + chat + wallet | bag pago 4 sítios | e2e 200 `pi_3UCmTRH…` 1115¢; ambas `pago` | paidA 335 + paidB 780 = PI; Hub leftover n=1+1; qty 3→2; Δwallet 0/0 | FAIL | SIM |
| C2 | Hub + orders + CPI leftover | leftover qty 2→1 | e2e 200 `pi_3UCmTV…`; leftover `cs_test_a1zqwFDY…` | status `pago`; qty=1; Hub n=1; leftover comprável | FAIL | NÃO |
| C3 | offer + CPI + Hub + orders | oferta 8€ aceite + CPI amount=1 | CPI **400** `order claim contention` | offer accepted 8€; Hub n=1; underpay **não** selado | FAIL | SIM |
| C4 | release∥disputa + wallet + Hub | Future.wait release + POST disputa | release 200 true; disputa 201 `aberta` | Δ snapshot 0; 1 efeito líquido; status `concluido`; Hub n=1 | FAIL | SIM |

Linhas na tabela: **12**. Stripe TEST pago: **sim**. HOLD = A1 = 1/12 ≈ 8% ≪ 40%. **Não** ATROFIA_ABORT. Classes novas: A1 t=0 dual · A2 t=50+leftover · A3 single-first · A4 3-way · C1 bag pago 4 sítios · C3 oferta selo · C4 release∥disputa (**7 ≥ 4**). Races: A1, A2, A3, A4, A5, B2, C4 (**7**; bag∥single/regressão A1–A4+A5 ≥4).

Burst fresco B4: 1 dual / 4 tiros (só ronda 0). Burst B3 quente: 0 dual / 6. Confirm B3: A1–A4 `cs_n=1`; A5 400+200.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 1
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (C3 CPI 400 vs body 1)
10. Buyer manipula qty autoritativa — NÃO (B1 hold `order_hold_exceeds_stock`)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (C4 Δ 0; C1 Δ 0/0 até release)
13. Refund excede captura — NÃO (fora da matriz ET)
14. Release+refund cria dinheiro líquido — NÃO (C4 net 0)
15. Payout duplica Transfer — NÃO (fora da matriz)
16. Stock=1 duas vendas válidas — NÃO (B1 2.º recusado)
17. Stock=1 duas capturas líquidas permanentes — NÃO (2 `cs_` órfãs **não pagas**)
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora da matriz)
24. RPC SECURITY DEFINER perigoso executável — NÃO
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO (C3 400 contention / não selou 1¢)
27. Regressão funcional (happy path partido) — NÃO (C1 bag pago 4 sítios; C2 leftover; A5 6∥4; B2 expand)
28. Saturação atingida — NÃO (P1 aberto; quota e classes novas cumpridas)

Poços ET: hub=SIM · bag=SIM · race=SIM · caixa=SIM · stock=SIM  
ATROFIA: NÃO (1/12 HOLD; ângulos novos = t=50 leftover, single-first, 3-way quente fechado, burst fresco ronda 0)  
Pagamento TEST: **pago** (vários PI `succeeded` + saco 1115¢).

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

| ID | Severidade | Título |
|----|------------|--------|
| P1-1 | P1 | P1-A1-BAG-SINGLE-HUB — bag∥single duas Sessions úteis (t=0 no comprador fresco) |

Soma P0+P1+P2+P3 `quantos` = 1.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| A2 t=50 leftover | **Fechado.** 1 `cs_` reused; leftover Hub n=1 qty=1. |
| A3 single-first | **Fechado.** mesmo `cs_` reused. |
| A4 3-way (B3 quente) | **Fechado nesta ronda.** creates=1; confirm `cs_n=1`. Dual só no **fresco**. |
| A5 6∥4 dual | **Fechado.** 400+200; confirm `cs_n=1`. |
| B2 expand dual | **Fechado.** 200+400 overlapping. |
| B3 2× idêntico | **1 `cs_` reused.** Não contar. |
| B1 2 buyers qty=1 | 2.º insert 400 hold; 1 `cs_`. Residual, não contar. |
| C2 leftover 2→1 | Hub n=1 + leftover comprável. Residual, não contar. |
| C3 oferta underpay | CPI **400** `order claim contention` (não selou 1¢). Anti-atrofia, não contar. |
| C4 release∥disputa | Race API: release `true` **e** disputa `aberta`. Δ wallet **0**. **1 efeito dinheiro** — anti-atrofia, não contar. |
| C1 chat card 400 | Ambas linhas `pago`, Hub leftover, Δwallet 0. Card 400 (`chat_system_card_notes_forbidden`) não é dinheiro; não contar. |
| Confirm B3 A1–A4 | `cs_n=1` — comprador **quente** (sessões abertas). Não desmente o dual no fresco. |
| Burst B3 6× | 0 dual — mesmo efeito quente. Não contar como fecho. |

--------------------------------------------------
## LENTES
--------------------------------------------------

| Lente | Evidência |
|-------|-----------|
| ET-A bag∥single + Hub | A1 dual t=0 fresco; A2 t=50 fechado + leftover Hub; A3 single-first fechado; A4 3-way fechado no quente; A5 6∥4 400 |
| ET-B stock / live | B1 2 buyers hold; B2 expand 400; B3 idêntico reuse |
| ET-C caixa | C1 saco 1115¢ proporcional + Hub leftover; C2 leftover 2→1; C3 400 contention; C4 Δ 0 |

--------------------------------------------------
## FIO (Hub + saco + caixa)
--------------------------------------------------

**bag∥single t=0 fresco (A1 P1)** → t=50+leftover (A2 fechado) → single-first (A3 fechado) → 3-way quente (A4 fechado) → 6∥4 (A5 fechado) → 2 buyers (B1) → expand (B2 fechado) → idêntico (B3) → **bag pago 4 sítios (C1)** → leftover 2→1 (C2) → oferta 400 (C3) → release∥disputa (C4). Burst fresco **1/4 dual** (só 1.º tiro).

--------------------------------------------------
## GATE FASE 4
--------------------------------------------------

P0–P2=0 nos 3 (ER+ES+ET) → OK avançar para Fase 4 / abertura.  
Qualquer P1 dual → **ainda não**.

**Este relatório:** dual create no bag∥single (t=0, comprador fresco, 1.º tiro) → **FAIL_P1** (**não Fase 4**).  
6∥4 / expand / idêntico / leftover Hub / saco pago: fail-closed ou happy path OK.

--------------------------------------------------
## OPERAÇÃO
--------------------------------------------------

- S1 `hub_published=true` à saída.
- Pasta: `tool/redteam_blind_et_20260906T2113/` (`pass1.json`, `confirm.json`, `burst_a1.json`, `burst_fresh.json`).
- **NÃO CORRIGIR.** Fase 4 não.

```
AUDITOR: REDTEAM_BLIND_ET_BAG_SINGLE_HUB_RETEST_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: 12 · classes_novas: 7 · races: 7
VEREDICTO: FAIL_P1
```

RESUMO_NUMERICO: P0=0 P1=1 P2=0 P3=0 TOTAL=1
