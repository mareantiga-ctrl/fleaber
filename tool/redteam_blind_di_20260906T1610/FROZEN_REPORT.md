# FROZEN · REDTEAM_BLIND_DI_OFERTAS_CHAT_POS_DBDG_v1
Prefixo `RTDI-20260906T1610` · staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST  
`production_touched: false` · `fase4: false` · `corrections_applied: false`

--------------------------------------------------
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
--------------------------------------------------

```
AUDITOR: REDTEAM_BLIND_DI_OFERTAS_CHAT_POS_DBDG_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: 21
VEREDICTO: PASS_CEGO_SATURADO
```

Anti-atrofia: **OK**. Residual exacto CQ na tabela: `12,00` → **400 `notes_forbidden`** (HOLD, não contar). 1/21 ≪ 50%. Sem PaysafeCash/PicPay. Sem chase de rails.

Fluxo terminal oferta: A1b aceite 8€ → CPI body `amount=1` → Session **905¢** (8€+protecção).  
Fluxo terminal conjunto: B4 aceite 22€ → Session **2375¢**; B1 hostil `total_eur=0.01` reescrito para **11,00€** (cap 50%) → Session **1220¢**.

--------------------------------------------------
## Missão
Preço de proposta/bundle **autoritativo** (não body cliente). Aceitar/rejeitar/supersede sem double-pay nem stock fantasma. Cards chat + inbox **não** liquidam dinheiro.

**Resposta:** **Sim, saturado.** INSERT `status=accepted` é forçado a `pending`. `amount` imutável. CPI ignora body `amount=1` e usa o selo (8€ / catálogo / `total_eur` reescrito). Oferta rejected não liga (`product_offer_id=null`, selo 18€). Qty>1 recusada. Unpublished/sold recusados. One-shot `offer_already_consumed`. Bundle cap 50% + saco completo + 1 contrato. Card canónico OK; PATCH `pago` sem Stripe **403**; inbox hostil **403**; Seguro label **mismatch**; OCR sem token **401**. Cards `price_offer`/`bundle_proposal` não liquidam e o total hostil é recusado.

--------------------------------------------------
## Findings abertos

Nenhum. TOTAL P0–P3 = 0.

--------------------------------------------------
## HOLD (não contar como finding)

- A1 lowball 0,01€ persiste **pending** (não auto-aceite) — proposta do comprador, vendedor tem de aceitar
- A2 corrida accept∥reject: ambos HTTP 200; BD final **accepted**; selo 800¢; Session 905¢ (um terminal)
- B2 accept HTTP 200 com `quantity=0` numa linha; INSERT order → `order_hold_exceeds_stock`; **sem Session** (defesa no hold, não no accept)
- C2 card `notes=pago` 201 (token canónico) + PATCH 403; status `reserva_pendente` inalterado; wallet vendedor 37,0 no instante do PATCH (ruído 37→36 só no dump final, concorrente)
- C6 `price_offer` sem `order_id` → `order_id_required` (fail-closed antes do mismatch de amount)
- Residual CQ `12,00` → 400 `notes_forbidden` (não contar)

Lentes cobertas: DI1 offer price · DI2 accept race · DI3 bundle · DI4 stock · DI5 chat card · DI6 inbox · DI7 FSM pago / OCR (7/7).

--------------------------------------------------
## TABELA DE PROVAS (21 LIVE)

| probe_id | superfície | payload | HTTP/RPC | BD/ledger | HOLD\|FAIL\|SKIP |
|---|---|---|---|---|---|
| A1 | DI-A oferta | POST amount=0.01 status=accepted | 201 | status=pending amount=0.01 | FAIL |
| A1b | DI-A oferta | oferta 8€ aceite + CPI amount=1 | 200 cs_test_a1afshd9… | amount_total=**905** (não 1€) | PASS |
| A1c | DI-A oferta | PATCH amount=0.01 pending | 403 offer_amount_immutable | amount=8.0 | FAIL |
| A2 | DI-A race | accept ∥ reject Future.wait | 200/200 + CPI 200 | status=accepted sealed=800 amt=905 | FAIL |
| A3 | DI-A stale | offer rejected amount=2 + CPI | 200 | offer_id=null sealed=1800 amt=**1955** | FAIL |
| A4 | DI-A qty | order qty=3 + product_offer_id | 400 offer_quantity_must_be_one | sem order | FAIL |
| A5 | DI-A dead | unpublished INSERT + unlist accept | 400 offer_product_not_listed | recusado | FAIL |
| A6 | DI-A oneshot | 2.ª order mesmo offer aceite | 400 offer_already_consumed | sem 2.ª bind | FAIL |
| B1 | DI-B conjunto | total_eur=0.01 discount_pct=99 | 201 + CPI 200 | total=**11.00** disc=50 amt=**1220** | PASS |
| B2 | DI-B stock 0 | accept com qty=0 numa linha | accept 200 · order 400 hold_exceeds_stock | qty=0 · sem cs_ | FAIL |
| B3 | DI-B supersede | 2 bundle_id no mesmo saco | 400 mix multiple bundle contracts | recusado | FAIL |
| B4 | DI-B underpay | bundle aceite 22€ + CPI amount=1 | 200 cs_test_a17TWNSG… | total=22.0 amt=**2375** | PASS |
| B5 | DI-B incompleto | saco 1 de 2 SKUs | 400 bag must include all items | recusado | FAIL |
| C1 | DI-C card | reservation_payment_submitted notes=ok | 201 id=1768 | orders.status=pago (já Stripe) | PASS |
| C2 | DI-C composição | card notes=pago + PATCH status=pago | card 201 id=1769 · patch 403 | reserva_pendente | FAIL |
| C3 | DI-C inbox | last_message=pago 0,01 sem Stripe | 403 preview_forbidden | last_message=null | FAIL |
| C4 | DI-C Seguro | label=compra paga 0,01 € | 400 label_mismatch | recusado | FAIL |
| C5 | DI-C OCR | ingest sem x-device-token | 401 missing_device_token | sem ingest | FAIL |
| C6 | DI-C offer card | price_offer amount=0.01 vs BD 8€ | 400 order_id_required | recusado | FAIL |
| C7 | DI-C bundle card | bundle_proposal total_eur=0.01 | 400 bundle_total_mismatch | total BD=22.0 | FAIL |
| C8 | DI-C residual | notes=12,00 | 400 notes_forbidden | recusado | HOLD (residual, não contar) |

Quota ≥14: **21**. Residual HOLD: **1** (`12,00`; anti-atrofia; não finding). Matriz A≥5 B≥4 C≥5 cumprida.

Oferta A1b `1d67e305-aaa2-4fa1-a46d-f3dc393cdea1` · Session 905¢.  
Conjunto B4 `086e69ea-de2c-4ef3-bc4a-3a44cc60dbe4` total 22€ · Session 2375¢.  
Chat pago `edaaf8e8-1d09-43dd-bb91-f47fa9891bff` · encomenda Stripe `b616e799-2d02-4637-bca7-7d5be56fd26c` (`pago`, PI `pi_3UChoZH7FWYUN3jh1KkTo0Ur`).  
Pendente C2 `c2d9c027-4400-4b40-b873-f4c5158c985c` inalterada.

**NÃO CORRIGIR.**
