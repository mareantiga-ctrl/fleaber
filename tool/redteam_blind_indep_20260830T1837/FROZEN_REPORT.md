# FLEABER — Relatório congelado · Red Team cego independente

**FROZEN_AT:** `2026-08-30T17:53:12Z`  
**Projecto:** Supabase staging `fxdknzrqjenzqcvnwqqq`  
**Stripe:** TEST apenas  
**Produção tocada:** NÃO  
**Fase 4 iniciada:** NÃO  
**Correcções aplicadas:** NÃO (auditor)  
**Prefixo de fixtures:** `RT1837`

## Veredicto

**D — PASS_CEGO_SATURADO**

Zero P0 confirmados. Zero P1 confirmados. Superfícies críticas atacadas live com JWT de laboratório (buyer/seller/anon), sem usar `service_role` para demonstrar exploits. Races e composição executadas. Último passe (Pass 4, assinaturas RPC exactas + settle de gorjeta fake + bag) sem nova classe P0/P1.

## Papel e cegueira

Auditoria adversarial independente. Código actual, schema live e comportamento staging. Relatórios anteriores / hardening / reteste / production gate **não** foram usados como roteiro. Findings do Pass 1 que dependiam de colunas inexistentes foram **descartados** (falsos positivos de parser), não promovidos.

Identidades:

| Papel | Uso |
|---|---|
| anon | PostgREST + Edge + webhook |
| buyer JWT lab | `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96` |
| seller JWT lab | `980f4fa1-0004-42f9-abca-69f1a9c29588` |
| service_role | só fixture / observação / cleanup |
| Stripe TEST | Sessions + 1 captura E2E + refund + payouts TEST |

---

## Findings

Nenhum P0/P1 aberto.

### P3 (higiene / defesa em profundidade)

| ID | Sev. | Título | Actor | Estado |
|---|---|---|---|---|
| RT1837-P3-01 | P3 | `batata_create_live_tip_pending` persiste `stripe_session_id` escolhido pelo cliente | buyer JWT | ABERTO |
| RT1837-P3-02 | P3 | `batata_find_user_id_by_email` existe para vendedor (rate 2/h) | seller JWT | ABERTO |

**RT1837-P3-01** — Pré: directo existente. Repro: RPC com `p_stripe_session_id=cs_fake_RT1837` → `200` UUID, row `pending`. Impacto: lixo na tabela; **settle JWT = 403** `permission denied for function batata_settle_live_tip_from_stripe`. Sem crédito. Não sobe a P1.

**RT1837-P3-02** — Seller lab: `400 rate_limited`. Buyer: `200 null`. Enumeração email→UUID limitada. Sem PII extra nesta prova.

Falsos positivos Pass 1 (`RT1837-P1-CHAT-LIST`, `RT1837-P1-DISPUTE-READ`): SELECT com colunas inexistentes; o erro JSON foi classificado como “row alheia”. **Não são findings.** Reteste com schema real: chats só próprios; disputes só `buyer_id` do JWT.

---

## Superfícies testadas

AUTH/PROFILES, ORDERS + FSM, PRODUCTS/CATALOG/PRICE/QTY, CHECKOUT Session, SETTLE GET, WEBHOOK, BAG, WALLET/LEDGER/PAYOUT, STOCK, REFUNDS (incl. concorrentes), DISPUTES, OFFERS, BUNDLES, LIVE/ITEMS/RESERVAS, RAFFLES, TIPS, CHAT, REVIEWS, STORAGE `fleaber_private`, MUX column grants, LIVEKIT publish, PS pairing/OCR/device token, RPCs SECURITY DEFINER, RLS, Edge Functions listadas abaixo.

Edge atacadas directamente: `create-payment-intent`, `refund-order`, `create-connect-account`, `create-live-tip-checkout`, `stripe-webhook`, `create-mux-live`, `livekit-mux-publish`, `ingest-ocr-reservation`, `ps-pairing-claim`, `delete-test-account`, `send-sms-bulkgate`, `sec-fase2-e2e-oversell`, `complete-mux-live`, `meta-data-deletion`.

