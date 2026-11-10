# Fleaber — Auditoria cega independente (Red Team)

**Projecto:** Supabase staging `fxdknzrqjenzqcvnwqqq`  
**Stripe:** TEST exclusivamente  
**Produção:** não tocada  
**Fase 4:** não iniciada  
**Correcções:** nenhuma (auditor, não implementador)  
**FROZEN_AT:** `2026-08-30T10:32:00+01:00`

Identidades de laboratório (JWT reais, não service_role como atacante):

- Anon (chave anónima)
- Buyer `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96`
- Seller `980f4fa1-0004-42f9-abca-69f1a9c29588`
- Terceiros observados: buyer `97f3089e-…`, seller `69104e91-…`

service_role usado só para fixtures, observação e cleanup.

---

## Veredicto

**D — PASS_CEGO_SATURADO**

Zero P0. Zero P1. Invariantes financeiros críticos atacados em LIVE. Composição e races executadas. Último passe completo sem nova classe P0/P1. Saturação = SIM, com limitações explícitas abaixo.

---

## Checklist final

| # | Pergunta | Resposta |
|---|----------|----------|
| 1 | P0 aberto encontrado | **NÃO** |
| 2 | Quantos P0 | **0** |
| 3 | P1 aberto encontrado | **NÃO** |
| 4 | Quantos P1 | **0** |
| 5 | Buyer consegue manipular preço autoritativo | **NÃO** |
| 6 | Buyer consegue manipular qty autoritativa | **NÃO** |
| 7 | Seller consegue falsificar pagamento plataforma | **NÃO** |
| 8 | JWT consegue criar saldo/fundos | **NÃO** |
| 9 | Refund pode exceder captura | **NÃO** |
| 10 | Release+refund cria dinheiro líquido | **NÃO** |
| 11 | Payout pode duplicar Transfer indevidamente | **NÃO COMPROVADO** (Connect IBAN em falta; débito RPC sem EXECUTE JWT) |
| 12 | Stock=1 pode produzir duas vendas válidas | **NÃO** (11 rounds: 10+1 concurrent, máx. 1 INSERT 201) |
| 13 | Stock=1 pode produzir duas capturas líquidas permanentes | **NÃO COMPROVADO** (não houve 2 orders válidas para pagar) |
| 14 | Existe bypass de capacidade/reserva | **NÃO** |
| 15 | Existe cross-user financeiro | **NÃO** |
| 16 | Existe cross-user de dados sensíveis | **NÃO** (provas privadas vazias; IBAN só seller com relação) |
| 17 | Buyer pode assumir autoridade seller/admin | **NÃO** |
| 18 | Seller pode assumir autoridade buyer/admin | **NÃO** |
| 19 | Reviews podem ser forjadas/duplicadas | **NÃO** |
| 20 | RPC/SECURITY DEFINER perigoso encontrado | **NÃO** (vários DEFINER com EXECUTE JWT; authz LIVE recusou efeitos) |
| 21 | RLS crítico quebrado | **NÃO** |
| 22 | Edge Function confia em autoridade do cliente | **NÃO** (amount/qty/product/seller/prize_shipping ignorados ou bloqueados) |
| 23 | Alguma conclusão crítica ficou NÃO COMPROVADA | **SIM** (payout Transfer dupla; captura dupla da mesma order via 2 Sessions) |
| 24 | Houve regressão funcional relevante | **NÃO** (não se implementou código) |
| 25 | Último passe encontrou nova classe P0/P1 | **NÃO** |
| 26 | Saturação atingida | **SIM** |
| 27 | Produção tocada | **NÃO** |
| 28 | Fase 4 iniciada | **NÃO** |

---

## Findings

### P0 / P1

Nenhum comprovado.

### RT-INDEP-20260830-P2-01 — Duas Checkout Sessions na mesma order

| Campo | Valor |
|-------|--------|
| **Severidade** | P2 |
| **Actor** | Buyer JWT |
| **Pré-condições** | Order própria em `reserva_pendente` com contrato selado |
| **Reprodução** | Dois POST paralelos a `create-payment-intent` no mesmo `order_id`, `amount` 1 vs 999999 |
| **Resultado LIVE** | Ambos HTTP 200. `cs_test_a1rluq…` e `cs_test_a1vWOG…`. Ambos `server_amount_cents=1955` / `amount_total=1955` |
| **Impacto** | Duas Sessions Stripe TEST no mesmo contrato. **Não** são duas vendas. Captura dupla **não** foi paga. Settle GET sem pagamento não marca pago. |
| **Estado** | Aberto / higiene: limitar Sessions por order. Efeito económico permanente: **NÃO COMPROVADO** |

Evidência: `out/03_pass3b.json` dual session A/B.

### RT-INDEP-20260830-P3-01 — Enumeração email→UUID (vendedor)

