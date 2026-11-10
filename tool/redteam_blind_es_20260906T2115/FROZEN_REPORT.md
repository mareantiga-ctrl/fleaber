# FROZEN_REPORT — REDTEAM_BLIND_ES_BAG_SINGLE_PAY_RETEST_v1

## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 1
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 1

1. P0 dinheiro irreversível? NÃO
2. Quantos P0: 0
3. P1 caminho explorável? SIM
4. Quantos P1: 1
5. P2 hygiene? NÃO
6. Quantos P2: 0
7. P3 baixo risco? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_ES_BAG_SINGLE_PAY_RETEST_v1
FROZEN_AT: 2026-09-06T21:33:31+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 10
classes_novas: 8
lentes_cobertas: [ES-A, ES-B, ES-C]
pocos_tentados: [ES-A, ES-B, ES-C]
races_future_wait: [A1, A2, A3, A4]
stripe_test_pago: true
dual_cs_pay_attempted: true
dual_cs_both_captured: false
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTES-20260906T2115-` · pasta: `tool/redteam_blind_es_20260906T2115/`.  
Atacante CPI: buyer JWT fresco buyer3 `88eb9886-419c-4eec-9225-868ee8717f82` + buyer4 `1cf843d4-4054-4fa9-8402-153ba5e62a0a` + confirm buyer5 `5e088f5e-ace6-4aab-803a-38c341508134`. `service_role` só fixture/observação.

GATE: 2 capturas = P0. Dual links sem captura = P1 (**não Fase 4**). Esperado: ≤1 create.

Reteste: **6∥4 continua fechado** (A4 400+200, 1 `cs_`). **bag∥single t=0 e single→bag 50 ms continuam com 2 `cs_`.** A3 bag∥single∥bag @200 ms unificou em 1 `cs_` (`reused=true,false,true`). Sem `sk_test_` local. Tentativa 4242 nas duas Sessions A1 (buyer4 e pass1): `payment_pages` 404, GET Session com pk **403** secret_key_required, settle **402** nas duas. 0 capturas. Ledger A1 `reserva_pendente`, qty=1.

---

## P1-1 — Saco e artigo avulso ao mesmo tempo: dois links; 2.ª captura não ocorreu

**O que isto é:** o comprador pede o pagamento de um saco de 5 artigos e, no mesmo instante (ou 50 ms depois), o pagamento avulso do artigo do meio. O cadeado (já fechado em 6∥4) tinha de entregar no máximo um link. Se mesmo assim saírem dois, pagar o segundo com cartão de teste **não** pode liquidar o stock duas vezes.

**Quem / onde:** comprador (JWT fresco buyer3 / buyer4 / buyer5) no checkout do saco vs checkout de um artigo. Stripe TEST.

**O que fizemos:**
- A1 fresco buyer4: saco ABCDE ∥ pagamento avulso da linha C, qty=1, t=0.
- Pass1 A1 (buyer3 fresco): o mesmo.
- A2: avulso primeiro → 50 ms → saco ABCDE.
- Pass2 buyer5: nova ronda A1, mesmos 2 links.
- B1/B2 + `a1_pay`: tentar pagar as duas Sessions (4242 via pk / payment_pages / settle; checkout alojado com URL devolvida).
- B3: ler encomendas + stock + Hub.

**Esperado vs resultado**
- API A1 buyer4: esperado ≤1 `cs_` · visto **2** `cs_test_` distintas, HTTP 200, `reused=false` (`a1BjYEA3…` + `a1yQ9AkZ…`)
- API A1 buyer3: **2** `cs_test_` (`a1Ahzcba…` + `a1XsFfsB…`), `reused=false`
- API A2: o mesmo padrão 200+200, 2 `cs_` (`a1FzSbbg…` órfã avulsa; saco `a1lDGNhw…` nas 5 linhas)
- Confirm buyer5: **2** `cs_test_` (`a1vPFcjv…` + `a1bIF1HX…`), `reused=false`. Ledger 5/5 = saco.
- Ledger: as 5 linhas apontam para a Session do saco; a Session avulsa ficou órfã
- Checkout alojado: URL devolvida hash=373 → Stripe «This link is incomplete»
- B1 primeira Session: pk GET Session **403**; `payment_pages` 404; settle **402**; **não paga**
- B2 segunda Session: o mesmo; **não paga**
- Base de dados após B1/B2 e após `a1_pay`: 5 encomendas `reserva_pendente`; qty produto **1**; `amount_paid_cents` vazio
- Contraste A3 (mesmo comprador): bag∥single∥bag @200 ms = **1** `cs_` reused (`a1KRQ3C8…`)
- Contraste A4: 6∥4 = 400+200 `overlapping bag session` · **1** `cs_` (`a1W3WHUe…`)

**Conclusão:** **P1** — o cliente recebeu dois links no bag∥single t=0 e no stagger 50 ms (reproduzido em 3 compradores frescos). Não é P0: as duas capturas **não** aconteceram; o stock não foi vendido duas vezes. 6∥4 **já** está fail-closed. Dual links sem 2.ª captura **bloqueiam Fase 4**.  
**Prova:** `a1_dual.json` + `probes.json` A1+A2 + B1/B2/B3 + `a1_pay.json` + `pass2.json`.

---

## Anti-atrofia

Exactos **não corridos / não contados**:
- settle unpaid 402 clássico — GET 402 nas duas Sessions A1 **não** é finding
- buyer refund 403 — sem double capture; não corrido

Fechos novos documentados (FAIL, ataque bloqueado / esperado):
- **A3** bag∥single∥bag @200 ms → 200+200+200 **1** `cs_test_a1KRQ3C8…` (`reused=true,false,true`)
- **A4** 6∥4 t=0 → 400+200 overlapping · 1 `cs_test_a1W3WHUe…`
- C1 wallet buyer3 Δ=0 após B1/B2 (sem captura overlap); seller 21,00 estável
- C2 happy bag único: PI `pi_3UCmji…` 1115 ¢, ambas linhas `pago`, soma proporcional
- C3 leftover 2→1: `pago`, qty=1, Hub n=1

HOLD na tabela = A1+A2 (um P1) = **2/10 = 20%** < 40%. **Não** ATROFIA_ABORT.  
classe_nova=SIM: A1, A2, A3, B1, B2, B3, C1, C3 (**8** ≥ 3).

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|-----------|------------------|--------------|
| A1 | ES-A | Future.wait bag ABCDE ∥ single C t=0 | 200+200 duas `cs_` reused=false | ledger saco `a1Ahzcba…`; órfã `a1XsFfsB…`; buyer4+buyer5 dual | **HOLD** P1-1 | SIM |
| A2 | ES-A | Future.wait single C first →50ms→ bag | 200+200 duas `cs_` reused=false | ledger saco `a1lDGNhw…`; órfã `a1FzSbbg…` | **HOLD** P1-1 | SIM |
| A3 | ES-A | Future.wait bag ∥ single +200ms ∥ bag | 200×3 **1** `cs_` reused | 1 sid `a1KRQ3C8…`; só linha do meio escrita | FAIL | SIM |
| A4 | ES-A | Future.wait bag 6∥4 t=0 regressão ≤1 | 400+200 overlapping · 1 `cs_` | ledger 1 sid `a1W3WHUe…` | FAIL | NÃO |
| B1 | ES-B | pagar primeira `cs_` 4242 (A1) | pk 403; pages 404; settle 402 | 5× `reserva_pendente` qty=1 | FAIL | SIM |
| B2 | ES-B | pagar segunda `cs_` 4242 (mesmo overlap) | pk 403; pages 404; settle 402 | 0 pagos; 2.ª captura **não** | FAIL | SIM |
| B3 | ES-B | oráculo Hub + products + orders (2 pagos?) | paid1=false paid2=false | 0 `pago`; qty=1 | FAIL | SIM |
| C1 | ES-C | wallet Δ após B1/B2 | paid1=false paid2=false | buyer3 Δ=0; seller 21,00 | FAIL | SIM |
| C2 | ES-C | 1× happy bag único pago | e2e `setup_paid_bag` 200 PI `pi_3UCmji…` 1115 ¢ | ambas `pago` proporcional | FAIL | NÃO |
| C3 | ES-C | Hub leftover após pago qty 2→1 | e2e PI `pi_3UCmjl…` 590 ¢ | `pago` qty=1 Hub n=1 | FAIL | SIM |

Linhas na tabela: **10** (≥10). Races `Future.wait`: **4**. Stripe TEST pago: **sim** (C2+C3 e2e; overlap `cs_` **não** capturadas). classe_nova=SIM: **8**.  
Races bag∥single: A1 = 2 `cs_` · A2 = 2 `cs_` · A3 = 1 `cs_` reused (≥3). Extra: buyer4 A1 dual + buyer5 pass2 dual.

HOLD na tabela = findings. FAIL = ataque bloqueado / caminho sem P0. SKIP = 0.

---

## Tácticas mínimas (quota)

1. Tabela ≥10: **10**
2. ≥3 bag∥single races: **sim** (A1, A2, A3)
3. Se 2 `cs_` open: pagar ambas 4242: **sim** (B1+B2 + `a1_pay` buyer4) — 0 capturas → **não P0**
4. Se ≤1 `cs_`: A3 reused + A4 400 documentados; 1× happy bag pago: **sim** (C2)
5. ≥3 classe_nova: **8**

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → sem retrieve nativo nem `pm_card_visa` na Session.
- Checkout alojado: URL devolvida (473 chars, hash 373) → Stripe «This link is incomplete». GET do HTML é o bundle JS (564 kB) sem `client_secret` da Session. Prova de dual = 2× HTTP 200 + 2 `cs_` + `reused=false` + settle 402.
- `payment_pages/{sid}/init` 404 «No such checkout.session» com `pk_test_` da página; GET `/v1/checkout/sessions/{sid}` com pk → 403 `secret_key_required`.
- Hub n=0 nos SKUs A1 (não publicados no Hub); leftover C3 usa o fluxo e2e (Hub n=1).
- Seller wallet 21,00 estável nesta ronda (e2e C2+C3 liquidaram encomendas; crédito carteira Δ=0 no overlap).
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_es_20260906T2115/_rtes.dart`
- `tool/redteam_blind_es_20260906T2115/a1_dual.dart` + `a1_dual.json`
- `tool/redteam_blind_es_20260906T2115/a1_pay.dart` + `a1_pay.json`
- `tool/redteam_blind_es_20260906T2115/pass1.dart` + `pass1_findings.json` + `probes.json`
- `tool/redteam_blind_es_20260906T2115/pass2.dart` + `pass2.json`

RESUMO_NUMERICO: P0=0 P1=1 P2=0 P3=0 TOTAL=1
