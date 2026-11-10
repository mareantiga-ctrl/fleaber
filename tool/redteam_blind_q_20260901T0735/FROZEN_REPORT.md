# FROZEN_REPORT — REDTEAM_BLIND_Q_POS_NOP_v1

```
AUDITOR: REDTEAM_BLIND_Q_POS_NOP_v1
FROZEN_AT: 2026-09-01T07:45:12+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [Q1, Q2, Q3, Q4, Q5, Q6, Q7, Q8]
VEREDICTO: FAIL_P0
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · prefixo `RTQ-20260901T0735-` · `service_role` só fixture/observação/cleanup.

**Missão:** depois dos fechos NOP+O34, ainda há dinheiro, stock, autoridade live, ou estado de disputa/devolução que a UI esconde?

**Resposta:** sim. O fecho O3 (`order_devolvida_requires_refund`) e O4 (`dispute_full_refund_requires_stripe` a 100%) aguentam. O fecho Q8/pós-envio **não** cobre o caminho `pedido_devolucao`: `batata_process_partial_refund_dispute` minta carteira comprador+vendedor com PaymentIntent Stripe ainda capturado e `stripe_refund_id` vazio.

--------------------------------------------------
ÂMBITO · TÁCTICAS
--------------------------------------------------

| Táctica | Feito |
|---|---|
| ≥1 Stripe TEST pago + disputa ou live reserva | 5 PI `succeeded` (pass2×2, pass3×3) + reservas live |
| Contabilidade fechada | buyer/seller wallet · stock_units · PI · stripe_refund_id |
| ≥1 race `Future.wait` verbos ≠ N/O | `process_partial ∥ refund-order`; `recusada ∥ process_partial`; `accept ∥ PATCH lives` |
| Flutter ≠ fronteira | REST / RPC / Edge |
| Fluxos legítimos | seller `enviado` OK; `refund-order` após oferta 100% em `entregue` recusado pelo gate de estado (não é bypass) |

Cegueira: código actual, SQL, RLS, Edge, schema LIVE. Sem relatórios K–P.

--------------------------------------------------
FINDINGS
--------------------------------------------------

## P0 — RTQ-Q8-partial-wallet-mint-on-return-path
**Lentes:** Q8 · Q3 · Q4

**Título:** `process_partial` em `pedido_devolucao` minta carteira sem refund Stripe (PI capturado).

**Actor:** buyer JWT (oferta 40% escrita pelo seller).

**Pré:** Stripe TEST `setup_paid_order` → seller `enviado` → buyer `entregue` → INSERT disputa → seller oferta `partial_refund` 40% → buyer `pedido_devolucao`.

**Repro:**
```
POST /rest/v1/rpc/batata_process_partial_refund_dispute
  { "p_order_id": "<oid>" }