RPC `batata_find_user_id_by_email`: anon 401; buyer 200 `null`; seller 200 devolve UUID do email pedido.

Impacto: enumeração de contas por um vendedor autenticado (convites staff). Sem efeito financeiro.

### RT-INDEP-20260830-P3-02 — GET settle anónimo consulta Stripe

`GET create-payment-intent?checkout_return=success&session_id=cs_test_fake` → erro Stripe «No such checkout.session». Session conhecida não paga → texto «Pagamento ainda não confirmado», order inalterada.

Impacto: oráculo de existência de session / abuso de API Stripe no servidor. Sem settle forjado.

### RT-INDEP-20260830-P3-03 — Metadados de rifas / mensagens de sistema LIVE

Buyer autenticado lê `live_raffles` de outros sellers (incl. `draw_seed` de rifas **já drawn**). Rifas `active` observadas com `draw_seed=null`. `live_messages` `kind=user` de outros lives: vazio. Mensagens `kind=system` (FOMO) visíveis.

Impacto: metadados públicos de live, não prova de chat privado nem seed previsível pré-sorteio.

---

## Superfícies testadas

AUTH/PROFILES · ORDERS/FSM · PRODUCTS/PRICE/QTY · CHECKOUT/STRIPE SESSION · SETTLE GET · BAG (linha alheia) · WALLET/LEDGER · PAYOUT (bloqueado Connect) · STOCK · REFUNDS (dual + retry) · DISPUTES · LIVE/LIVE ITEMS/RESERVAS · OFFERS · RAFFLES · TIPS (session 1€) · CHAT · REVIEWS · STORAGE · MUX create/complete · LIVEKIT token · PS pairing/OCR · RPCs DEFINER · RLS SELECT/INSERT/UPDATE · EDGE

Não acessível / fora: OpenAPI PostgREST (401); tabela `lives` `select=*` (coluna stream key sem GRANT); payout Transfer real.

---

## Invariantes (tentativa de refutação)

| ID | Invariante | Resultado LIVE |
|----|------------|----------------|
| A | Stripe cobra o contrato servidor | **Mantido.** Cliente `amount=50` → Session `1115` cêntimos (10€ + protecção). Cliente `amount=1` e `999999` → ambos `1955`. |
| B | Buyer não define preço/qty autoritativos | **Mantido.** INSERT `price_total=0.01` selou `contract_unit_cents=1000`. PATCH qty/price/stripe revertidos. Checkout ignora body. |
| C | Release/refund/payout ≤ fundos legítimos | **Mantido no observado.** Release MB WAY sem captura → `false`, wallets inalteradas. Refund 590¢ uma vez; retry `already_refunded=true`. |
| D | Uma unidade ≠ duas vendas válidas | **Mantido no INSERT.** 10 inserts paralelos stock=1 → 1×201 + 9×`order_hold_exceeds_stock`. 10 rounds 2-way: sempre `wins=1`. |
| E | JWT não cria saldo/PI/session authority | **Mantido.** PATCH wallet 200 `[]`. INSERT wallet/transações/ledger 403/401. Stripe IDs no INSERT anulados. |
| F | Pagamento off-platform ≠ saldo Fleaber | **Mantido.** Seller marcou MB WAY `pago`, `stock_units_applied=1`, `amount_paid_cents=null`, release `false`, wallets iguais. |
| G | Refund acumulado ≤ captura | **Mantido.** Dual: um 500 idempotency in-progress, um 200 `re_3UA5tz…` 590¢; retry idempotente mesmo id. |
| H | Parties coerentes | **Mantido.** Troca buyer_id revertida. Product/seller mismatch 23514. Checkout product/seller mismatch 400. |
| I | Uma intenção payout ≤ uma Transfer | **NÃO COMPROVADO** (Connect sem IBAN; Edge recusou antes de Stripe). |
| J | Duas intenções distintas → duas Transfers | **NÃO COMPROVADO** (mesmo bloqueio). |
| K | Catálogo posterior ≠ contrato aceite | **Mantido.** Após PATCH seller `price=0.01`, checkout da order selada a 10€ → `1115` cêntimos. |
| L | Offer/bundle/reserva só com autoridade | **Mantido.** Offer 0.01 aceite → RLS 403. Reserva buyer→accepted → 200 `[]`. prize_shipping em order normal → 400. |

---

## Races

| Race | N | Estado final |
|------|---|--------------|
| 10× INSERT order stock=1 | 1×201, 9×400 | `held_qty=1`, product `quantity=1` |
| 10 rounds 2× INSERT stock=1 | `wins=[1,1,1,1,1,1,1,1,1,1]` | nunca 2 vendas |
| 2× Checkout Session mesma order | 2×200, ambos 1955¢ | Sessions criadas; **sem captura** |
| 2× refund mesma order | 500 + 200; retry idempotente | 1 refund Stripe 590¢ |
| 2× payout keys distintas | 2×400 Connect IBAN | sem débito observado |
| 2× reviews | 400 status inválido | sem row |

