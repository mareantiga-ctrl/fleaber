# FROZEN_REPORT — REDTEAM_BLIND_DH_MARKETPLACE_POS_DBDG_v1

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
AUDITOR: REDTEAM_BLIND_DH_MARKETPLACE_POS_DBDG_v1
FROZEN_AT: 2026-09-06T16:25:00+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 31
lentes_cobertas: [DH1, DH2, DH3, DH4, DH5, DH6, DH7, DH8]
pocos_tentados: [DH-A, DH-B, DH-C, DH-D]
races_future_wait: [A3, A4, B1, B2, B3, B5]
stripe_test_pago: true
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTDH-20260906T1609-` · pasta: `tool/redteam_blind_dh_20260906T1609/`.  
Atacantes: anon · buyer JWT · seller JWT · buyer2 · seller2. `service_role` só fixture/observação (`plantClaim`, `setup_paid_order`, mutex peek).

---

## P1-1 — Overlap saco 4∥2 e bag∥single: duas Sessions Stripe

**O que isto é:** o comprador pede ao mesmo tempo o pagamento de quatro artigos e, em paralelo, só de dois desses artigos (ou o pagamento avulso de uma linha do mesmo saco). O mutex DBDG (cadeado por comprador + escrita `cs_` só com claim) tinha de entregar no máximo um link Stripe útil, ou recusar o segundo.

**Quem / onde:** comprador (JWT) no checkout do saco.

**O que fizemos:** 4 encomendas do mesmo vendedor. `Future.wait` saco ABCD ∥ saco CD. Confirmação pass2. Residual novo vs 3∥1: saco de 4 ∥ pagamento avulso da linha C (B3).

**Esperado vs resultado**
- API 4∥2: esperado ≤1 `cs_` útil ou 2.º contention · visto **2** `cs_test_` distintas, ambas HTTP 200 (`a1R88zSO…` + `a18p9u5e…`); pass2 `a14lLWK8…` + `a1CGZEoU…`
- Ledger 4∥2: A–D todas com a Session do saco de 4; a Session de 2 linhas ficou órfã (pass1 e pass2)
- API bag∥single: **2** `cs_test_` (`a1O7w2FR…` + `a1etVvW1…`); pass2 `a1xFpm3S…` + `a1rlCn8O…`; ledger nas 4 linhas = sid do saco; single órfã
- API 3∥1: **1** `cs_` (`a1x5IFNc…`) — este overlap ficou fechado
- Stripe: sem `sk_test_` local; settle 402 nas duas (pass1 `payable=2`). **Não pagámos as duas.**

**Conclusão:** **P1** — o cliente recebeu dois links; uma Session ficou órfã. Não é P0: não pagámos as duas. O mutex por buyer **não** impede duas criações em overlap parcial 4∥2 nem bag∥single. 3∥1 passou a ≤1 (fecho parcial).  
**Prova:** `probes.json` B1/B3 + `pass2.json`.

---

## P1-2 — Off-platform: compacto exacto — sufixo/prefixo ASCII abre Stripe

**O que isto é:** um pedido marcado como MB WAY / transferência (pagamento fora da app) não pode abrir um link Stripe. O fail-closed DBDG trata non-ASCII e o compacto exacto `mbway`/`transferencia`. Lixo ASCII à volta (`mb way x`, `xxmbway`, `via mb way`, `transferencia extra`) **não** casa na allowlist e o SQL devolve `false` → Stripe abre.

**Quem / onde:** comprador JWT; `orders.payment_method` + `create-payment-intent` + RPC `batata_is_off_platform_payment`.

**O que fizemos:**
- Controlo anti-atrofia (não contar): `mb way` exact → CPI **400** · SQL `true`; `mbωay` / `𝗺𝗯𝘄𝗮𝘆` → **400** (fold DBDG OK)
- Encodes **novos** (não omega/math/coptic):
  - **mb way x** → **200** `cs_test_a185b75e…` · SQL `false` · codes `6d 62 20 77 61 79 20 78` · persistido
  - **xxmbway** → **200** `cs_test_a1mOlpD1…` · SQL `false`
  - **via mb way** → **200** `cs_test_a1jzaFCM…` · SQL `false`
  - **transferencia extra** → **200** `cs_test_a101Q63n…` · SQL `false`
- Confirm: JWT persiste `mb way x` / `xxmbway` / `transferencia extra` no ledger (`confirm_c3.json`); retry CPI 429 rate-limit (não invalida o 200 do pass1)
- Rails ASCII novos bizum/pix/mbnet → 200 (mesma allowlist exacta; classe próxima de PaysafeCash — **não** somar finding extra)
- Fold-to-card (fullwidth/cirílico) e VS16 em `mbway` → **400**

**Esperado vs resultado**
- API: esperado 400 off-platform nos wraps de mbway/transfer · visto Session Stripe
- BD: `reserva_pendente` com método hostil persistido
- Caixa: sem captura 4242 nestes (não é P0)

**Conclusão:** **P1** — bypass novo da allowlist pós-DBDG. Não é homóglifo unicode (esses fecharam). É *exact-match* do compacto: um espaço e um `x` bastam.  
**Prova:** `probes.json` C3-SUFFIX/PREFIX/VIA/TRANSX + `confirm_c3.json`.

---

## Anti-atrofia

Exactos **não contados** / agora bloqueados:
- `mb way` exact → **400** — CTRL-MBWAY FAIL
- `mbωay` / `𝗺𝗯𝘄𝗮𝘆` → **400** — fold DBDG OK (não contar)
- bag 4∥2 → **ainda 2 cs_** — **contado** como P1-1 (não é o caso «≤1 cs_»)
- PaysafeCash → **200** `cs_test_a1m4YYEI…` — HOLD **não contar** (rails residual)
- reclaim `cs_` morta → A1 FAIL (buyer2 400; JWT PATCH 403; owner `cs_` nova)
- `claiming:<futuro>` / malform / TTL → A2 FAIL (CPI 200 + `cs_` coerente; RPC JWT 403)
- timeout 250ms ∥ retry → A3 FAIL (1 `cs_` útil)
- bags disjuntos mesmo buyer → A4 FAIL (2 `cs_` após serializar; JWT **não** lê mutex; documentado)
- `transferência` legítima → C4 **400**
- underpay `total_eur=0` → Session **2323** ¢ — FAIL
- C2 portes/coupon: PATCH shipping HTTP 200 **sem mutar** (`entrega em mão` igual no serviço); amount 2995 estável; coupon ignorado — FAIL (HOLD pass1 falso)

Residual HOLD não contado = **1** (PaysafeCash). Findings contados = **2**. Classe nova = compacto ASCII wrap (não unicode DB). **Não** ATROFIA_ABORT.

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP |
|----------|------|----------------|----------|-----------|------------------|
| A1 | DH-A | plant `cs_test_dead`; JWT PATCH cs_; buyer2 CPI; owner retry | JWT PATCH 403; buyer2 400; retry 200 `cs_test_a1DGxSMc…` | sid novo; morta não persiste | FAIL |
| A2 | DH-A | `claiming:<now+1y>:futuretoken12ab` | RPC JWT 403; CPI 200 | sid `cs_test_a1kG9MTE…` coerente | FAIL |
| A2-MALFORM | DH-A | `claiming:notanumber:malformtok12` | CPI 200 | sid `cs_test_a1poqhGV…` coerente | FAIL |
| A2-TTL | DH-A | `claiming:<now-120s>:expiredtoken12` | CPI 200 | sid `cs_test_a1ac20DF…` coerente | FAIL |
| A3 | DH-A | Future.wait bag timeout 250ms ∥ retry | 598 + 200 | 1 `cs_test_a1khIcxk…` nas 2 linhas | FAIL |
| A4 | DH-A | Future.wait 2 bags disjuntos mesmo buyer | 200+200 duas `cs_` | bags A/B sid distintos; JWT mutex sem GRANT | FAIL |
| B1 | DH-B | Future.wait bag 4-line ∥ bag 2-line overlap CD | 200+200 duas `cs_` | A–D `a1R88zSO…`; órfã `a18p9u5e…`; pass2 repeat 2 `cs_` | **HOLD** P1-1 |
| B2 | DH-B | Future.wait bag 3∥1 overlap | 1 `cs_test_a1x5IFNc…` | ≤1 útil | FAIL |
| B3 | DH-B | Future.wait bag 4 ∥ CPI single linha C | 200+200 duas `cs_` | ledger saco; single órfã; pass2 repeat 2 `cs_` | **HOLD** P1-1 |
| B4 | DH-B | 2 buyers última unidade (qty=1) | insert2 400 `order_hold_exceeds_stock` | 0 Sessions do 2.º | FAIL |
| B5 | DH-B | Future.wait CPI ∥ unlist+qty=0 | 400 not listed | `list_on_marketplace=false` qty=0 | FAIL |
| C1 | DH-C | `total_eur=0`+`item_price=0.01` SKU 18€ | 200 **2323** ¢ | amount catálogo | FAIL |
| C2 | DH-C | Session open → JWT PATCH shipping=ctt; coupon SAVE90 | PATCH 200; re-CPI/coupon 2995 | pass2: shipping **não** mudou (`entrega em mão`) | FAIL |
| C3-SUFFIX | DH-C | `mb way x` | 200 `cs_test_a185b75e…` | SQL `false`; persistido | **HOLD** P1-2 |
| C3-PREFIX | DH-C | `xxmbway` | 200 `cs_test_a1mOlpD1…` | SQL `false` | **HOLD** P1-2 |
| C3-VIA | DH-C | `via mb way` | 200 `cs_test_a1jzaFCM…` | SQL `false` | **HOLD** P1-2 |
| C3-TRANSX | DH-C | `transferencia extra` | 200 `cs_test_a101Q63n…` | SQL `false` | **HOLD** P1-2 |
| C3-FWCARD | DH-C | fullwidth `ｃard` | 400 off-platform | SQL `false`; CPI deny | FAIL |
| C3-CYRCARD | DH-C | cirílico `сard` | 400 off-platform | SQL `false`; CPI deny | FAIL |
| C3-BIZUM | DH-C | `bizum` | 200 `cs_test_a1hiSppl…` | SQL `false` | HOLD (rails, não somar) |
| C3-PIX | DH-C | `pix` | 200 `cs_test_a1m7foXD…` | SQL `false` | HOLD (rails, não somar) |
| C3-MBNET | DH-C | `mbnet` | 200 `cs_test_a1BbJ2lC…` | SQL `false` | HOLD (rails, não somar) |
| C3-VS | DH-C | `mbway`+VS16 | 400 off-platform | SQL `true` | FAIL |
| C4 | DH-C | `transferência` PT | 400 off-platform | SQL `true`; sem `cs_` | FAIL |
| C5 | DH-C | Stripe TEST pago 4242 + caixa | e2e `setup_paid_order` 200 | `pago` PI `pi_3UChozH7FWYUN3jh0xrEIhkx` 590¢ stock 2→1 `applied=1` | FAIL |
| CTRL-MBWAY | DH-C | `mb way` exact | 400 off-platform | SQL `true` | FAIL (não contar) |
| CTRL-OMEGA | DH-C | mbωay U+03C9 | 400 off-platform | SQL `true` | FAIL (não contar) |
| CTRL-MATH | DH-C | 𝗺𝗯𝘄𝗮𝘆 math bold | 400 off-platform | SQL `true` | FAIL (não contar) |
| CTRL-PAYSAFE | DH-C | PaysafeCash | 200 `cs_test_a1m4YYEI…` | SQL `false` | HOLD (não contar) |
| D1 | DH-D | bag 2 sellers | 400 one seller | sem `cs_` | FAIL |
| D2 | DH-D | JWT PATCH qty=99; CPI quantity=99 stock=1 | JWT 403; CPI 200 catálogo | quantity imutável | FAIL |

Linhas na tabela: **31** (≥16). Races `Future.wait`: **6** (A3, A4, B1, B2, B3, B5). Stripe TEST pago: **sim**.

HOLD na tabela = finding (B1/B3 = um P1; C3 wraps = um P1). FAIL = ataque bloqueado. SKIP = 0.  
C3-BIZUM/PIX/MBNET HOLD rails **não** entram no `quantos` (classe Paysafe). C2 FAIL após pass2.

---

## Lentes (≥6/8)

| Lente | Evidência |
|-------|-----------|
| DH1 Session | A1 reclaim morta; A2 futuro/malform/TTL |
| DH2 mutex | A4 bags disjuntos; JWT sem GRANT na tabela mutex |
| DH3 bag∥ | B1 4∥2 duas `cs_`; B3 bag∥single duas `cs_`; B2 3∥1 uma; D1 cross 400 |
| DH4 stock | B4 hold stock; B5 unlist 400; D2 qty 403 |
| DH5 preço | C1 2323 ¢; C2 amount estável 2995 |
| DH6 off-platform | C4 400; CTRL omega/math 400; C3 wraps 200 |
| DH7 race | Future.wait A3/A4/B1/B2/B3/B5 |
| DH8 caixa | PI succeeded 590¢; wallets buyer 61,10 estável |

---

## Tácticas mínimas (quota)

1. Checkout Stripe TEST pago (4242 / `setup_paid_order`): **sim** — order `9744eb1d-e2bd-455e-aa9e-a5d5ce83b8fd`, PI `pi_3UChozH7FWYUN3jh0xrEIhkx`, `amount_paid_cents=590`, qty 2→1
2. ≥3 races `Future.wait` distintas: **sim** (A3, A4, B1, B2, B3, B5)
3. Tabela ≥16: **31**
4. Matriz DH-A (4) DH-B (5) DH-C (5) DH-D (2): **sim**
5. Lentes ≥6/8: **8/8**

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → sem expire/retrieve nativo; settle 402
- Δwallet seller 37,00 → 35,00: não bate com o pago 5,90 € desta ronda (ronda payout em paralelo possível); buyer 61,10 estável — **não imputar** a DH
- Confirm C3 retry CPI **429** rate-limit após pass2; persistência do método hostil confirmada; abertura Stripe no pass1
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_dh_20260906T1609/_rtdh.dart`
- `tool/redteam_blind_dh_20260906T1609/pass1.dart` + `pass1_findings.json` + `probes.json`
- `tool/redteam_blind_dh_20260906T1609/pass2.dart` + `pass2.json`
- `tool/redteam_blind_dh_20260906T1609/confirm_c3.dart` + `confirm_c3.json`
