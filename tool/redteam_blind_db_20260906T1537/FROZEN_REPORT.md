# FROZEN_REPORT — REDTEAM_BLIND_DB_MARKETPLACE_POS_CVDA_v1

## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 2
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 2
1. P0 dinheiro irreversível? NÃO
2. Quantos P0: 0
3. P1 caminho explorável? SIM
4. Quantos P1: 2
5. P2 hygiene? NÃO
6. Quantos P2: 0
7. P3 baixo risco? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_DB_MARKETPLACE_POS_CVDA_v1
FROZEN_AT: 2026-09-06T15:42:00+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 25
lentes_cobertas: [DB1, DB2, DB3, DB4, DB5, DB6, DB7]
pocos_tentados: [DB-A, DB-B, DB-C]
races_future_wait: [A3, B1, B2, B4, B5]
stripe_test_pago: true
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTDB-20260906T1537-` · pasta: `tool/redteam_blind_db_20260906T1537/`.  
Atacantes: anon · buyer JWT · seller JWT · buyer2 · seller2. `service_role` só fixture/observação (`plantClaim`, `setup_paid_order`).

---

## P1-1 — Overlap saco 4∥2 / 3∥1 / bag∥single: duas Sessions Stripe

**O que isto é:** o comprador pede ao mesmo tempo o pagamento de quatro artigos e, em paralelo, só de dois desses artigos. O cadeado CVDA (lock por comprador) tinha de entregar no máximo um link Stripe útil, ou recusar o segundo. O mesmo furo aparece no saco de três∥um e no saco∥pagamento avulso.

**Quem / onde:** comprador (JWT) no checkout do saco.

**O que fizemos:** 4 encomendas do mesmo vendedor. `Future.wait` saco ABCD ∥ saco CD. Confirmação 3∥1 (ABC ∥ C). Residual: saco de 4 ∥ pagamento avulso da linha C. Repeat pass2 do 4∥2.

**Esperado vs resultado**
- API 4∥2: esperado ≤1 `cs_` útil ou 2.º contention · visto **2** `cs_test_` distintas, ambas HTTP 200 (`a1J8bKh2…` e `a12JE4xa…`); pass2 repeat `a1SfuCwY…` + `a1MSRx4v…`
- Ledger 4∥2: A–D todas com a Session do saco de 4; a Session de 2 linhas ficou órfã (pass1 e pass2)
- API 3∥1: **2** `cs_test_` (`a1SDTJ36…` ledger + órfã `a1zSy0pY…`)
- API bag∥single: **2** `cs_test_` (`a1RGXgZH…` + `a1ctgmiG…`)
- Stripe: GET settle nas Sessions → **402 unpaid**; páginas `checkout.stripe.com` HTTP 200 (pass2). Sem `sk_test_` local → sem expire nativo. **Não pagámos as duas.**

**Conclusão:** **P1** — o cliente recebeu dois links; uma Session ficou órfã. Não é P0: não pagámos as duas. O fecho CVDA (advisory lock por buyer) **não** impediu as duas criações em corrida de overlap parcial. 3∥1 e bag∥single são a mesma classe.  
**Prova:** `probes.json` B1/B2/B5 + `pass2.json` b1repro/b1peeks.

---

## P1-2 — Off-platform: confusables novos (não exactos CV) abrem Stripe

**O que isto é:** um pedido marcado como MB WAY (pagamento fora da app) não pode abrir um link Stripe. O fold CVDA trata μ / ԝ / small-caps / NFD. Outros lookalikes de letra que o compacto **não** reduz a `mbway` passam como «pagamento na app».

**Quem / onde:** comprador JWT; `orders.payment_method` + `create-payment-intent` + RPC `batata_is_off_platform_payment`.

**O que fizemos:**
- Controlo C1: `mb way` exact → CPI **400** off-platform · SQL `true`
- Controlo C2 (não contar): **μbway** e **ᴍʙᴡᴀʏ** → **400** · SQL `true` (fold CVDA OK)
- Encodes novos (não μ/ԝ/small-caps/NFD/tags):
  - **mbωay** (grego ω U+03C9) → **200** `cs_test_a1os7NQr…` · SQL `false` · codes `6d 62 3c9 61 79`
  - **ⲙbway** (copta ⲙ U+2C99) → **200** `cs_test_a1G7vByM…` · SQL `false` · codes `2c99 62 77 61 79`
  - **mɓway** (b with hook U+0253) → **200** `cs_test_a1kCyr0Y…` · SQL `false`
  - **𝗺𝗯𝘄𝗮𝘆** (math sans-serif bold) → **200** `cs_test_a1UPxJEB…` · SQL `false` · codes `1d5dc…`
  - **mbwɑy** (latin alpha U+0251) → **200** `cs_test_a1RIXjnN…` · SQL `false`
  - **mβway** (grego β U+03B2) → **200** `cs_test_a1zKe0jZ…` · SQL `false`
  - ⅿbway (roman) · ⓜⓑⓦⓐⓨ · mb+MVS+way → **400** (SQL `true`)
- Pass2: omega / math / coptic repetidos → outra vez 200 + SQL `false`

**Esperado vs resultado**
- API: esperado 400 off-platform nos lookalikes novos · visto Session Stripe nos seis
- BD: pedido `reserva_pendente` com método hostil persistido
- Caixa: sem captura 4242 nestes (não é P0)

**Conclusão:** **P1** — bypass novo da allowlist pós-CVDA. Letras que o fold não mapeia sobrevivem no compacto e deixam de ser `mbway`. Classe **nova** (não é μ/ԝ/small-caps/NFD).  
**Prova:** `probes.json` C3-* + `pass2.json` omega/math/copt.

---

## Anti-atrofia

Exactos **não contados** / agora bloqueados:
- `mb way` exact → **400** — C1 FAIL
- μbway / ᴍʙᴡᴀʏ / mbwáy (NFD) / mbway+ZWSP → **400** — fold CVDA OK (não contar)
- bag 4∥2 exacto → **ainda 2 cs_** — **contado** como P1-1 (não é o caso «≤1 cs_»)
- PaysafeCash → **200** `cs_test_a1Lxwq0x…` — HOLD **não contar** (rails residual)
- reclaim `cs_` morta → A1 **FAIL** (buyer2 400; JWT PATCH 403 `order_money_fields_immutable`; owner `cs_` nova)
- `claiming:<futuro>` → A2 **FAIL** (CPI 200 + `cs_` coerente no ledger; RPC JWT 403)
- timeout 250ms ∥ retry → A3 **FAIL** (1 `cs_` útil)

Underpay body `total_eur=0` / `item_price=0.01`: Session **2323** ¢ — **FAIL**.  
Portes homoglyph / `€3.5`: **400** — **FAIL**.

Residual HOLD não contado = **1** (PaysafeCash). Findings contados = **2**. Classe nova = confusables fora do mapa CVDA. **Não** ATROFIA_ABORT.

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP |
|----------|------|----------------|----------|-----------|------------------|
| A1 | DB-A | plant `cs_test_dead`; buyer2 CPI; owner retry | JWT PATCH 403; buyer2 400; retry 200 `cs_test_a1x3iSFz…` | sid novo; morta não persiste | FAIL |
| A2 | DB-A | `claiming:<now+1y>:futuretoken12ab` | RPC JWT 403; CPI 200 | sid `cs_test_a1oHKEfx…` coerente | FAIL |
| A3 | DB-A | Future.wait bag timeout 250ms ∥ retry | 598 + 200 | 1 `cs_test_a1YzOJbN…` nas 2 linhas; payable 1 | FAIL |
| B1 | DB-B | Future.wait bag 4-line ∥ bag 2-line overlap CD | 200+200 duas `cs_` | A–D `a1J8bKh2…`; órfã `a12JE4xa…`; settle 402×2; pass2 repeat 2 `cs_` | **HOLD** P1-1 |
| B2 | DB-B | Future.wait bag 3∥1 overlap | 200+200 duas `cs_` | ledger `a1SDTJ36…`; órfã `a1zSy0pY…` | **HOLD** P1-1 |
| B3 | DB-B | 2 buyers última unidade (qty=1) | insert2 400 `order_hold_exceeds_stock` | 0 Sessions do 2.º | FAIL |
| B4 | DB-B | Future.wait CPI ∥ unlist+qty=0; bag cross-seller | 400 not listed; cross 400 one seller | `list_on_marketplace=false` qty=0 | FAIL |
| B5 | DB-B | Future.wait bag 4 ∥ CPI single linha C | 200+200 duas `cs_` | `a1RGXgZH…` + `a1ctgmiG…`; settle 402×2 | **HOLD** P1-1 |
| C1 | DB-C | `mb way` exact | 400 off-platform | SQL `true`; sem `cs_` | FAIL |
| C2-MU | DB-C | μbway U+03BC (controlo fold) | 400 off-platform | SQL `true`; codes `3bc 62 77 61 79` | FAIL (não contar) |
| C2-SC | DB-C | ᴍʙᴡᴀʏ small caps (controlo) | 400 off-platform | SQL `true` | FAIL (não contar) |
| C3-OMEGA | DB-C | mbωay U+03C9 | 200 `cs_test_a1os7NQr…` | SQL `false`; codes `6d 62 3c9 61 79` | **HOLD** P1-2 |
| C3-COPT | DB-C | ⲙbway U+2C99 | 200 `cs_test_a1G7vByM…` | SQL `false`; codes `2c99…` | **HOLD** P1-2 |
| C3-HOOK | DB-C | mɓway U+0253 | 200 `cs_test_a1kCyr0Y…` | SQL `false` | **HOLD** P1-2 |
| C3-ROMAN | DB-C | ⅿbway U+217F | 400 off-platform | SQL `true` | FAIL |
| C3-MATH | DB-C | 𝗺𝗯𝘄𝗮𝘆 math bold | 200 `cs_test_a1UPxJEB…` | SQL `false`; codes `1d5dc…` | **HOLD** P1-2 |
| C3-LATN | DB-C | mbwɑy U+0251 | 200 `cs_test_a1RIXjnN…` | SQL `false` | **HOLD** P1-2 |
| C3-CIRC | DB-C | ⓜⓑⓦⓐⓨ circled | 400 off-platform | SQL `true` | FAIL |
| C3-MVS | DB-C | mb+U+180E+way | 400 off-platform | SQL `true` | FAIL |
| C3-BETA | DB-C | mβway U+03B2 | 200 `cs_test_a1zKe0jZ…` | SQL `false` | **HOLD** P1-2 |
| C4 | DB-C | `total_eur=0`+CTT; homoglyph portes; €3.5 | CTT 200 **2323** ¢; homo/€3.5 400 | amount catálogo | FAIL |
| C5 | DB-C | Stripe TEST pago 4242 + caixa | e2e `setup_paid_order` 200 | `pago` PI `pi_3UChHxH7FWYUN3jh1bh32X3n` 590¢ stock 2→1 `applied=1` | FAIL |
| CTRL-NFD | DB-C | mbwáy U+0301 | 400 off-platform | codes `…61 301 79` | FAIL (não contar) |
| CTRL-ZWSP | DB-C | `mbway`+ZWSP | 400 off-platform | codes `…79 200b` | FAIL (não contar) |
| CTRL-PAYSAFE | DB-C | PaysafeCash | 200 `cs_test_a1Lxwq0x…` | SQL `false` | HOLD (não contar) |

Linhas na tabela: **25** (≥12). Races `Future.wait`: **5** (A3, B1, B2, B4, B5). Stripe TEST pago: **sim**.

HOLD na tabela = finding (B1/B2/B5 = um P1; C3-* abertos = um P1). FAIL = ataque bloqueado. SKIP = 0.

---

## Lentes (≥5/7)

| Lente | Evidência |
|-------|-----------|
| DB1 Session | A1 reclaim morta; B1 duas `cs_` |
| DB2 claiming | A2 futuro reclaim; RPC JWT 403 |
| DB3 bag∥ | B1 4∥2 duas `cs_`; B2 3∥1 duas `cs_`; B5 bag∥single; cross-seller 400 |
| DB4 off-platform | C1 400; C2 μ/SC 400; C3 homóglifos novos 200 |
| DB5 preço | C4 2323 ¢ selo CTT; portes 400 |
| DB6 race | Future.wait A3/B1/B2/B4/B5; B3 hold stock |
| DB7 caixa | PI succeeded 590¢; wallets buyer 61,10 estável |

---

## Tácticas mínimas (quota)

1. Checkout Stripe TEST pago (4242 / `setup_paid_order`): **sim** — order `328bd13e-6f16-44b2-8f62-b1f73a6bd30d`, PI `pi_3UChHxH7FWYUN3jh1bh32X3n`, `amount_paid_cents=590`, qty 2→1
2. ≥2 races `Future.wait` distintas: **sim** (A3, B1, B2, B4, B5)
3. Tabela ≥12: **25**
4. Matriz DB-A (3) DB-B (4+) DB-C (5+encodes): **sim**
5. Lentes ≥5: **7/7**

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → sem expire/retrieve nativo; settle 402 + página 200 (pass2 `expired_c` keyword no HTML das Sessions antigas — repro fresco 4∥2 ainda 2 `cs_` HTTP 200)
- Δwallet seller 49,00 → 39,00: não bate com o pago 5,90 € desta ronda (ronda payout em paralelo possível); buyer 61,10 estável — **não imputar** a DB
- B3: 2.º insert `order_hold_exceeds_stock` (não chegou a `Future.wait` CPI)
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_db_20260906T1537/_rtdb.dart`
- `tool/redteam_blind_db_20260906T1537/pass1.dart` + `pass1_findings.json` + `probes.json`
- `tool/redteam_blind_db_20260906T1537/pass2.dart` + `pass2.json`