---

## Stripe TEST

| Fase | Resultado |
|------|-----------|
| SESSION CRIADA | Sim: `1115`, `1955`, `1955` (dual), tip `cs_test_a1F4gim…` |
| CAPTURA REAL TEST | Refund de captura **pré-existente** `pi_3UA5tzH7FWYUN3jh17CQQ1hU` (590¢) — seller autorizado. Novas Sessions **não** pagas neste audit. |
| CAPTURA LÍQUIDA PERMANENTE | Sem evidência de captura extra. Dual Session ≠ dual captura. |

Não há `STRIPE_SECRET` no env local do auditor → pagamento 4242 das Sessions novas não foi concluído.

---

## Ataques que falharam (prova de defesa, não de segurança absoluta)

- INSERT order `status=pago` + PI fake → persistido como `reserva_pendente`, stripe/amount null, contrato 1000¢
- Qty 999999 → `order_hold_exceeds_stock`
- Buyer PATCH pago/cancelado/qty/price/stripe/buyer_id → valores antigos
- Seller PATCH platform order → pago → revertido a `reserva_pendente`
- Seller INSERT atribuindo buyer → `order_buyer_attribution_denied`
- Wallet PATCH/INSERT crédito → 0 rows / denied
- `user_type` admin/vendedor/admim → permanece `comprador`
- Mux live como buyer → 403 authz
- Refund buyer / refund order alheia → 403
- Checkout seller com `buyer_id` alheio → Invalid checkout user
- Bag com order de terceiro → order does not belong to buyer
- fase2_e2e_settle JWT → 401 service_role required
- Webhook sem assinatura → missing_signature
- OCR token fake → invalid_token
- Pairing `000000` → invalid_or_expired_code
- Staff helper self-insert → RLS 403
- Dispute order alheia / própria pago → RLS 403
- Review sem order / pending / pago não concluído → 23514
- IBAN de seller sem relação → `[]`
- Chat/order de terceiro → `[]`
- Stream keys `select=` → 42501
- `exec_sql` / `sql` RPC → inexistente

HTTP 200 em PATCH **não** foi persistência: o trigger devolveu a row com campos revertidos.

---

## Composição

order × catalog × checkout: preço catálogo 0.01 após selo 10€ → Session 11,15€.  
order × proposal: offer hostil RLS.  
order × Stripe × refund: refund seller 590¢, retry idempotente.  
stock × N orders: hold.  
reservation × accept buyer: sem efeito.  
review × order: status gate.  
dispute × third party: RLS.  
release × MB WAY pago: sem crédito wallet.  
webhook × return path: GET fake não settle.  
bag × foreign order: bloqueado.

---

## Lacunas (não inflacionar)

1. Pagar as duas Sessions da mesma order até captura Stripe TEST — **não feito** (sem secret Stripe local).
2. Payout Connect com IBAN TEST — **não feito**; Transfer dupla NÃO COMPROVADA.
3. Race 2 buyers distintos no mesmo stock=1 — só o buyer de laboratório (um JWT). Dois INSERTs do mesmo buyer já saturaram o hold.
4. Live activa Mux/LiveKit com stream key (GRANT coluna) — não extraída.
5. PS OCR com token de device real — só token inválido.

---

## Saturação

- PASS 1 cobertura: RLS, RPCs, Edge, money cols, profiles, mux, storage list  
- PASS 2 invariantes: contrato, checkout amount, prize_shipping, MB WAY wallet, banking IDOR, reviews, shipping seal  
- PASS 3 composição/races: stock 11 rounds, dual session, dual refund, dual payout (fail-closed Connect)  
- Último passe: dual session (P2, não P0/P1 novo) + refund idempotente  

**SATURAÇÃO = SIM**

---

## Efeitos colaterais de laboratório (não findings)

- Refund TEST da order `6a3268c5-…` (captura 5,90€) — ataque seller-autorizado para dual-refund.  
- Sessions Stripe TEST não pagas (expiram).  
- Product V0 `f85ded7d-…` preço restaurado a 10€, qty 6.  
- Orders hostis canceladas via observação/cleanup.

---

## Artefactos

| Ficheiro | Conteúdo |
|----------|----------|
| `00_discover.dart` | OpenAPI/RLS/Edge varrimento |
| `01_hostile.dart` | RLS money, RPC, Edge hostil |
| `02_pass23.dart` | Invariantes, checkout, race 10, storage |
| `03_pass3b.dart` | Dual session, refund dual, 10 rounds stock |
| `04_observe_refund.dart` | Estado pós-refund |
| `out/*.json` | Evidência bruta |
| `frozen.json` | Machine-readable |

Probes em `tool/redteam_blind_indep_20260830/`.
