# FROZEN_REPORT — REDTEAM_BLIND_EG_BAG_PAY_POS_OPEN_v1

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
AUDITOR: REDTEAM_BLIND_EG_BAG_PAY_POS_OPEN_v1
FROZEN_AT: 2026-09-06T19:20:00+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 14
classes_novas: 12
lentes_cobertas: [EG-A, EG-B, EG-C]
pocos_tentados: [EG-A, EG-B, EG-C]
races_future_wait: [A1, A2, A3, A4, A5, B5]
stripe_test_pago: true
dual_cs_pay_attempted: true
dual_cs_both_captured: false
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTEG-20260906T1907-` · pasta: `tool/redteam_blind_eg_20260906T1907/`.  
Atacante CPI: buyer JWT fresco (`973f995b-190d-4d23-a3bd-506a0b84c943`). `service_role` só fixture/observação.

GATE: 2 capturas + stock inconsistente = P0. 2.ª paga falhou / links duplos sem captura = P1 (bloqueia abertura).  
Sem `sk_test_` local. Tentativa 4242 nas duas Sessions: `payment_pages` 404 com pk, confirm sem `client_secret`, Checkout alojado «This link is incomplete» (hash idêntico em todos os `cs_`), GET settle **402** nas duas. Ledger A1 continua `reserva_pendente`, qty=1, 0 pagos.

---

## P1-1 — Overlap 6∥4, expand, bag∥single e stagger: duas Sessions; 2.ª captura não ocorreu

**O que isto é:** o comprador pede ao mesmo tempo o pagamento de um saco grande e, em paralelo, um subconjunto, um artigo avulso, ou o mesmo saco com 50 ms de atraso. O cadeado tinha de entregar no máximo um link Stripe. Se mesmo assim saírem dois, pagar o segundo com cartão de teste **não** pode liquidar stock duas vezes.

**Quem / onde:** comprador (JWT buyer3 fresco) no checkout do saco. Stripe TEST.

**O que fizemos:**
- A1: saco ABCDEF ∥ saco BCDE a t=0 (qty=1, mesmas encomendas).
- A2: subconjunto → 50 ms → saco maior.
- A3: saco de 5 ∥ pagamento avulso da linha do meio.
- A4: saco cheio t=0 → 50 ms → subconjunto.
- B1/B2: tentar pagar as duas Sessions do A1 (4242 via pk / cartão / página Checkout / settle).
- B3: ler encomendas + stock + Hub depois da tentativa.

**Esperado vs resultado**
- API A1–A4: esperado ≤1 `cs_` útil · visto **2** `cs_test_` distintas, HTTP 200, `reused=false` em cada corrida
- Ledger A1: as 6 linhas apontam para `cs_test_a1JMp4uc…`; a Session de 4 (`cs_test_a16ytZR…`) ficou órfã
- B1 primeira Session: `payment_pages` 404; confirm 400 sem `client_secret`; settle **402** «ainda não confirmado»; **não paga**
- B2 segunda Session: o mesmo; **não paga**
- Checkout no browser (URL completa 473 caracteres, hash): «This link is incomplete»
- Base de dados após B1/B2 (pass2): 6 encomendas `reserva_pendente`; qty produto **1**; `amount_paid_cents` vazio; stock_units_applied vazio
- Settle pass2: **402** + **402** (não contar como finding — anti-atrofia unpaid 402)

**Conclusão:** **P1** — o cliente recebeu dois links no overlap (A1, A2, A3, A4). Não é P0: as duas capturas **não** aconteceram; o stock não foi vendido duas vezes. A 2.ª paga falhou (sem chave secreta Stripe local + página Checkout incompleta + settle 402). Links duplos sem 2.ª captura **bloqueiam abertura** até o cadeado do saco ficar em ≤1 Session.  
**Prova:** `probes.json` A1–A4 + B1/B2/B3 + `pass2.json`.

---

## Anti-atrofia

Exactos **não corridos / não contados**:
- settle unpaid 402 clássico — GET 402 nas duas Sessions **não** é finding
- buyer refund 403 — C2 sem double capture; não corrido

Fechos novos documentados (FAIL, ataque bloqueado / esperado):
- A5 2× bag idêntico → 200+200 **mesmo** `cs_` (`reused=true`)
- B4 N/A — havia 2 open; caminho B1/B2
- B5 bags disjuntos: 2 `cs_`; tentativa de pagar 1 não marcou o outro `pago`
- C1 wallet buyer3 Δ=0 após B1/B2 (sem captura overlap); seller 4,00→19,00 pelos e2e C3+C4
- C2 sem double capture
- C3 leftover 2→1: `pago`, qty=1, Hub 1 linha (pass2)
- C4 happy bag único: PI `pi_3UCkZ5…` 1115 ¢, ambas linhas `pago`, soma proporcional

HOLD na tabela = A1–A4 (um P1) = **4/14 ≈ 29%** < 40%. **Não** ATROFIA_ABORT.  
classe_nova=SIM: A1, A2, A3, A4, B1, B2, B3, B4, B5, C1, C2, C3 (**12** ≥ 4).

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|-----------|------------------|--------------|
| A1 | EG-A | Future.wait bag 6∥4 t=0 qty=1 | 200+200 duas `cs_` reused=false | ledger `a1JMp4uc…`; órfã `a16ytZR…` | **HOLD** P1-1 | SIM |
| A2 | EG-A | Future.wait subset→50ms→superset | 200+200 duas `cs_` | dual create | **HOLD** P1-1 | SIM |
| A3 | EG-A | Future.wait bag ABCDE ∥ single C meio | 200+200 duas `cs_` | dual create | **HOLD** P1-1 | SIM |
| A4 | EG-A | Future.wait full→50ms→subset | 200+200 duas `cs_` | dual create | **HOLD** P1-1 | SIM |
| A5 | EG-A | Future.wait 2× bag idêntico invertido | 200+200 mesmo `cs_` reused=true | 1 sid `a1inzrZR…` | FAIL | NÃO |
| B1 | EG-B | pagar primeira `cs_` 4242 (A1) | pk 404; confirm 400; settle 402; browser incomplete | 6× `reserva_pendente` qty=1 | FAIL | SIM |
| B2 | EG-B | pagar segunda `cs_` 4242 (mesmo overlap) | pk 404; confirm 400; settle 402 | 0 pagos; 2.ª captura **não** | FAIL (P1 residual = links) | SIM |
| B3 | EG-B | oráculo Hub + products + orders | paid1=false paid2=false | 0 `pago`; qty=1; pass2 Hub C3 ok | FAIL | SIM |
| B4 | EG-B | 1 open + settle órfã | N/A — 2 open; B1/B2 | 2 sids A1 | FAIL | SIM |
| B5 | EG-B | Future.wait bags disjuntos; pagar 1 | 200+200 duas `cs_`; pay esquerda falhou igual | direita não `pago` | FAIL | SIM |
| C1 | EG-C | wallet Δ após B1/B2 | paid1=false paid2=false | buyer3 Δ=0; seller +15 (C3+C4 e2e) | FAIL | SIM |
| C2 | EG-C | refund se double capture | sem 2 capturas | N/A | FAIL | SIM |
| C3 | EG-C | Hub leftover após pago qty 2→1 | e2e PI `pi_3UCkZ0…` 590 ¢ | `pago` qty=1 Hub n=1 (pass2) | FAIL | SIM |
| C4 | EG-C | 1× happy bag pago único | e2e `setup_paid_bag` 200 PI `pi_3UCkZ5…` 1115 ¢ | ambas `pago` proporcional | FAIL | NÃO |

Linhas na tabela: **14** (≥14). Races `Future.wait`: **6**. Stripe TEST pago: **sim** (C3+C4 e2e; overlap `cs_` **não** capturadas). classe_nova=SIM: **12**.  
Tentativas dual-checkout que produziram 2 `cs_`: **4** (A1, A2, A3, A4) ≥ 3.

HOLD na tabela = findings. FAIL = ataque bloqueado / caminho sem P0. SKIP = 0.

---

## Tácticas mínimas (quota)

1. ≥3 overlaps dual `cs_` **ou** documentar ≤1: **sim** (A1–A4 = 2 `cs_`; A5 = 1)
2. Se 2 `cs_`: tentar pagar **ambas** 4242: **sim** (B1+B2 + browser) — 0 capturas
3. Oráculo stock Hub + products + orders: **sim** (B3 + pass2)
4. Tabela ≥14: **14**
5. ≥4 classe_nova: **12**
6. ≥3 races: **6**
7. 1× happy bag pago: **sim** (C4)

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → sem retrieve nativo nem `pm_card_visa` na Session.
- Hash do `checkoutUrl` **idêntico** em todas as Sessions (473 caracteres) → Checkout alojado «link incomplete». Não contado como P2 extra (igual DZ: webview/Checkout não distingue expire).
- `fase2_e2e_settle` com service_role devolveu **401** «service_role required» neste harness — não usado como prova de captura.
- GET Hub com `select=quantity` deu 400 (coluna inexistente) no pass1; pass2 sem essa coluna = 200 n=1.
- Seller wallet 4,00→19,00 pelos e2e C3+C4 (5,90 € + ~11,15 €); **não** finding.
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_eg_20260906T1907/_rteg.dart`
- `tool/redteam_blind_eg_20260906T1907/pass1.dart` + `pass1_findings.json` + `probes.json`
- `tool/redteam_blind_eg_20260906T1907/pass2.dart` + `pass2.json`
- `tool/redteam_blind_eg_20260906T1907/extract_cs.dart`

RESUMO_NUMERICO: P0=0 P1=1 P2=0 P3=0 TOTAL=1
