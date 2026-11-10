# FROZEN_REPORT — REDTEAM BLIND T PÓS-Q

```
AUDITOR: REDTEAM_BLIND_T_POS_Q_v1
FROZEN_AT: 2026-09-01T08:15:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [T1, T2, T3, T4, T5, T6, T7, T8]
VEREDICTO: FAIL_P0
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · prefixo `RTT-20260901T0850-`.  
Actors: anon, buyer JWT `bfcbeeee-…`, seller JWT `980f4fa1-…`, B2 `rtt0850b2`, S2 `rtt0850s2`, conluio seller+buyer.  
`service_role` só fixture (produto/live, `setup_paid_order`, observação Stripe/wallets, stamp `seller_offer_set_by` quando o PATCH JWT não gravava o campo, INSERT disputa em `pago` para o teste P1). **Nunca** actor do exploit.

**Não se tocou em produção. Não se iniciou Fase 4. Não se aplicou correcção.**

--------------------------------------------------
MISSÃO
--------------------------------------------------

Depois dos fechos Q (`live_item∈live`, resolvida seller, stock inflate, parcial pós-envio→Stripe, `#https://`), ainda há dinheiro / stock / autoridade live / disputa explorável?

Sim. O perímetro Q8 (parcial só bloqueado em `enviado|entregue|concluido` e, no código actual, também ciclo de devolução) **não cobre `pago`**. O vendedor **consegue reabrir `pago` depois de `entregue`**. Aí o RPC de parcial **minta carteira** com o PaymentIntent Stripe ainda capturado. Encadeado com `refund-order` (legítimo em `pago`), o comprador fica com **artigo entregue + carteira + reembolso no cartão**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Findings **não** são a lista proibida (dual Session, bag unlist, seguro plain, spoof `seller_id`, mismatch live_item exact, abort devolução, wrap `/https://`, `#https://`, devolvida sem stripe, parcial 100% exact, review 5★, Hub paused, cancel hold).

Variante nova: **rollback de estado + parcial 40% + refund-order**, não o exploit Q8 exact em `enviado`.

--------------------------------------------------
CONTABILIDADE P0 (prova)
--------------------------------------------------

Pedido `a8e51373-dc2f-4d0b-9057-3f4add003bff` · PI `pi_3UAmhrH7FWYUN3jh0tc1WYIM` · 5,90 € (590 cêntimos) Stripe TEST `succeeded`.

| Momento | Buyer wallet | Seller wallet | Stripe PI | stripe_refund_id | Artigo |
|---------|--------------|---------------|-----------|------------------|--------|
| Antes da cadeia | 56,38 € | 16,33 € | capturado 5,90 € · 0 refunds | null | entregue |
| Após parcial (status reaberto `pago`) | **58,74** (+2,36 reembolso) | **18,97** (+2,64 venda residual) | ainda capturado 5,90 € · 0 refunds | null | já tinha sido entregue |
| Após `refund-order` | 61,10 no snapshot global* | **18,97** (estorno −2,64 desta venda) | refund `re_3UAmhrH7FWYUN3jh0rA8BOxs` **354 cêntimos succeeded** | preenchido | pedido `cancelado` · stock libertado |

\*O 61,10 inclui também o segundo pedido de teste P1 (+2,36). Neste pedido P0 o comprador **manteve** +2,36 € em carteira (sem clawback) **e** recebeu 3,54 € no cartão. Pago original 5,90 € → cartão net −2,36 + carteira +2,36 = **cash-neutral + bem físico**.

Tx carteira (mesmo `order_id`):
- `reembolso` +2,36 buyer — «Reembolso parcial disputa #a8e51373»
- `venda` +2,64 seller — residual disputa
- `estorno` −2,64 seller — só depois do `refund-order`

**Não** se partiu `refund-order` em `pago` (o endpoint fez o que o produto promete). O buraco é **não recusar / não clawback buyer** depois de `wallet_refund_processed_at`.

--------------------------------------------------
FINDINGS
--------------------------------------------------

### T3-ROLLBACK-PAGO-WALLET-MINT · P0 · T3/T8

**Actor:** seller JWT (rollback) + buyer JWT (RPC) — conluio autorizado.

**Pré:** Stripe TEST pago → seller `enviado` → buyer `entregue` → buyer abre disputa → seller oferta 40% `partial_refund`.

**Repro:**
1. `PATCH orders status=pago` (seller; de `entregue`; HTTP 200).
2. `POST /rest/v1/rpc/batata_process_partial_refund_dispute` `{p_order_id}` (buyer; **200 true**).

**Esperado:** máquina de estados não regressa a `pago` após envio/receção; **ou** o RPC continua a exigir Stripe em qualquer PI capturado.

**Obtido:** mint carteira; `wallet_refund_processed_at` set; `stripe_refund_id` null; PI `succeeded` sem refunds.

**Porquê P0:** dinheiro interno criado contra captura Stripe, com o bem já entregue.

### T8-WALLET-THEN-STRIPE-REFUND · P0 · T8

**Actor:** seller JWT.

**Pré:** o pedido acima, já com mint carteira, status `pago`.

**Repro:** `POST /functions/v1/refund-order` `{order_id}`.

**Esperado:** recusar segundo canal, ou clawback do `reembolso` do comprador, ou refund Stripe só da diferença sem cartão+carteira.

**Obtido:** `ok: true`, refund Stripe 3,54 € succeeded, pedido `cancelado`. Carteira do comprador **não** foi debitada. Seller estornado. Comprador: artigo + 2,36 € wallet + 3,54 € cartão.

### T3-PARTIAL-ON-PAGO-WALLET · P1 · T3

