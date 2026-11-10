# FROZEN_REPORT — REDTEAM_BLIND_CP_MARKETPLACE_POS_ALLOW_v1

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
AUDITOR: REDTEAM_BLIND_CP_MARKETPLACE_POS_ALLOW_v1
FROZEN_AT: 2026-09-06T14:22:00+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 13
lentes_cobertas: [CP1, CP2, CP3, CP4, CP5, CP6, CP7]
pocos_tentados: [CP-A, CP-B, CP-C]
races_future_wait: [A5, B1, B2, B3]
stripe_test_pago: true
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTCP-20260906T1410-` · pasta: `tool/redteam_blind_cp_20260906T1410/`.  
Atacantes: anon · buyer JWT · seller JWT · buyer2 · seller2. `service_role` só fixture/observação (`plantClaim`, `setup_paid_order`).

---

## P1-1 — Overlap saco 4 linhas ∥ 2 linhas: duas Sessions Stripe

**O que isto é:** o comprador pede ao mesmo tempo o pagamento de quatro artigos e, em paralelo, só de dois desses artigos. O sistema não pode entregar dois links Stripe que cubram os mesmos artigos.

**Quem / onde:** comprador (JWT) no checkout do saco.

**O que fizemos:** 4 encomendas do mesmo vendedor (A,B,C,D). `Future.wait` saco ABCD ∥ saco CD.

**Esperado vs resultado**
- API: esperado ≤1 `cs_` · visto **2** `cs_test_` distintas, ambas HTTP 200 com `checkoutUrl`
- Ledger: esperado o mesmo sid coerente · visto A–D **todas** com a Session do saco de 4 (`cs_test_a1HoXqnS…`); a Session de 2 linhas (`cs_test_a1ZTLk9Y…`) ficou órfã no Stripe
- Stripe/settle: GET settle nas duas → **402 unpaid**
- Captura 4242 nas duas URLs: **não feita** (sem `sk_test_` local)

**Conclusão:** **P1** — o cliente recebeu dois links; uma Session de 2 linhas ficou órfã. Não é P0: não pagámos as duas. O fecho CJCO (claim sem overwrite) **não** impediu as duas criações em corrida. Residual da matriz CP-B1, classe já vista em CJ, ainda aberta.  
**Prova:** `probes.json` B1 + `pass2.json` B1.pages.

---

## P1-2 — Allowlist off-platform: ZWSP / fullwidth / cirílico abrem Stripe

**O que isto é:** um pedido marcado como MB WAY (pagamento fora da app) não pode abrir um link Stripe. A lista branca compara o método **exacto** depois de minúsculas e espaços; o que não está na lista passa como «pagamento na app».

**Quem / onde:** comprador JWT; `orders.payment_method` + `create-payment-intent`.

**O que fizemos:**
- Controlo: `mb way` → CPI **400** `order is off-platform payment`
- `mbway` + U+200B (ZWSP) → **200** `cs_test_a1kugyn3…`; BD `payment_method` codes `6d 62 77 61 79 200b` (len=6)
- `ｍｂｗａｙ` (fullwidth) → **200** `cs_test_a1byiCY1…`
- `мbway` (cirílico м) → **200** `cs_test_a1qXVOXf…`
- NBSP / CR no fim → **400** off-platform (o trim/`\s` do JS come esses)

**Esperado vs resultado**
- API: esperado 400 off-platform nos lookalikes · visto Session Stripe nos três encodings
- BD: pedido continua `reserva_pendente` com método hostil persistido
- Caixa: sem captura 4242 nestes três (não é P0)

**Conclusão:** **P1** — bypass da allowlist exacta (`isOffPlatformPaymentMethod`). O vendedor pode achar que é MB WAY enquanto o comprador paga na app. Classe nova (não é lista de rails PaysafeCash/PicPay).  
**Prova:** `probes.json` C1 + `pass2.json` zwsp/alw.

---

## Anti-atrofia

Exactos **não contados** / agora bloqueados:
- reclaim `cs_` morta → A1 **FAIL** (reclaim + `cs_`; buyer2 400; JWT PATCH 403 `order_money_fields_immutable`)
- `claiming:<futuro>` → A2 **FAIL** (CPI 200 + `cs_`; RPC JWT 403)
- claiming malform / sem ms / passado extremo → A3 **FAIL** (3× reclaim)
- PaysafeCash · PicPay · esaurito · Coptic · follow unpublished — **não corridos** (fora de âmbito CP)

Underpay body `total_eur=0` / `item_price=0.01`: Session **2323** ¢ (18€+CTT+protecção) — **FAIL**.  
Portes homoglyph / `€3.5` fora da allowlist: **400** portes inválidos — **FAIL**.  
Coupon/portes com Session open: amount **2533→2533** reuse — **FAIL**.

Residual HOLD = **1** (4∥2) em **2** findings. Classe nova = allowlist off-platform. **Não** ATROFIA_ABORT.

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP |
|----------|------|----------------|----------|-----------|------------------|
| A1 | CP-A | plant `cs_test_dead`; buyer2 CPI; owner retry | JWT PATCH 403; buyer2 400; retry 200 `cs_test_a1v762Cy…` | sid novo; morta não persiste | FAIL |
| A2 | CP-A | `claiming:<now+1y>:futuretoken12ab` | RPC JWT 403; CPI 200 | sid `cs_test_a1rCrF7N…` | FAIL |
| A3 | CP-A | `claiming:malformed` / `claiming:` / `claiming:1000:…` | 200×3 | 3 `cs_` novas | FAIL |
| A4 | CP-A | Session single → bag overlap → 2.º CPI (sem `sk_test_` expire) | 200+200+200 três `cs_` | ledger última `a1sMZErb…`; settle 402×3 **não** distingue expired | FAIL |
| A5 | CP-A | Future.wait bag timeout 250ms ∥ retry | 598 + 200 | 1 `cs_` nas 2 linhas | FAIL |
| B1 | CP-B | Future.wait bag 4-line ∥ bag 2-line overlap CD | 200+200 duas `cs_` | A–D `a1HoXqnS…`; órfã `a1ZTLk9Y…`; settle 402×2 | **HOLD** P1-1 |
| B2 | CP-B | Future.wait 2 buyers última unidade (qty 2→1) | 400 stock 0 ×2 | 0 Sessions | FAIL |
| B3 | CP-B | Future.wait CPI ∥ unlist+qty=0 | 400 not listed | `list_on_marketplace=false` qty=0 | FAIL |
| B4 | CP-B | bag qty 9999 + cross-seller | rpc `request_not_found`; fat **905** ¢; cross 400 one seller | 1 un. não 9999 | FAIL |
| C1 | CP-C | `total_eur=0`+CTT; homoglyph portes; `mbway`+ZWSP | CTT 200 **2323** ¢; homo/€3.5 400; ZWSP 200 `cs_` | pm codes `…79 200b` | **HOLD** P1-2 |
| C2 | CP-C | Session open CTT; 2.º CPI coupon FREESHIP + mão | 200 reuse mesma `cs_` | amt **2533=2533**; ship `ctt` | FAIL |
| C3 | CP-C | Stripe TEST pago 4242 + caixa | e2e `setup_paid_order` 200 | `pago` PI `pi_3UCfwYH7FWYUN3jh1xJvEJnX` 590¢ stock 2→1 `applied=1` | FAIL |
| ALW1 | CP-C | mbway NBSP/CR/fullwidth/cirílico | NBSP/CR 400; fw+cyr 200 `cs_` | pm `ｍｂｗａｙ` / `мbway` | **HOLD** P1-2 |

Linhas na tabela: **13** (≥12). Races `Future.wait`: **4** (A5, B1, B2, B3). Stripe TEST pago: **sim**.

HOLD na tabela = finding. FAIL = ataque bloqueado / defesa manteve o contrato. SKIP = 0.

A4: três URLs em sequência (contrato de 2.ª Session após overlap). Sem `sk_test_` retrieve, settle 402 não prova Sessions ainda abertas — **não** elevado a P0/P1.

---

## Lentes (≥5/7)

| Lente | Evidência |
|-------|-----------|
| CP1 Session | A1 reclaim morta; A4 2.ª Session; B1 duas `cs_` |
| CP2 claiming | A2 futuro reclaim; A3 malform reclaim; RPC JWT 403 |
| CP3 bag∥ | B1 4∥2; B4 cross-seller 400 |
| CP4 stock | B2 0 Sessions; B3 unlist 400; C3 qty 2→1 |
| CP5 preço | C1 2323 ¢ selo CTT; C2 2533 estável; P1-2 allowlist |
| CP6 race | Future.wait A5/B1/B2/B3 |
| CP7 caixa | PI succeeded 590¢; wallets buyer 61,10 estável |

---

## Tácticas mínimas (quota)

1. Checkout Stripe TEST pago (4242 / `setup_paid_order`): **sim** — order `431a782a-b3c9-431b-ab86-01aca46a016a`, PI `pi_3UCfwYH7FWYUN3jh1xJvEJnX`, `amount_paid_cents=590`, qty 2→1
2. ≥2 races `Future.wait` distintas: **sim** (A5, B1, B2, B3)
3. Tabela ≥12: **13**
4. Matriz CP-A (5) CP-B (4) CP-C (3): **sim**
5. Lentes ≥5: **7/7**

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → sem expire/retrieve nativo; A4 usou overlap bag; settle 402 ≠ `status=open`
- Δwallet seller 61,00 → 57–58: ronda payout em paralelo (não imputar a CP); buyer 61,10 estável
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_cp_20260906T1410/_rtcp.dart`
- `tool/redteam_blind_cp_20260906T1410/pass1.dart` + `pass1_findings.json` + `probes.json`
- `tool/redteam_blind_cp_20260906T1410/pass2.dart` + `pass2.json` + `pass2_findings.json`
