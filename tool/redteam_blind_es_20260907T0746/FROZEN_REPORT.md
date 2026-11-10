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
FROZEN_AT: 2026-09-07T08:01:44+01:00
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
hosted_bag_captured: true
hosted_orphan_captured: false
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTES-20260907T0746-` · pasta: `tool/redteam_blind_es_20260907T0746/`.  
Atacante CPI: buyer JWT fresco buyer3 `f022a021-8421-432e-82b0-0e3472560bb5` + confirm buyer5 `dbe4ed95-00b0-48c8-8767-4470298fa6b4`. `service_role` só fixture/observação.

GATE: 2 capturas = P0. Dual links sem 2.ª captura = P1 (**não Fase 4**). Esperado: ≤1 create.

Reteste: **6∥4 continua fechado** (A4 400+200, 1 `cs_`). **bag∥single t=0 e single→bag 50 ms continuam com 2 `cs_`.** A3 bag∥single∥bag @200 ms unificou em 1 `cs_` (`reused=true,false,true`). Sem `sk_test_` local. Checkout alojado Stripe TEST 4242: saco A1 **capturado** (5 `pago`, qty=0, PI `pi_3UCwR4…`); 2.ª Session **não** pagável (página «This link is incomplete» / «You’re all done here» + settle **402**). Confirm buyer5: o mesmo padrão (saco capturado, órfã 402). 0 2.ªs capturas. Sem oversell.

---

## P1-1 — Saco e artigo avulso ao mesmo tempo: dois links; 2.ª captura não ocorreu

**O que isto é:** o comprador pede o pagamento de um saco de 5 artigos e, no mesmo instante (ou 50 ms depois), o pagamento avulso do artigo do meio. O cadeado (já fechado em 6∥4) tinha de entregar no máximo um link. Se mesmo assim saírem dois, pagar o segundo com cartão de teste **não** pode liquidar o stock duas vezes.

**Quem / onde:** comprador (JWT fresco buyer3 / buyer5) no checkout do saco vs checkout de um artigo. Stripe TEST (checkout alojado 4242).

**O que fizemos:**
- A1 fresco buyer3: saco ABCDE ∥ pagamento avulso da linha C, qty=1, t=0.
- A2: avulso primeiro → 50 ms → saco ABCDE.
- Confirm buyer5: nova ronda A1, mesmos 2 links.
- B1: pagar a Session do saco no checkout alojado (4242, 12/30, CVC 123).
- B2: abrir a Session órfã no mesmo browser e num separador novo.
- B3: ler encomendas + stock + Hub.

**Esperado vs resultado**
- API A1 buyer3: esperado ≤1 `cs_` · visto **2** `cs_test_` distintas, HTTP 200, `reused=false` (`a1d3UdJJ…` saco + `a1XxM9eg…` órfã)
- API A2: 200+200, 2 `cs_` (`a1BhAxGF…` órfã; saco `a1inDmeI…` nas 5 linhas)
- Confirm buyer5: **2** `cs_test_` (`a1bzcBWo…` saco + `a15s8rmo…` órfã), `reused=false`. Ledger 5/5 = saco.
- Ledger pré-pago: as 5 linhas apontam para a Session do saco; a Session avulsa ficou órfã
- B1 checkout alojado saco A1: formulário «Saco Fleaber» **€33,73** · 4242 aceite · settle **200** · PI `pi_3UCwR4H7FWYUN3jh0eBhAXfz` · **5 `pago`**, `amount_paid_cents` 525+600+675+750+823, qty=0, `is_sold=true`
- B2 Session órfã A1: «This link is incomplete» (URL sem hash) e «You’re all done here» (URL completa, também em separador novo) · settle **402** · **não paga**
- Confirm: saco alojado 4242 settle **200**, 5 `pago`, qty=0; órfã settle **402**
- Contraste A3 (mesmo comprador): bag∥single∥bag @200 ms = **1** `cs_` reused (`a1ylfnUe…`)
- Contraste A4: 6∥4 = 400+200 `overlapping bag session` · **1** `cs_` (`a1FFdfth…`)

**Conclusão:** **P1** — o cliente recebeu dois links no bag∥single t=0 e no stagger 50 ms (reproduzido em 2 compradores frescos nesta ronda). Não é P0: a 2.ª captura **não** aconteceu; o stock do saco foi vendido **uma** vez (qty 1→0). 6∥4 **já** está fail-closed. Dual links sem 2.ª captura **bloqueiam Fase 4**.  
**Prova:** `pay_urls.json` + `probes.json` A1+A2 + `ledger_after_hosted.json` + `confirm.json`.

---

## Anti-atrofia

Exactos **não corridos / não contados**:
- settle unpaid 402 clássico na órfã — GET 402 **não** é finding
- buyer refund 403 — sem double capture; não corrido

Fechos novos documentados (FAIL, ataque bloqueado / esperado):
- **A3** bag∥single∥bag @200 ms → 200+200+200 **1** `cs_test_a1ylfnUe…` (`reused=true,false,true`)
- **A4** 6∥4 t=0 → 400+200 overlapping · 1 `cs_test_a1FFdfth…`
- B1/B2 hosted: 1.ª captura saco OK; 2.ª órfã morta no Stripe
- C1 wallet buyer3 Δ=0 após overlap; seller 21,00 estável (crédito carteira não acompanhou o Stripe nesta ronda — não é P0)
- C2 happy bag único: PI `pi_3UCwNx…` 1115 ¢, ambas linhas `pago`, soma proporcional
- C3 leftover 2→1: `pago`, qty=1, Hub n=1

HOLD na tabela = A1+A2 (um P1) = **2/10 = 20%** < 40%. **Não** ATROFIA_ABORT.  
classe_nova=SIM: A1, A2, A3, B1, B2, B3, C1, C3 (**8** ≥ 3).

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|-----------|------------------|--------------|
| A1 | ES-A | Future.wait bag ABCDE ∥ single C t=0 | 200+200 duas `cs_` reused=false | ledger saco `a1d3UdJJ…`; órfã `a1XxM9eg…`; buyer5 dual | **HOLD** P1-1 | SIM |
| A2 | ES-A | Future.wait single C first →50ms→ bag | 200+200 duas `cs_` reused=false | ledger saco `a1inDmeI…`; órfã `a1BhAxGF…` | **HOLD** P1-1 | SIM |
| A3 | ES-A | Future.wait bag ∥ single +200ms ∥ bag | 200×3 **1** `cs_` reused | 1 sid `a1ylfnUe…` | FAIL | SIM |
| A4 | ES-A | Future.wait bag 6∥4 t=0 regressão ≤1 | 400+200 overlapping · 1 `cs_` | ledger 1 sid `a1FFdfth…` | FAIL | NÃO |
| B1 | ES-B | pagar primeira `cs_` 4242 (A1 saco alojado) | API pk 403/pages 404; alojado **pago** €33,73 | 5× `pago` qty=0 PI `pi_3UCwR4…` settle 200 | FAIL | SIM |
| B2 | ES-B | pagar segunda `cs_` 4242 (órfã A1 + confirm) | «incomplete» / «all done»; settle 402 | 0 2.ªs capturas | FAIL | SIM |
| B3 | ES-B | oráculo Hub + products + orders (2 pagos?) | paid_bag=true paid_orph=false | 5 `pago` qty=0; sem qty&lt;0 | FAIL | SIM |
| C1 | ES-C | wallet Δ após B1/B2 | paid_orph=false | buyer3 Δ=0; seller 21,00 | FAIL | SIM |
| C2 | ES-C | 1× happy bag único pago | e2e `setup_paid_bag` 200 PI `pi_3UCwNx…` 1115 ¢ | ambas `pago` proporcional | FAIL | NÃO |
| C3 | ES-C | Hub leftover após pago qty 2→1 | e2e PI `pi_3UCwO0…` 590 ¢ | `pago` qty=1 Hub n=1 | FAIL | SIM |

Linhas na tabela: **10** (≥10). Races `Future.wait`: **4**. Stripe TEST pago: **sim** (C2+C3 e2e **e** saco overlap alojado 4242). classe_nova=SIM: **8**.  
Races bag∥single: A1 = 2 `cs_` · A2 = 2 `cs_` · A3 = 1 `cs_` reused (≥3). Extra: buyer5 confirm dual.

HOLD na tabela = findings. FAIL = ataque bloqueado / caminho sem P0. SKIP = 0.

---

## Tácticas mínimas (quota)

1. Tabela ≥10: **10**
2. ≥3 bag∥single races: **sim** (A1, A2, A3)
3. Se 2 `cs_` open: pagar ambas 4242: **sim** (B1 alojado capturou o saco; B2 órfã recusada) — 1 captura, 0 2.ªs → **não P0**
4. Se ≤1 `cs_`: A3 reused + A4 400 documentados; 1× happy bag pago: **sim** (C2)
5. ≥3 classe_nova: **8**

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → retrieve nativo / `pm_card_visa` na Session falhou; a captura real foi no **checkout alojado** Stripe TEST.
- API `payment_pages/{sid}/init` 404 «No such checkout.session» com `pk_test_` da página; GET `/v1/checkout/sessions/{sid}` com pk → 403 `secret_key_required`.
- Session órfã: URL completa mostra «You’re all done here» mesmo em separador novo (não é só o hash dummy). Settle 402. Não foi possível forçar a 2.ª captura.
- Hub n=0 nos SKUs A1 (não publicados no Hub); leftover C3 usa o fluxo e2e (Hub n=1).
- Seller wallet 21,00 estável nesta ronda após capturas Stripe (crédito carteira Δ=0 no overlap).
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_es_20260907T0746/_rtes.dart`
- `tool/redteam_blind_es_20260907T0746/pass1.dart` + `pass1_findings.json` + `probes.json` + `pay_urls.json`
- `tool/redteam_blind_es_20260907T0746/confirm.dart` + `confirm.json`
- `tool/redteam_blind_es_20260907T0746/ledger_after_browser.json` + `ledger_after_hosted.json`

RESUMO_NUMERICO: P0=0 P1=1 P2=0 P3=0 TOTAL=1