OpenAPI (service_role): 247 paths, 178 RPCs.

---

## Invariantes financeiros (tentativa de refutação)

| ID | Claim | Resultado live |
|---|---|---|
| A | Stripe cobra o contrato servidor | **HOLD.** Underpay `amount=50` ignorado. Após drop de catálogo 12€→0,50€ Session `amount_total=1325`. Bag hostil `line_total=1c` → `1105` (5€+6€ + ajuste servidor, não 50c). |
| B | Buyer não define preço/qty autoritativos | **HOLD.** `prize_shipping` em order normal → 400. `seller_id` trocado → 400. INSERT qty 99 → `order_hold_exceeds_stock`. Contrato selado `unit=1200 qty=1`. |
| C | Release/refund/payout não criam dinheiro líquido | **HOLD.** Captura TEST 590c → refund concorrente 6× mesmo `re_…` idempotente. Wallets buyer/seller inalterados no refund. Release após refund = `false`. |
| D | Uma unidade ≠ duas vendas válidas | **HOLD.** Hold seq: 201 + `order_hold_exceeds_stock`. Race 10× INSERT stock=1: **1/10** 201. |
| E | JWT não cria saldo/PI/payout authority | **HOLD.** Wallet INSERT 403; PATCH `200 []` saldo inalterado (16.90). `credit_wallet_once` / `debit_wallet_once` / `payout_debit` / `payout_finish` 403. INSERT order `pago`+PI fake bloqueado. `user_type=admin` eco 200 mas row continua `comprador`. |
| F | Off-platform não minta saldo plataforma | **HOLD.** Seller PATCH MB WAY → `pago` (sem PI). Buyer `concluido`. RPC release `true` mas **saldo seller 37.96→37.96** (true = selo, não crédito). |
| G | Refund ≤ captura | **HOLD.** 6 refunds concorrentes: um `re_3UACpK…`, `already_refunded/idempotent`. |
| H | Parties coerentes | **HOLD.** Checkout order alheia: `does not belong to buyer`. PATCH swap parties: money immutable / vazio. |
| I | Uma intenção payout ≤ 1 Transfer | **HOLD.** Mesma idempotency key → mesmo `transferId`. |
| J | Intenções distintas → Transfers distintas | **HOLD.** Keys diferentes → Transfers distintas (comportamento legítimo). |
| K | Catálogo posterior não reescreve contrato | **HOLD.** Session 1325c após price 0,50€. |
| L | Offer/bundle só com autoridade | **HOLD.** Offer 0,01€ INSERT forçado a `pending`; self-accept `offer_accept_not_authorized`. Bundle INSERT `bundle_products_required`. |

---

## Races

| Race | N | Resultado final |
|---|---|---|
| INSERT hold stock=1 | 10 paralelo | 1×201, 9×400 |
| create-payment-intent mesma order | 8 paralelo | 8×200, **1** `checkoutSessionId` |
| GET settle session **não paga** | 8 paralelo | 8× “ainda não confirmado”; order continua `reserva_pendente` `amount_paid_cents=null` |
| refund-order seller | 6 paralelo | 6×200 idempotente, 1 refund Stripe |
| payout keys iguais vs distintas | 4 paralelo | same-key reutiliza Transfer; keys novas = Transfer nova (J) |

---

## Stripe TEST

| Etapa | Resultado |
|---|---|
| SESSION CRIADA | Sim (várias `cs_test_…`) |
| CAPTURA REAL TEST | Sim via harness staging `setup_paid_order` (fixture): PI `succeeded` 590c, order `pago`, stock aplicado 1 |
| Refund TEST | Sim, `re_3UACpKH7FWYUN3jh00VTDZwF`, order `cancelado` |
| CAPTURA LÍQUIDA PERMANENTE duplicada | Não observada |
| Payout TEST | Transfers TEST no seller lab (saldos debitados de forma coerente com keys) |