Authorization: Bearer <buyer>
```
Em paralelo (Q4): `POST /functions/v1/refund-order` seller — 403 `order_refund_blocked_status` (já enviada). A mint **não** precisa da race; a race só mostrou que o refund Stripe está fechado neste estado.

**Esperado (fecho Q8 / O4):** `dispute_partial_refund_requires_stripe` ou equivalente; sem Δwallet enquanto `stripe_refund_id` vazio e PI capturado pós-envio.

**Obtido (persistido na observação pass4):**

| Superfície | Valor |
|---|---|
| order | `fe8256e6-a1eb-418b-a97f-1184c7e42b08` |
| status | `pedido_devolucao` |
| PI | `pi_3UAlNgH7FWYUN3jh1Rfvhw6w` succeeded · `amount_paid_cents=590` |
| `stripe_refund_id` | **null** |
| `wallet_refund_processed_at` | `2026-09-01T06:41:20Z` |
| `wallet_release_processed_at` | mesmo instante |
| `stock_units_applied` | 1 (item continua “do” comprador) |
| Δ buyer wallet | **+2.36** `reembolso` (51.66 → 54.02) |
| Δ seller wallet | **+2.64** `venda` residual (11.05 → 13.69) |
| RPC | `200 true` |

O guard Q8 só exige Stripe se `status ∈ (enviado, entregue, concluido)`. `pedido_devolucao` / `em_devolucao` / `devolucao_entregue` / `disputa_devolucao_vendedor` **não** entram. O3 bloqueia `devolvida` sem refund — o dinheiro já saiu **antes** de chegar a `devolvida`.

**Porquê P0:** movimento de dinheiro irreversível (créditos wallet) contra PI capturado sem `stripe_refund_id`. Plataforma fica a dever 5,00 € em carteiras com 5,90 € ainda no Stripe; vendedor é pago em wallet com o artigo ainda no comprador.

**Não é o clássico** «devolvida sem stripe»: o PATCH `devolvida` neste mesmo arco deu `order_devolvida_requires_refund`. Variante = rail wallet no estado de devolução.

---

## P1 — RTQ-Q5-seller-forge-buyer-decision-resolvida
**Lente:** Q5

**Título:** vendedor forja `buyer_decision` e fecha `resolvida` no mesmo PATCH.

**Actor:** seller JWT.

**Pré:** Q5 reverte `status=resolvida` se `buyer_decision` não está na allowlist — mas lê `NEW.buyer_decision` na mesma row.

**Repro:**
```
PATCH /rest/v1/order_disputes?id=eq.<did>
{ "buyer_decision": "accepted_partial_refund", "status": "resolvida" }
```

**Esperado:** `buyer_decision` imutável para o vendedor; sem salto a `resolvida`.

**Obtido:** disputa `1673ab1f-f565-4c5d-b585-b83251a7eaef` · `status=resolvida` · `buyer_decision=accepted_partial_refund` · `current_turn=administracao`. PATCH só `status=resolvida` **não** bastou (Q5 clássico fechado); a variante no mesmo request passa.

Efeito: disputa morta na API; comprador perde FSM; encomenda pode continuar `pedido_devolucao` (desync UI/API). Sem mint extra neste ramo (oferta nula após fecho).

---

## P1 — RTQ-Q5-seller-recusada-unilateral
**Lentes:** Q5 · Q4

**Título:** vendedor PATCH `recusada` sozinho (estado terminal permitido pelo CHECK, fora do if Q5 que só olha `resolvida`).

**Actor:** seller JWT.

**Repro:** `PATCH order_disputes status=recusada`

**Obtido:** disputa `33773d4b-dd8a-446c-85b1-5743c7c0884e` · `status=recusada` · `current_turn=administracao` · oferta 50% ainda visível mas `process_partial` → `dispute_refund_offer_required` (exclui `recusada`). Race `recusada ∥ process_partial`: mint 0 (mutex informal a favor do fecho).

**Loot:** autoridade — o vendedor mata a disputa sem decisão do comprador.

---

## P1 — RTQ-Q1-live-item-foreign-product-accept
**Lentes:** Q1 · Q7

**Título:** 2.º vendedor aponta `live_items.product_id` ao SKU da vítima e aceita reserva (capacidade lida do stock alheio).

**Actor:** seller2 JWT + buyer JWT.

**Pré:** `seller_id` na reserva é forçado ao dono da **live** (N-P0). `live_item_id` tem de pertencer ao `live_id` (Q1 item∈live). Nenhum guard exige `product_id.seller_id = live.seller_id`.

**Repro:**
```
PATCH live_items?id=eq.<item_atacante> { product_id: <sku_vítima>, item_kind: marketplace_product }
POST live_reservation_requests … live_id=atacante, live_item_id=item_atacante
rpc batata_process_live_reservation_request accept  (seller2)
```

**Obtido:** reserva `b1de1706-437f-40be-a2a2-e5625f058d40` `accepted` qty=2 · RPC `item_qty: 5` (quantity do produto vítima) · `products.quantity` vítima **permanece 5**. Checkout `create-payment-intent` neste probe: 400 metadata (sem PI extra).

**Não é** spoof `seller_id=accepted`. Variante = catálogo cruzado. Sem Δwallet; autoridade live + tecto de stock lido de SKU alheio.

---

## P2 — RTQ-Q3-label-query-wrap-on-terminal
**Lente:** Q3

**Título:** `return_label_url` `https://fleaber.app/l?next=https://evil.test/steal` persiste em disputa já `resolvida`.

**Actor:** seller JWT.

