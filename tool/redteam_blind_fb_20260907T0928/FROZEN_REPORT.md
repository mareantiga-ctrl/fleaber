# FROZEN_REPORT — REDTEAM_BLIND_FB_STOCK_MONEY_SMOKE_PRE_P4_v1

## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 0

1. P0 dinheiro irreversível? NÃO
2. Quantos P0: 0
3. P1 caminho explorável? NÃO
4. Quantos P1: 0
5. P2 hygiene? NÃO
6. Quantos P2: 0
7. P3 baixo risco? NÃO
8. Quantos P3: 0

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0

```
AUDITOR: REDTEAM_BLIND_FB_STOCK_MONEY_SMOKE_PRE_P4_v1
FROZEN_AT: 2026-09-07T09:36:00+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 12
classes_novas: 8
races: 1
stripe_test_pago: true
oversell: false
double_credit: false
VEREDICTO: PASS_CEGO_SATURADO
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTFB-20260907T0928-` · pasta: `tool/redteam_blind_fb_20260907T0928/`.  
Atacante CPI: comprador fresco `d2dac1c6-…` (fb1) + B2 `2bdb17c6-…`. Seller `980f4fa1-…` Hub publicado. `service_role` só fixture/observação/release. Sem `sk_test_` local.

Missão: stock e Hub batem com o que o Stripe liquidou; dois compradores no mesmo SKU qty=1 não vendem 2.

**Resposta:** missão fechada. 2.º insert qty=1 = `order_hold_exceeds_stock`. Race 0 ms = 1 hold. Após pago qty=1: `qty=0` `is_sold` Hub buyer+anon n=0. Leftover 2→1 Hub n=1 nos dois sítios. Underpay `total_eur=0` → quote **1325** ¢. Wallet Δ pago=0; após release mão **+5,00** (1 txn `venda`). Sem oversell. Sem double credit.

---

## Anti-atrofia

Exactos **corridos ≤1 cada, não contar como classe nova**:
- buyer refund 403 — D1 `403` «Sem permissão.»
- settle unpaid 402 — D2 pass2 `402` «Pagamento ainda não confirmado»

Não corrido / não contar: bag∥avulso (lente FA/GATE).

HOLD na tabela = **0/12 = 0%** < 40%. **Não** ATROFIA_ABORT.  
classe_nova=SIM: A2, A3, A4, B1, B3, C1, C2, C3 (**8** ≥3).

---

## FINDINGS (contáveis)

Nenhum. `findings: []`.

---

## TABELA DE PROVAS (12)

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|-----------|------------------|--------------|
| A1 | FB-A | 2 buyers SKU qty=1 insert sequencial | 201 + **400** `order_hold_exceeds_stock` | o2=null | FAIL | NÃO |
| A2 | FB-A | Future.wait reserve∥reserve 0 ms qty=1 | 400+201 hold | claims=**1** qty=1 | FAIL | SIM |
| A3 | FB-A | após pago qty=1 qty↓ is_sold Hub | e2e 200 PI `pi_3UCxzpH7…` | `pago` qty=**0** sold Hub 0/0 applied=1 | FAIL | SIM |
| A4 | FB-A | 2.º buyer CPI mesma unit paga | insert **400** hold (sem CPI) | qty=0 sold | FAIL | SIM |
| B1 | FB-B | Hub buyer+anon vs order+products pós-pago | Hub **200** n=1 + n=1 | `pago` qty=1 sold=false PI `pi_3UCxztH7…` 4 sítios | FAIL | SIM |
| B2 | FB-B | leftover qty 2→1 visível Hub | Hub n=1 | qty **2→1** | FAIL | NÃO |
| B3 | FB-B | bag 4 lines todas pago ou nenhuma | CPI **200** `cs_test_a1aPOA1…`; captura hosted falhou (sem `sk_test_`); settle **402** | 4× `reserva_pendente` (nenhuma pago; sem meia) | FAIL | SIM |
| C1 | FB-C | underpay amount=0 total_eur=0 | CPI **200** | quoted=**1325** stripeAmt=**1325** client_won=false | FAIL | SIM |
| C2 | FB-C | seller wallet antes/depois 1 pago + release | release **200 true** | Δpago=**0** Δrel=**+5,00** 21→26 1 txn `venda` | FAIL | SIM |
| C3 | FB-C | 2× settle mesma session | e2e replay session sem PI; fallback 2× GET **402**+**402** | sid `cs_test_a1rZqXi…` 1 efeito (nenhum) | FAIL | SIM |
| D1 | FB-D | buyer refund-order | **403** Sem permissão | oid leftover `2a112865-…` | FAIL | NÃO |
| D2 | FB-D | settle unpaid (pass2 buyer fresco) | CPI 200 · GET **402** | credited=false `cs_test_a1ShPOn…` | FAIL | NÃO |