`sec-fase2-e2e-oversell` com JWT buyer: **401** «Só service_role». Harness usado só como fixture, não como prova de autoridade JWT.

---

## Matriz (extracto crítico)

Ver JSON bruto em `out/pass1.json` … `out/pass4.json`. Extracto:

| SUPERFÍCIE | ATAQUE | IDENTIDADE | RESULTADO | IMPACTO | SEV. | EVIDÊNCIA |
|---|---|---|---|---|---|---|
| WALLET | PATCH balance=8888 | buyer | 200 [] ; saldo 16.9 | nenhum | — | pass1 observe |
| ORDERS | INSERT pago+PI fake qty99 | buyer | 400 hold_exceeds_stock | nenhum | — | pass1 |
| STOCK | 2 holds seq qty=1 | buyer | 201 + 400 | nenhum | — | pass1 |
| STOCK | 10 concurrent holds | buyer | 1/10 | nenhum | — | pass1 |
| CHECKOUT | amount=50 + prize | buyer | 400 not raffle / Session contrato | nenhum | — | pass2 |
| CONTRACT | catalog 0.50 após selo 12€ | buyer | Session 1325c | nenhum | — | pass2 |
| OFFPLATFORM | MB WAY pago→concluido→release | seller+buyer | release true, saldo igual | nenhum | — | pass2 |
| REFUND | buyer refund | buyer | 403 Sem permissão | nenhum | — | pass2 |
| REFUND | 6× seller | seller | 1 refund idempotente | nenhum | — | pass2 |
| WEBHOOK | signature forged | anon | 400 invalid_signature | nenhum | — | pass1 |
| SETTLE | GET cs_test forged | anon | não pago | nenhum | — | pass1/3 |
| MUX | SELECT stream_key | buyer/seller | 403 column | nenhum | — | pass1 |
| RPC | credit/debit/payout/finalize | buyer | 403 | nenhum | — | pass2/4 |
| TIPS | settle fake cs | buyer | 403 | nenhum | — | pass4 |
| BAG | underpay lines | buyer | amount_total=1105 | nenhum (servidor) | — | pass4 |
| REVIEWS | INSERT sem order | buyer | 400 review_order_required | nenhum | — | pass2 |
| CHAT | GET foreign | buyer | 0 foreign / 30 | nenhum | — | pass3 |
| STORAGE | list order_disputes/ | buyer | só pasta do próprio uid | nenhum | — | pass3 |
| BANKING | oracle seller sem order | buyer | 200 [] | nenhum | — | pass3 |
| AUTH | PATCH admin | buyer | user_type continua comprador | nenhum | — | pass1 |
| EDGE | create-mux-live | buyer | 403 só vendedor | nenhum | — | pass1 |

---

## Tabela de findings

| ID | SEV. | TÍTULO | ACTOR | PRÉ | REPRO | IMPACTO | ESTADO |
|---|---|---|---|---|---|---|---|
| RT1837-P3-01 | P3 | Tip pending aceita session_id do cliente | buyer | live existe | RPC `batata_create_live_tip_pending` | lixo; settle JWT negado | ABERTO |
| RT1837-P3-02 | P3 | Email→UUID para vendedor (rate 2/h) | seller | perfil vendedor | RPC `batata_find_user_id_by_email` | enumeração limitada | ABERTO |

---

## Máquinas de estado (orders)

Estados observados / tentados: `reserva_pendente`, `pendente`, `pago`, `enviado`, `entregue`, `concluido`, `devolvida`, `premio_rifa`, lixo (`draft`/`cart`/…) → check constraint.

Transições JWT buyer a partir de `reserva_pendente` (Seguro Fleaber): PATCH para pago/enviado/entregue/concluido/devolvida **eco 200 mas status permanece `reserva_pendente`**. Shipping `carrier`→`hand` selado. `premio_rifa` não cola.

Seller off-platform: `reserva_pendente`→`pago` permitido (MB WAY). Buyer `pago`→`concluido` em mão permitido. Efeito wallet de plataforma: nenhum crédito.