**Pré:** allowlist `https://fleaber.app/%`; regex Q3 pega `#https://` e `https://…/https://`. Query `?next=` passa. O freeze terminal **não** reverte `return_label_url`.

**Obtido (pass4):** `return_label_url` exactamente esse URL na disputa `1673ab1f-…`.

`proof_url` com `#https://` → `order_proof_url_denied`. Variante ≠ wrap path clássico.

Sem loot directo (higiene / open-redirect em domínio allowlist).

--------------------------------------------------
SATURAÇÃO (não-finding · prova de fecho)
--------------------------------------------------

### Q1 / N-P0
- INSERT `accepted` + `seller_id=self` → 201 mas `seller_id` reescrito para o dono da live; status `pending`.
- `live_item` de live A em `live_id` V → `live_item_live_mismatch`.
- Buyer PATCH `accepted`+qty → 200 `[]`; row continua `pending`.
- `facebook_manual` accepted → forçado `pending`.

### Q2
- `complete-mux-live` buyer/seller2/anon → 403/401 «Sem permissão».
- `livekit-mux-publish` `token` / `egress` / `stop_egress` alheio → 403.
- PATCH `lives` ended → `permission denied for table lives`.
- INSERT clone `mux_live_id` → 403.
- SELECT `mux_stream_key` / `mux_live_id` JWT/anon → 403/401 (coluna/tabela).
- Live vítima permaneceu `status=live is_active=true`.

### Q3 / O3 / O4
- PATCH `devolvida` directo e ciclo `pedido_devolucao→…→devolvida` → `order_devolvida_requires_refund`.
- `stripe_refund_id` fake / flip `payment_method` → `order_money_fields_immutable`.
- Aliases `returned`/`refunded`/`devolvido` → CHECK `orders_status_batata_check`.
- `process_partial` 100% em `entregue` → `dispute_full_refund_requires_stripe`.
- `proof_url` fragmento `#https://` → `order_proof_url_denied`.

### Q6
- PATCH `products.quantity=99` com ordem activa → `product_quantity_increase_blocked_active_order`.
- Relist pós `refund-order` bloqueado (refund também bloqueado em `entregue`).

### Q7
- RPC accept/convert buyer2/seller2 → `not_allowed` / `permission denied` `stripe_convert`.
- buyer2 PATCH disputa → 200 `[]`.
- buyer2 INSERT disputa → `dispute_already_exists_for_order` (não RLS leak de encomenda alheia neste caso).

### Q4 races sem loot extra
- `accept ∥ PATCH live ended`: accept OK (dono); PATCH lives 403 (tabela). Não é hijack.
- `refund-order` em `pedido_devolucao`/`entregue`: 403 `order_refund_blocked_status` — bind de produto, não double-Stripe.

### Legítimo
- Seller `enviado` a partir de `pago` (mão) funciona.
- `refund-order` após oferta 100% **em entregue** recusado pelo gate de envio — o caminho Stripe 100% não está disponível pós-envio; o único rail que correu foi wallet em `pedido_devolucao` (P0 acima).

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Findings ≠ lista clássica (dual session, bag unlist, seguro plain, resolve handle, mux draft, cancel hold, review 5★, Hub paused, seller PATCH `resolvida` sozinho, spoof `seller_id` accepted, abort `pedido_devolucao→enviado`, proof evil / label wrap path, `devolvida` sem stripe).

Variantes novas: rail wallet em `pedido_devolucao`; forge `buyer_decision`+`resolvida`; `recusada` unilateral; `product_id` cruzado; label `?next=`.

--------------------------------------------------
VEREDICTO
--------------------------------------------------

**FAIL_P0** — o fecho NOP+O34 segura spoof live `seller_id`, stop/publish alheio, `devolvida` sem Stripe e parcial 100% sem Stripe. **Não** segura o caminho disputa→`pedido_devolucao`→`process_partial` &lt; 100%: carteiras creditadas, PI capturado, `stripe_refund_id` null. Q5 ainda salta FSM se o vendedor escrever a decisão do comprador no mesmo PATCH.

**Não corrigir. Não tocar produção. Fase 4 não iniciada.**

Evidência: `tool/redteam_blind_q_20260901T0735/pass{1,2,3,4}.json`