FB-A: 4 · FB-B: 3 · FB-C: 3 · FB-D: 2 · **total 12**.

Apoio (não contam na quota):
- **B3e2e** setup_paid_bag 2 linhas: ambas `pago`, PI `pi_3UCy2ZH7…` 1115 ¢, paid 335+780, sem meia liquidação.
- **C3-paid** 2× `fase2_e2e_settle` no PI leftover: **401** `service_role required` ×2; qty=1 estável; Δwallet=0; status `concluido`.

---

## DESCARTADOS / HOLD (não contar)

| Poço | Resultado |
|------|-----------|
| A1 2 insert qty=1 | 1× 201 + 1× 400 hold |
| A2 race 0 ms | 1 hold; qty listed=1 |
| A3/A4 pago qty=1 | Hub 0; 2.º insert 400 |
| B1/B2 leftover | qty 1 Hub buyer+anon 1; PI `pi_3UCxztH7FWYUN3jh0I9oohI0` |
| B3 4-line hosted | captura 4242 falhou sem `sk_test_` (pp_init 404); 0/4 pago |
| B3e2e | 2 linhas ambas pago (lacuna: não são 3–5) |
| C1 underpay | servidor 1325 vs body 0 |
| C2 wallet | crédito só no release; 1 venda +5,00 |
| C3 GET×2 unpaid | 402+402 |
| C3-paid | 401×2 sem 2.º efeito |
| D1/D2 residual | 403 / 402 |

**Lacuna honesta:** saco **3–5 linhas** Stripe hosted **não capturado** (sem `sk_test_` local; mesmo padrão GATE). Atomicidade **paga** vista em e2e 2 linhas; 4 linhas abertas ficaram **todas** `reserva_pendente` (não meia liquidação). Não é finding.

---

## LENTES

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| FB-A stock 2 buyers | SIM A1–A4 | não |
| FB-B Hub / composição | SIM B1–B3 | não |
| FB-C dinheiro curto | SIM C1–C3 | não |
| FB-D anti-atrofia | SIM D1–D2 | não |

Lentes **4/4**. Bag∥avulso **não** martelado.

---

## INVARIANTES

- qty=1 → ≤1 hold/venda válida
- Hub público = leftover / sold-out
- underpay não vence catálogo
- 1 pago → ≤1 crédito wallet no release
- 2× settle → ≤1 efeito
- buyer não reembolsa
- GET settle unpaid não liquida

Todos **intactos** nesta corrida.

---

## CHECKLIST OURO

1. Tabela ≥10 — SIM (12)
2. ≥1 2 buyers qty=1 2.º fail — SIM A1+A2
3. ≥1 pago 4242 + Hub leftover — SIM B1/B2 (`pi_3UCxztH7…` qty 2→1 Hub n=1)
4. ≥1 underpay servidor manda — SIM C1 1325
5. ≥1 wallet Δ seller — SIM C2 +5,00 após release (0 no instante do pago)
6. Oversell / double credit = P0 — NÃO ocorreram
7. ≥3 classe_nova — SIM (8)

```
AUDITOR: REDTEAM_BLIND_FB_STOCK_MONEY_SMOKE_PRE_P4_v1
VEREDICTO: PASS_CEGO_SATURADO
```

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