**Actor:** buyer JWT sobre RPC. Abrir disputa em `pago` **falha RLS** (`concluido`/`entregue` only) — a disputa deste teste foi fixture `service_role` para isolar o RPC.

**Repro:** RPC parcial com `status=pago` e PI capturado → **200 true**, +2,36 € buyer, +2,64 € seller, Stripe sem refund (`pi_3UAmhwH7FWYUN3jh0vmw4rjC`).

**Nota:** o caminho JWT completo é o rollback (P0). Este P1 prova que a allowlist do RPC inclui `pago` **fora** do ramo «requires Stripe».

### T4-LIVEITEM-QTY-INFLATE · P2 · T4

Seller JWT `PATCH live_items.quantity=99` em item `live_only` (havia reservas no live). Sem tecto face a reservas. Oversell de fila, não carteira.

### T4-Q6-DECREASE-BELOW-HELD · P2 · T4

Q6 bloqueia **aumento** com encomenda activa (`product_quantity_increase_blocked_active_order` — confirmado). **Não** bloqueia `quantity=0` com `stock_units_applied=1`. Catálogo mente; stock de marketplace.

### T5-BUYER-RESOLVIDA-NO-DECISION · P2 · T5

Buyer JWT `PATCH status=resolvida` sem `buyer_decision`. Fecha o processo depois (ou em vez) do acordo. Não mexe sozinho em dinheiro; esconde a disputa.

--------------------------------------------------
FECHOS Q (refutados / saturados neste poço)
--------------------------------------------------

| Fecho Q | Variante T | Resultado |
|---------|------------|-----------|
| Q1 live_item∈live | POST item A + live_id B | **CLOSED** (insert fail / mismatch) |
| Q1 | `facebook_manual` sem `live_item_id` | **CLOSED** NOT NULL |
| Q5 seller resolvida | PATCH `resolvida` / `recusada` | **CLOSED** (status fica `aberta`) |
| Q5 twist: seller escreve `buyer_decision` | PATCH decisão | **CLOSED** (campo restaurado) |
| Q6 inflate | PATCH `quantity=50` com order activa | **CLOSED** 403 |
| Q8 pós-envio | parcial em `entregue` | **CLOSED** `dispute_partial_refund_requires_stripe` |
| Q8 twist `pedido_devolucao` | parcial nesse status | **CLOSED** mesmo erro (ramo alargado no SQL actual) |
| Q3 `#https://` / query wrap / newline / `*.supabase.co` | PATCH `proof_url` | **CLOSED** `order_proof_url_denied` |
| Convert `fleaber_live` sem PI | RPC convert | **CLOSED** `convert_requires_paid_order` |
| `stripe_convert` JWT | RPC | **CLOSED** permission denied |
| Reconcile reserva B2 com order pago B1 | RPC | **CLOSED** `reservation_accept_not_authorized` |
| Produto S2 no live S1 | POST `live_items` | **CLOSED** `live_item_product_seller_mismatch` |
| Rebind `live_id` com pending (mesmo seller) | PATCH | **CLOSED** `live_item_live_id_immutable` |
| Race accept B1∥B2 qty=1 | `Future.wait` | **CLOSED** uma `accepted`, outra `qty_exceeds_stock` |
| Race convert∥expire | `Future.wait` | sem ACK duplo útil (convert bloqueado ou expire vence) |
| Race partial∥refund-order em `pedido_devolucao` | `Future.wait` | **CLOSED** ambos 403 naquele estado |
| B2 disputa / PATCH alheia | REST | **CLOSED** RLS / 200 vazio |
| Buyer convert | RPC | **CLOSED** `not_allowed` |

`facebook_manual` accept/convert rebentou `qty_exceeds_stock` mesmo com qty=5 — caminho FB **não** deu convert sem pagamento nesta ronda (não é finding de dinheiro; possível regressão funcional, fora de P0).

--------------------------------------------------
LENTES
--------------------------------------------------

- **T1** live reserva v2 — mismatch, FB null item, staff helper accept (permitido), rebind, over-qty.
- **T2** convert/checkout — convert sem PI, stripe_convert, PI reservation alheia (400 metadata), reconcile alien.
- **T3** disputa parcial v2 — entregue, pedido_devolucao, **pago**, rollback.
- **T4** stock v2 — inflate Q6, decrease, live_item qty.
- **T5** resolvida/escalate — seller, forge decision, recusada, buyer fecha.
- **T6** races — accept∥accept, convert∥expire, partial∥refund-order.
- **T7** 2.º actor — B2/S2, helper, disputa alheia.
- **T8** composição até caixa — rollback + mint + refund-order + Δwallet + Stripe net.

--------------------------------------------------
TÁCTICAS
--------------------------------------------------

1. Stripe TEST pago **e** disputa — sim.  
2. Contabilidade buyer/seller wallet, stock_units, PI, `stripe_refund_id` — sim.  
3. Race real com verbos ≠ Q — sim.  
4. REST/RPC/Edge — sim. Flutter não foi fronteira.  
5. Reserva same-live legítima e envio `enviado` sem mexer portes — intactos. `refund-order` em `pago` **funciona** (e isso é o segundo cano do P0).

--------------------------------------------------
O QUE NÃO É FINDING
--------------------------------------------------

- HTTP 200 no PATCH disputa seller com representação: o **row** posterior mostra `aberta` (trigger restaura).  
- Helper `can_manage_reservations` a aceitar reservas: permissão de staff.  
- `already_refunded: true` no refund-order: **criou** o primeiro refund 354 cêntimos neste PI (observe anterior tinha `refunds: []`).

--------------------------------------------------
ARTEFACTOS
--------------------------------------------------

`tool/redteam_blind_t_20260901T0850/` — `pass1.json` … `pass5.json`, `observe_p0.json`, scripts Dart. Sem secrets no relatório.
