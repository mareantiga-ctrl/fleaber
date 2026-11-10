# FROZEN_REPORT — RED TEAM CEGO DR · tip / rifa / convert / Edge live money · POS_DHDM

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
AUDITOR: REDTEAM_BLIND_DR_TIP_RAFFLE_POS_DHDM_v1
FROZEN_AT: 2026-09-06T17:20:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DR1, DR2, DR3, DR4, DR5, DR6, DR7]
probes_na_tabela: 14
classes_novas: 7
races: 4
VEREDICTO: PASS_CEGO_SATURADO
prefix: RTDR-20260906T1708
staging: fxdknzrqjenzqcvnwqqq
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`cs_test_*` Sessions; **sem** `sk_test_` local → captura 4242 da gorjeta **não** exercitada, skip documentado) · JWT B1/S1 + B2/S2 fixture · `service_role` só fixture / observação / restore / end_live. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

FOMO allowlist / welcome / buyer refund 403 **não** na tabela (anti-atrofia). Tip mid-unpublish unpaid clássico sequencial **não** repetido; D1 é **race** POST tip ∥ unpublish + GET settle unpaid.

--------------------------------------------------
## TABELA DE PROVAS (14)
--------------------------------------------------

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|-----------|------------------|--------------|
| A1 | DR-A | amount 0/-1/0.5/501 + `"1e2"` + `[2]` + `amount_cents=1` | 400 invalid/too high; sci/arr/`cents` **200** `cs_test` | sci amount **100** pending; arr **2** pending; Δwallet **0** | **HOLD** | **SIM** |
| A2 | DR-A | tip_id UUID cliente; live S2 + seller_id S1 | live alheia **400** `Tip seller does not own`; tip_id em live válida **400** `Client tip_id is not allowed` | 0 Session | **HOLD** | **SIM** |
| A3 | DR-A | POST tip ∥ end_live + hub unpublish | **400** `Tips only allowed while the live is broadcasting` | Δwallet **0**; hub restored | **HOLD** | **SIM** |
| A4 | DR-A | seller_id S2 na live S1 | **400** `Tip seller does not own this live` | — | **HOLD** | não |
| B1 | DR-B | claim_share + join raffle_id inexistente | **200** `ok:false` `raffle_not_found` ×2 | tickets=0 winners=0 | **HOLD** | **SIM** |
| B2 | DR-B | join + claim_share rifa active | join **200** tickets=1; share **200** tickets=**2** `duplicate:false` | entry elegível t=2 | **HOLD** | não |
| B3 | DR-B | draw JWT buyer+S2; POST winners; draw seller×2 | buyer/S2 **400** `not_allowed`; insert **403** RLS 42501; seller draw **200** drawn; 2.º draw sem 2.º winner | nWinForge=0 nWinDouble=**1** | **HOLD** | **SIM** |
| C1 | DR-C | convert pending (RPC + CPI) | RPC **403** function denied; CPI mismatch **400** `live item does not match order` (pass2); pass1 CPI `cs_test` unpaid | res **pending**; order `reserva_pendente` ≠pago ≠converted | **HOLD** | **SIM** |
| C2 | DR-C | convert∥convert 2 buyers + IDOR res B1 | RPC×2 **403** denied; insert order **400** `order_hold_exceeds_stock` (CPI não arrancou) | B1 **accepted** B2 **pending**; nConv=0 nPago=0 | **HOLD** | **SIM** |
| C3 | DR-C | accept live_only ∥ marketplace CPI qty=1 | accept **200**; CPI **400** `Checkout blocked` | res **accepted**; order `reserva_pendente`; product qty=1 is_sold=false | **HOLD** | **SIM** |
| C4 | DR-C | convert após live ended | RPC **403** denied; PATCH **403** `convert_requires_paid_order` | status **accepted** ≠converted | **HOLD** | não |
| C5 | DR-C | converted capacity vs stock qty=1 | RPC **403**; 2.º accept **400** `qty_exceeds_stock` | A **accepted** B **pending**; convert unpaid recusado | **HOLD** | não |
| D1 | DR-D | tip Session TEST ∥ unpublish; GET settle unpaid | POST **200** `cs_test_a18wSGEA…`; GET **200** «Pagamento ainda não confirmado» | tip `7ce47904-…` **pending** amount=2; Δwallet **0** | **HOLD** | não |
| D2 | DR-D | convert feliz + order ledger | accept **200**; CPI **200** `cs_test_a1usngQs…`; GET settle unpaid | order `7ef2d016-…` `reserva_pendente`; res **accepted** ≠converted | **HOLD** | não |