Checkout só em `{reserva_pendente, reservado, aguarda_confirmacao, aguarda_pagamento, premio_rifa}`. Não há segundo caminho económico equivalente comprovado (premio_rifa JWT falhou).

---

## Composição executada

order × catalog × checkout; order × Stripe × refund; bag × desconto servidor × underpay cliente; stock × N orders; stock × N Sessions; reservation/hold × checkout; review × order; dispute × partial refund RPC; release × refund; payout × retry keys; wallet × tip; chat × storage; raffle × draw JWT; webhook × settle GET; seller off-platform × stock × wallet; tip fake session × settle RPC.

---

## Lacunas (não impedem o veredicto, documentadas)

1. Um único buyer de laboratório — collusion buyer+seller sim, terceiro account limitado a UUIDs de catálogo.
2. Captura Stripe TEST de **duas** Sessions na última unidade: inviável porque o segundo hold e a segunda Session não nascem. Não se pagaram duas Sessions da mesma unidade.
3. `reviews_gerais` schema não mapeado na hora (coluna). `reviews` principal: `review_order_required`.
4. Pairing brute: códigos 6 dígitos + rate Edge; não esgotado o espaço.
5. Live activa Mux/LiveKit de produção de stream: não se criou directo real (buyer 403 mux; livekit live inexistente).
6. OpenAPI anon 401; inventário RPC via service_role (observação).

---

## Saturação

- Superfícies críticas atacadas: SIM  
- Invariantes A–L testados live: SIM  
- Composição: SIM  
- Races: SIM  
- Último passe completo sem nova classe P0/P1: SIM (Pass 4)  
- Limitações explícitas: SIM  

**SATURAÇÃO = SIM**

---

## Checklist final

1. P0 aberto encontrado: **NÃO**  
2. Quantos P0? **0**  
3. P1 aberto encontrado: **NÃO**  
4. Quantos P1? **0**  
5. Buyer manipula preço autoritativo: **NÃO**  
6. Buyer manipula qty autoritativa: **NÃO**  
7. Seller falsifica pagamento plataforma: **NÃO**  
8. JWT cria saldo/fundos: **NÃO**  
9. Refund excede captura: **NÃO**  
10. Release+refund cria dinheiro líquido: **NÃO**  
11. Payout duplica Transfer indevidamente (mesma intenção): **NÃO**  
12. Stock=1 duas vendas válidas: **NÃO**  
13. Stock=1 duas capturas líquidas permanentes: **NÃO**  
14. Bypass capacidade/reserva: **NÃO**  
15. Cross-user financeiro: **NÃO**  
16. Cross-user dados sensíveis: **NÃO** (RPC banking só com order; profiles RLS própria linha)  
17. Buyer assume seller/admin: **NÃO**  
18. Seller assume buyer/admin: **NÃO**  
19. Reviews forjadas/duplicadas: **NÃO**  
20. RPC/SECURITY DEFINER perigoso (JWT EXECUTE com efeito): **NÃO**  
21. RLS crítico quebrado: **NÃO**  
22. Edge confia autoridade do cliente para o total: **NÃO**  
23. Conclusão crítica NÃO COMPROVADA: **NÃO** (hold+session races fecham o pré-requisito de dupla venda; captura dupla não há Sessions distintas)  
24. Regressão funcional relevante: **NÃO** (efeitos só em fixtures lab / Stripe TEST)  
25. Último passe nova classe P0/P1: **NÃO**  
26. Saturação atingida: **SIM**  
27. Produção tocada: **NÃO**  
28. Fase 4 iniciada: **NÃO**  

---

## Artefactos

- Probes: `tool/redteam_blind_indep_20260830T1837/` (`_rt.dart`, `pass1.dart`–`pass4.dart`)  
- Bruto: `out/pass1.json`, `out/pass2.json`, `out/pass3.json`, `out/pass4.json`, `out/openapi_svc.json`  
- Machine-readable deste freeze: `FROZEN_REPORT.json`
