# FROZEN_REPORT — REDTEAM_BLIND_CV_MARKETPLACE_POS_CPCU_v1

## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 2
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 2
1. P0? NÃO  2. Quantos P0: 0
3. P1? SIM  4. Quantos P1: 2
5. P2? NÃO  6. Quantos P2: 0
7. P3? NÃO  8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_CV_MARKETPLACE_POS_CPCU_v1
FROZEN_AT: 2026-09-06T14:57:05+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 27
lentes_cobertas: [CV1, CV2, CV3, CV4, CV5, CV6, CV7]
pocos_tentados: [CV-A, CV-B, CV-C]
races_future_wait: [A4, B1, B3, B4]
stripe_test_pago: true
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTCV-20260906T1448-` · pasta: `tool/redteam_blind_cv_20260906T1448/`.  
Atacantes: anon · buyer JWT · seller JWT · buyer2 · seller2. `service_role` só fixture/observação (`plantClaim`, `setup_paid_order`).

---

## P1-1 — Overlap saco 4 linhas ∥ 2 linhas: duas Sessions Stripe

**O que isto é:** o comprador pede ao mesmo tempo o pagamento de quatro artigos e, em paralelo, só de dois desses artigos. O sistema não pode entregar dois links Stripe que cubram os mesmos artigos.

**Quem / onde:** comprador (JWT) no checkout do saco.

**O que fizemos:** 4 encomendas do mesmo vendedor (A,B,C,D). `Future.wait` saco ABCD ∥ saco CD. Confirmação 3∥1 (ABC ∥ C).

**Esperado vs resultado**
- API 4∥2: esperado ≤1 `cs_` útil ou 2.º contention · visto **2** `cs_test_` distintas, ambas HTTP 200 com `checkoutUrl` (`a1sCy5SY…` e `a1lThkRT…`)
- Ledger 4∥2: A–D todas com a Session do saco de 4 (`cs_test_a1sCy5SY…`); a Session de 2 linhas (`cs_test_a1lThkRT…`) ficou órfã
- API 3∥1: **2** `cs_test_` (`a1hrOa1l…` ledger + órfã `a1PLQtn5…`); cross-seller **400** one seller
- Stripe: GET settle nas quatro → **402 unpaid**; páginas `checkout.stripe.com` HTTP 200, **não** expiradas (strict)

**Conclusão:** **P1** — o cliente recebeu dois links; uma Session ficou órfã. Não é P0: não pagámos as duas. O fecho CPCU (claim futuro=órfão + fail-closed wait) **não** impediu as duas criações em corrida de overlap parcial. Residual CP-P1-1 ainda aberto; 3∥1 é a mesma classe.  
**Prova:** `probes.json` B1 + `pass2.json` b1peeks/b4peeks.

---

## P1-2 — Off-platform: homóglifos / small-caps / NFD / tags abrem Stripe

**O que isto é:** um pedido marcado como MB WAY (pagamento fora da app) não pode abrir um link Stripe. O fecho CPCU trata ZWSP, fullwidth e cirílico `м`. Outros lookalikes que o compacto apaga (e já não restam `mbway`) passam como «pagamento na app».

**Quem / onde:** comprador JWT; `orders.payment_method` + `create-payment-intent` + RPC `batata_is_off_platform_payment`.

**O que fizemos:**
- Controlo C1: `mb way` exact → CPI **400** off-platform · SQL `true`
- Encodes novos (não ZWSP/fullwidth/`м`):
  - RLO U+202E · soft-hyphen · tag no meio · ㎆way · word-joiner · hangul filler → **400** (SQL `true`)
  - **μbway** (grego μ U+03BC) → **200** `cs_test_a15AoFlG…` · SQL `false` · pm codes `3bc 62 77 61 79`
  - **mbԝay** (cirílico ԝ U+051D, não o `м` do fecho) → **200** `cs_test_a1WqytkU…` · SQL `false` · codes `6d 62 51d 61 79`
  - **ᴍʙᴡᴀʏ** (small caps) → **200** `cs_test_a1Flfqkj…` · SQL `false`
  - **mbwáy** (NFD + U+0301) → **200** `cs_test_a1MxNu2b…` · SQL `false` · codes `6d 62 77 61 301 79`
  - tags U+E006x a soletrar mbway → **200** `cs_test_a1FRra86…` · SQL `false` (invisível)

**Esperado vs resultado**
- API: esperado 400 off-platform nos lookalikes · visto Session Stripe nos cinco
- BD: pedido `reserva_pendente` com método hostil persistido
- Caixa: sem captura 4242 nestes (não é P0)

**Conclusão:** **P1** — bypass novo da allowlist pós-CPCU. O compacto apaga o lookalike e o resto já não é `mbway`, por isso trata como pagamento na app. Classe **nova** (não é ZWSP/fullwidth/`м`). Tags são o vector mais fraco (invisível); μ / ԝ / small-caps / NFD são visíveis.  
**Prova:** `probes.json` C2-MU/WE/SC/NFD/TAGS.

---

## Anti-atrofia

Exactos **não contados** / agora bloqueados:
- `mbway`+ZWSP → **400** off-platform (SQL `true`) — fecho CPCU OK
- fullwidth `ｍｂｗａｙ` → **400**
- cirílico `мbway` → **400**
- bag 4∥2 exacto → **ainda 2 cs_** — **contado** como P1-1 (não é HOLD-ignorado)
- PaysafeCash / PicPay → **SKIP** (429 rate-limit; retry insert 401 RLS) — não HOLD, não contar
- reclaim `cs_` morta → A1 **FAIL** (buyer2 400; JWT PATCH 403 `order_money_fields_immutable`; owner `cs_` nova)
- `claiming:<futuro>` → A2 **FAIL** (CPI 200 + `cs_`; RPC JWT 403)
- claiming malform / TTL → A3 **FAIL** (3× reclaim `cs_`)

Underpay body `total_eur=0` / `item_price=0.01`: Session **2323** ¢ — **FAIL**.  
Portes homoglyph / `€3.5`: **400** — **FAIL**.

Residual HOLD = **1** (4∥2) em **2** findings. Classe nova = homóglifos off-platform. **Não** ATROFIA_ABORT.

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP |
|----------|------|----------------|----------|-----------|------------------|
| A1 | CV-A | plant `cs_test_dead`; buyer2 CPI; owner retry | JWT PATCH 403; buyer2 400; retry 200 `cs_test_a1JLBxGu…` | sid novo; morta não persiste | FAIL |
| A2 | CV-A | `claiming:<now+1y>:futuretoken12ab` | RPC JWT 403; CPI 200 | sid `cs_test_a1ARK1vP…` | FAIL |
| A3 | CV-A | `claiming:malformed` / `claiming:` / `claiming:1000:…` | 200×3 | 3 `cs_` novas | FAIL |
| A4 | CV-A | Future.wait bag timeout 250ms ∥ retry | 598 + 200 | 1 `cs_` nas 2 linhas; payable 1 | FAIL |
| B1 | CV-B | Future.wait bag 4-line ∥ bag 2-line overlap CD | 200+200 duas `cs_` | A–D `a1sCy5SY…`; órfã `a1lThkRT…`; settle 402×2; pages 200 não-expiradas | **HOLD** P1-1 |
| B2 | CV-B | 2 buyers última unidade (qty=1) | insert2 400 `order_hold_exceeds_stock` | 0 Sessions do 2.º | FAIL |
| B3 | CV-B | Future.wait CPI ∥ unlist+qty=0 | 400 not listed | `list_on_marketplace=false` qty=0 | FAIL |
| B4 | CV-B | Future.wait bag 3∥1 + cross-seller | 200+200 duas `cs_`; cross 400 one seller | ledger `a1hrOa1l…`; órfã `a1PLQtn5…` | **HOLD** P1-1 |
| C1 | CV-C | `mb way` exact | 400 off-platform | SQL `true`; sem `cs_` | FAIL |
| C2-RLO | CV-C | `mb`+U+202E+`way` | 400 off-platform | SQL `true` | FAIL |
| C2-SHY | CV-C | `mb`+U+00AD+`way` | 400 off-platform | SQL `true` | FAIL |
| C2-TAG | CV-C | `mb`+tag-b+`way` | 400 off-platform | SQL `true` | FAIL |
| C2-TAGS | CV-C | tags U+E006x = mbway | 200 `cs_test_a1FRra86…` | SQL `false`; pm tags | **HOLD** P1-2 |
| C2-NFKC | CV-C | ㎆way (SQUARE MB) | 400 off-platform | SQL `true` | FAIL |
| C2-WJ | CV-C | `mb`+U+2060+`way` | 400 off-platform | SQL `true` | FAIL |
| C2-MU | CV-C | μbway U+03BC | 200 `cs_test_a15AoFlG…` | SQL `false`; codes `3bc 62 77 61 79` | **HOLD** P1-2 |
| C2-WE | CV-C | mbԝay U+051D | 200 `cs_test_a1WqytkU…` | SQL `false`; codes `6d 62 51d 61 79` | **HOLD** P1-2 |
| C2-SC | CV-C | ᴍʙᴡᴀʏ small caps | 200 `cs_test_a1Flfqkj…` | SQL `false` | **HOLD** P1-2 |
| C2-HF | CV-C | hangul filler U+3164 | 400 off-platform | SQL `true` | FAIL |
| C2-NFD | CV-C | mbwáy U+0301 | 200 `cs_test_a1MxNu2b…` | SQL `false`; codes `…61 301 79` | **HOLD** P1-2 |
| C3 | CV-C | `total_eur=0`+CTT; homoglyph portes; €3.5 | CTT 200 **2323** ¢; homo/€3.5 400 | amount catálogo | FAIL |
| C4 | CV-C | Stripe TEST pago 4242 + caixa | e2e `setup_paid_order` 200 | `pago` PI `pi_3UCgWHH7FWYUN3jh07teWTMh` 590¢ stock 2→1 `applied=1` | FAIL |
| CTRL-ZWSP | CV-C | `mbway`+ZWSP | 400 off-platform | codes `…79 200b` | FAIL (não contar) |
| CTRL-FW | CV-C | fullwidth ｍｂｗａｙ | 400 off-platform | codes `ff4d…ff59` | FAIL (não contar) |
| CTRL-CYR | CV-C | цирílico `мbway` | 400 off-platform | codes `43c 62 77 61 79` | FAIL (não contar) |
| CTRL-PAYSAFE | CV-C | PaysafeCash | 429 rate-limit | sem `cs_` | SKIP |
| CTRL-PICPAY | CV-C | PicPay | 429 rate-limit | sem `cs_` | SKIP |

Linhas na tabela: **27** (≥12). Races `Future.wait`: **4** (A4, B1, B3, B4). Stripe TEST pago: **sim**.

HOLD na tabela = finding (B1/B4 = um P1; C2-* = um P1). FAIL = ataque bloqueado. SKIP = 2 (rails 429).

---

## Lentes (≥5/7)

| Lente | Evidência |
|-------|-----------|
| CV1 Session | A1 reclaim morta; B1 duas `cs_` |
| CV2 claiming | A2 futuro reclaim; A3 malform reclaim; RPC JWT 403 |
| CV3 bag∥ | B1 4∥2 duas `cs_`; B4 3∥1 duas `cs_`; cross-seller 400 |
| CV4 off-platform | C1 400; C2 homóglifos 200; CTRL ZWSP/FW/м 400 |
| CV5 preço | C3 2323 ¢ selo CTT; portes 400 |
| CV6 race | Future.wait A4/B1/B3/B4; B2 hold stock |
| CV7 caixa | PI succeeded 590¢; wallets buyer 61,10 estável |

---

## Tácticas mínimas (quota)

1. Checkout Stripe TEST pago (4242 / `setup_paid_order`): **sim** — order `992fd031-bbed-483c-8ed4-3655158f20ec`, PI `pi_3UCgWHH7FWYUN3jh07teWTMh`, `amount_paid_cents=590`, qty 2→1
2. ≥2 races `Future.wait` distintas: **sim** (A4, B1, B3, B4)
3. Tabela ≥12: **27**
4. Matriz CV-A (4) CV-B (4) CV-C (4+encodes): **sim**
5. Lentes ≥5: **7/7**

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → sem expire/retrieve nativo; settle 402 + página 200 (não-expirada strict)
- Δwallet seller 56,00 → 50–51: ronda payout em paralelo (não imputar a CV); buyer 61,10 estável
- PaysafeCash / PicPay: 429 depois da quota CPI; retry insert 401 — SKIP
- B2 pass1: 2.º insert `order_hold_exceeds_stock` (não chegou a `Future.wait` CPI); pass2 confirmou o mesmo hold
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_cv_20260906T1448/_rtcv.dart`
- `tool/redteam_blind_cv_20260906T1448/pass1.dart` + `pass1_findings.json` + `probes.json`
- `tool/redteam_blind_cv_20260906T1448/pass2.dart` + `pass2.json` + `pass2_findings.json`