DR-A: 4 · DR-B: 3 · DR-C: 5 · DR-D: 2 · **total 14**.

`classe_nova=SIM`: A1 (coerção `"1e2"`/`[2]`), A2 (tip_id em live válida), A3 (tip∥end_live), B1 (share sem rifa), B3 (forge/double), C1 (pending→order), C2 (convert∥convert + hold), C3 (accept∥CPI) → **7** (≥3).  
Races: A3, C2, C3, D1 → **4** (≥3: accept∥CPI, convert∥convert, tip∥unpublish).

Efeito BD obrigatório: **sim** — D1 tip row pending + `cs_test`; B2 tickets 1→2; D2 order ledger `reserva_pendente`. Captura 4242 gorjeta: **SKIP** (sem `sk_test_` local).

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

Nenhum. `findings: []`. P0=0 P1=0 P2=0 P3=0.

A1 coerção JS `Number("1e2")`→ Session 100 € e `Number([2])`→ 2 €: unpaid, teto 500 €, Δwallet 0 — **não** contar (HOLD classe_nova, não P3).

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| FOMO / welcome / buyer refund 403 | **não corridos** (anti-atrofia; FOMO 0 linhas) |
| Tip mid-unpublish unpaid clássico sequencial | **não** — D1 é race + settle unpaid |
| A1 0/-1/0.5/501 | 400; sci/arr Session pending Δ=0 |
| A2/A4 seller≠owner + tip_id | 400 |
| A3 tip∥end | 400 broadcasting Δ=0 |
| B1 sem rifa | `raffle_not_found` |
| B3 forge | `not_allowed` + RLS; 1 winner |
| C* RPC convert JWT | 403 function denied (só Edge/service) |
| C4 PATCH converted | 403 `convert_requires_paid_order` |
| C5 2.º accept | 400 `qty_exceeds_stock` |
| C2 dual CPI | insert order `order_hold_exceeds_stock` com hold aceite |
| D1 settle unpaid | texto unpaid; pending |
| Coptic / charset | não corridos |

Residual clássico na tabela (A4 seller≠owner já HOLD noutros lotes) = 1/14 ≪ 40%. **ATROFIA: NÃO.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| DR1 tip auth | SIM A1/A2/A4 | não |
| DR2 rifa | SIM B1/B2/B3 | não |
| DR3 convert | SIM C1/C4/D2 | não |
| DR4 race | SIM A3/C2/C3/D1 | não |
| DR5 stock | SIM C5 + C2 hold | não |
| DR6 unpublish/end | SIM A3/C4/D1 | não |
| DR7 Edge | SIM D1 Session + A* tip Edge | não |

Lentes **7/7**.

--------------------------------------------------
## INVARIANTES
--------------------------------------------------

Tip amount/`tip_id` autoridade servidor (400 hostil / client tip_id). Unpaid não credita (pending Δ=0). Seller≠owner 400. Tips só enquanto broadcasting. Rifa: sem rifa ≠ prémio; share com rifa +1 ticket; draw só seller; insert winners RLS; double draw = 1 winner. Convert JWT autenticado **403** function denied; PATCH converted **403** `convert_requires_paid_order`. Pending ≠ converted. Hold aceite qty=1 bloqueia 2.º accept (`qty_exceeds_stock`) e insert order (`order_hold_exceeds_stock`). CPI hitch marketplace **400** Checkout blocked. Order ledger unpaid permanece `reserva_pendente`.

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_dr_20260906T1708/pass1.dart` + `pass1.json`
- `tool/redteam_blind_dr_20260906T1708/pass2.dart` + `pass2.json` (BD reservas sem coluna inexistente; A2 tip_id; C2/C3/C5 status)
- `tool/redteam_blind_dr_20260906T1708/cleanup.dart` — 21 lives ended, 2 rifas cancelled, hub S1 restored

**NÃO CORRIGIR.**

```
AUDITOR: REDTEAM_BLIND_DR_TIP_RAFFLE_POS_DHDM_v1
probes_na_tabela: 14 · classes_novas: 7
VEREDICTO: PASS_CEGO_SATURADO
```

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
