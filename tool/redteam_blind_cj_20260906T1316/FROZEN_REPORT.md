# FROZEN_REPORT — REDTEAM_BLIND_CJ_MARKETPLACE_POS_CDCI_v1

## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 1
P2 aberto: SIM → quantos: 2
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 3
1. P0? NÃO  2. Quantos P0: 0
3. P1? SIM  4. Quantos P1: 1
5. P2? SIM  6. Quantos P2: 2
7. P3? NÃO  8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_CJ_MARKETPLACE_POS_CDCI_v1
FROZEN_AT: 2026-09-06T13:30:00+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 26
lentes_cobertas: [CJ1, CJ2, CJ3, CJ4, CJ5, CJ6, CJ7, CJ8]
pocos_tentados: [CJ-A, CJ-B, CJ-C, CJ-D]
races_future_wait: [A1, A4, A5, C1, C2, C3, C4]
stripe_test_pago: true
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTCJ-20260906T1316-` · pasta: `tool/redteam_blind_cj_20260906T1316/`.  
Atacantes: anon · buyer JWT · seller JWT · buyer2 · seller2. `service_role` só fixture/observação (`plantClaim`, `setup_paid_order`).

---

## P1-1 — Overlap saco 4 linhas ∥ 2 linhas: duas Sessions Stripe

**O que isto é:** o comprador pode pedir ao mesmo tempo o pagamento de quatro artigos e, em paralelo, só de dois desses artigos. O sistema não pode deixar dois links de pagamento Stripe abertos que cubram os mesmos artigos.

**Quem / onde:** comprador (JWT) no checkout do saco.

**O que fizemos:** criámos 4 encomendas do mesmo vendedor (A,B,C,D). Disparámos ao mesmo tempo um saco ABCD e um saco CD.

**Esperado vs resultado**
- API: esperado ≤1 `cs_` · visto **2** `cs_test_` distintas, ambas HTTP 200 com `checkoutUrl`
- Ledger: esperado o mesmo sid em A–D · visto A e B **vazios**; C e D com a Session do saco de 2 linhas (`cs_test_a1ZlGY9Z…`)
- Stripe/settle: GET settle nas duas → **402 unpaid** (os dois objectos existem e não estão pagos)
- Captura 4242 nas duas URLs: **não feita** (sem `sk_test_` local)

**Conclusão:** **P1** — caminho explorável: o cliente recebeu dois links; uma Session de 4 linhas ficou órfã no Stripe. Não é P0 porque não pagámos as duas. Não é o dual bag∥single nem o triângulo de 3 sacos já fechados.  
**Prova:** `probes.json` A5 + `pass2_findings.json` A5.live.

---

## P2-1 — `cs_` morta/inválida bloqueia o checkout (DoS)

**O que isto é:** se o campo da Session Stripe na encomenda ficar com um identificador inválido, o comprador tem de conseguir voltar a pagar. Não pode ficar preso.

**Quem / onde:** comprador JWT; o valor morto foi plantado só como observação de crash (não é o ataque JWT).

**O que fizemos:** abrimos uma Session real; gravámos `stripe_checkout_session_id=cs_test_deaddeaddeaddeaddead12`; repetimos o checkout.

**Esperado vs resultado**
- API: esperado reclaim + nova `cs_` · visto `400 No such checkout.session: cs_test_deaddeaddeaddeaddead12`
- BD: o sid morto **manteve-se**
- Stripe: nenhuma Session nova

**Conclusão:** **P2** — a encomenda fica impagável. O fecho CDCI cobriu `claiming:` com TTL; **não** cobre `cs_` inválida (o Stripe `retrieve` rebenta antes do reclaim).  
**Prova:** probe A3.

---

## P2-2 — `claiming:` com data no futuro prende o cadeado para sempre

**O que isto é:** o cadeado temporário do checkout deve caducar ao fim de ~90 s. Uma data no futuro não pode transformá-lo num bloqueio eterno.

**Quem / onde:** comprador JWT após plantação de observação `claiming:<now+1 ano>:futuretoken12ab`.

**O que fizemos:** plantámos o token; o comprador fez checkout; o RPC JWT foi negado (403), como deve ser.

**Esperado vs resultado**
- API: esperado reclaim (como no legado sem timestamp) · visto `400 order claim contention`
- BD: token futuro **intacto**
- Controlo A2 (TTL+1 s no passado): reclaim OK, nova `cs_` — o TTL funciona para o passado, não para o futuro

**Conclusão:** **P2** — DoS permanente, classe nova face ao órfão `claiming:abc` (A8a: legado sem ms **reclaim OK**).  
**Prova:** probe A8c; contraste A8a/A8b/A2.

---

## Anti-atrofia

Exactos CDCI **não contados** (e nesta corrida bloqueados ou nem usados como finding):
- reclaim TTL clássico órfão sem timestamp → A8a `claiming:abc` **FAIL** (reclaim + `cs_`)
- bag∥single dual — não é o A5 (A5 = 4∥2 overlap)
- 3-sacos A∩B∩C — não corrido como finding
- underpay body clássico → B2/B5 **FAIL** (selo CTT 1693¢; só EUR)

B4 `8e-1`: Postgres gravou **0,80 €** visível; Session **149 ¢** alinhada com a oferta aceite pelo script. **Não é finding** (contrato honesto, não spoof de UI).  
Carteira vendedor 72,00 → 62,00: ronda **CN payout** em paralelo (PATCH wallets); não imputar a CJ.

Três findings = vectores **novos**. Atrofia: **não**.

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP |
|----------|------|----------------|----------|-----------|------------------|
| A1 | CJ-A | Future.wait 2×CPI claiming TTL−10s | 400 contention ×2 | stored `claiming:<now-80s>` payable=0 | FAIL |
| A2 | CJ-A | CPI após claiming TTL+1s | 200 `cs_test_a1TnQpDj…` | sid `cs_` reclaim OK | FAIL |
| A3 | CJ-A | CPI com `cs_test_deaddeaddeaddeaddead12` | 400 No such checkout.session | sid morto persistente | **HOLD** P2-1 |
| A4 | CJ-A | Future.wait bag timeout 250ms ∥ retry | 598 + 200 | 1 `cs_` nas 2 linhas | FAIL |
| A5 | CJ-A | Future.wait bag 4-line ∥ bag 2-line overlap CD | 200+200 duas `cs_` | A,B sid vazio; C,D `a1ZlGY9Z`; settle 402×2 | **HOLD** P1-1 |
| A5b | CJ-A | settle GET + GET páginas das 2 cs_ A5 | 402 + 402 (páginas 403 CDN) | ambos unpaid | FAIL (confirma A5) |
| A6 | CJ-A | PATCH qty/price com Session open | PATCH qty 403 `order_money_fields_immutable`; CPI 1640→1640 | contrato selado | FAIL |
| A7 | CJ-A | GET settle unpaid + órfão PI | 402 «Pagamento ainda não confirmado» | `reserva_pendente` sem PI | FAIL |
| A8a | CJ-A | `claiming:abc` legado | RPC JWT 403; CPI 200 | nova `cs_` | FAIL |
| A8b | CJ-A | `claiming:` sem ms | RPC JWT 403; CPI 200 | nova `cs_` | FAIL |
| A8c | CJ-A | `claiming:<+1y>:futuretoken12ab` | RPC JWT 403; CPI 400 contention | token futuro intacto | **HOLD** P2-2 |
| B1a | CJ-B | coupon SELLER2-50 + unicode + discount_cents=1700 | 200 | amount_total **1955** (catálogo 18€+taxas) | FAIL |
| B1b | CJ-B | offer rejected amount=2 no checkout | 200 | amount_total **1955** (não 2€) | FAIL |
| B1c | CJ-B | offer seller2 aceite colada em SKU seller1 | 200 | amount_total **1955** (catálogo S1) | FAIL |
| B2 | CJ-B | portes 0 / shipping_cents=-350 / método -3.50 (selo CTT) | 200 + 200 | **1693** ¢ ambas (CTT+protecção, não 0) | FAIL |
| B3 | CJ-B | bundle `total_eur=0.01` + discount 99 | insert 201; CPI 200 | **1168** ¢ (cap ~50%, não 1¢) | FAIL |
| B4 | CJ-B | offer arabic/scientific/circled/NNBSP/fraction | arabic 22P02; `8e-1` → amount 0.80 aceite | Session **149** ¢ = 0,80€+taxas | FAIL |
| B5 | CJ-B | currency usd/jpy + amount １２ + ｅｕｒ | 400 only EUR ×3 | sem Session | FAIL |
| C1 | CJ-C | Future.wait 2 buyers CPI após 2 holds + PATCH qty=1 | 400 stock 0 ×2 | 0 Sessions | FAIL |
| C2 | CJ-C | Future.wait CPI ∥ unlist | 400 not listed | `list_on_marketplace=false` | FAIL |
| C3 | CJ-C | Future.wait CPI ∥ deleted_at (fallback qty=0) | CPI 200 ganhou a corrida; PATCH 200 | qty **0** após Session | FAIL |
| C4 | CJ-C | Future.wait CPI ∥ is_sold=true | 400 marked sold ×2 | `is_sold=true` | FAIL |
| C5a | CJ-C | bag qty 9999 rpc + bag_lines | rpc `request_not_found`; CPI 200 | amount **905** ¢ (1 un., não 9999) | FAIL |
| C5b | CJ-C | cross-seller bag | 400 must share one seller | — | FAIL |
| D1 | CJ-D | seller PATCH pago MB WAY sem prova | 403 `order_mbway_pago_requires_proof` | `reserva_pendente` | FAIL |
| D2 | CJ-D | cancel JWT + refund-order JWT buyer pós-pago | 403 + 403 Sem permissão | status continua `pago` | FAIL |
| PAID | CJ-D | Stripe TEST pago 4242 + contabilidade | e2e `setup_paid_order` 200 | `pago` PI `pi_3UCf9HH7FWYUN3jh0S8qUSMw` 590¢ stock 2→1 `stock_units_applied=1` | FAIL |

Linhas na tabela: **26** (≥20). Races `Future.wait`: **7**. Stripe TEST pago: **sim**.

HOLD na tabela = finding. FAIL = ataque bloqueado / defesa manteve o contrato. SKIP = 0.

---

## Lentes (≥6/8)

| Lente | Evidência |
|-------|-----------|
| CJ1 | coupon ignorado 1955¢; portes selados 1693¢; só EUR |
| CJ2 | TTL±; A8 legado vs futuro; cs_ morta P2-1 |
| CJ3 | bundle 1168¢; offer rejected 1955¢; `8e-1`→0,80 honesto |
| CJ4 | MB WAY sem prova 403; cancel/refund buyer 403 |
| CJ5 | last-unit 0 Sessions; sold; qty 9999 |
| CJ6 | Future.wait A1/A4/A5/C1–C4 |
| CJ7 | offer S2 em SKU S1 1955¢; bag 2 sellers 400; RPC claim JWT 403 |
| CJ8 | PI succeeded 590¢; settle 402; wallets buyer 61,10 estável |

---

## Tácticas mínimas (quota)

1. Checkout Stripe TEST pago (4242 / `setup_paid_order`): **sim** — order `682f11ac-1b6c-411d-90d9-ed2cec4b27d6`, PI `pi_3UCf9HH7FWYUN3jh0S8qUSMw`, `amount_paid_cents=590`, qty 2→1
2. ≥3 races `Future.wait` distintas: **sim** (A1, A4, A5, C1, C2, C3, C4)
3. Tabela ≥20: **26**
4. Poços A–D: **sim**
5. Lentes ≥6: **8/8**

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → sem expire/retrieve/list nativo; A3 usou `cs_` morta; A5 sem captura 4242 nas 2 URLs (por isso P1, não P0)
- `deleted_at` em products: PATCH vendedor caiu; C3 usou `quantity=0` (compensação documentada)
- Δwallet seller 72→62: ronda CN em paralelo, não CJ
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_cj_20260906T1316/_rtcj.dart`
- `tool/redteam_blind_cj_20260906T1316/pass1.dart` + `pass1_findings.json` + `probes.json`
- `tool/redteam_blind_cj_20260906T1316/pass2.dart` + `pass2_findings.json`
