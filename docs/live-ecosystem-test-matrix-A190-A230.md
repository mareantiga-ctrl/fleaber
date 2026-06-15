# Matriz expandida — A190 a A230

**Área:** Saco da live · checkout · pagamentos · rifa (checkout-adjacent)  
**Versão:** 1.0 · **2026-06-14**  
**Estado:** Fichas expandidas — **sem implementação de testes**.

Substitui a tabela compacta A190–A230 em `live-ecosystem-test-matrix.md`.

**Nota:** A211–A218 são rifa no âmbito do checkout pós-pagamento; A219–A230 fecham pagamentos/encomendas/wallet.

---

## A190 — Abrir saco da live

| Campo | Valor |
|-------|-------|
| **ID** | A190 |
| **Nome** | Sheet «Saco da live» abre com secções |
| **Pré-condições** | Live `status=live` ou `ended`; comprador autenticado; ≥1 reserva histórica ou vazia |
| **Passos** | 1. Entrar player (`live_id`) 2. Tocar «Saco da live» (sidebar ou CTA) 3. Ver sheet |
| **Resultado esperado** | `LiveBagSheet` abre; secções visíveis conforme estado; sem navegar para PDP |
| **Componentes afectados** | `live_bag_sheet.dart`, `fleaber_live_player_widget.dart` (`_openLiveBagSheet`) |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | `live_id`, buyer JWT |
| **Validar BD** | Opcional: `count(*) from live_reservation_requests where live_id=$id and buyer_id=$buyer` |
| **Validar UI** | Texto «Saco da live»; sheet modal; botão fechar |
| **Risco de regressão** | Alto — entry point de todo checkout |
| **Dependências** | A145 (entrar player); — |

---

## A191 — Secção «No saco» (pending / in bag)

| Campo | Valor |
|-------|-------|
| **ID** | A191 |
| **Nome** | Linhas pending no saco com metadata correcta |
| **Pré-condições** | Reserva `status=pending`; `source=fleaber_live` |
| **Passos** | 1. Reservar artigo 2. Abrir saco 3. Localizar secção in-bag |
| **Resultado esperado** | Linha com título/ref, qty, chip posição (#1 se aplicável), estado «Pendente»; botão Pagar se `buyerCanPayBagReservation` |
| **Componentes afectados** | `live_bag_sheet.dart`, `live_reservation_queue_service.dart` (`buyerBagDisplayRequests`) |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro + Bot |
| **Dados necessários** | `live_reservation_requests` pending |
| **Validar BD** | `status='pending'`, `requested_qty`, `queue_position` |
| **Validar UI** | Secção correcta; foto miniatura se existir |
| **Risco de regressão** | Alto — A1 histórico (Pagar sumiu) |
| **Dependências** | A148 (criar reserva); A190 |

---

## A192 — Secção waitlist / «Espera #N»

| Campo | Valor |
|-------|-------|
| **ID** | A192 |
| **Nome** | Reserva em fila quando stock cheio |
| **Pré-condições** | Stock grosso esgotado por aceites; nova reserva permitida (BATATA waitlist) |
| **Passos** | 1. Esgotar stock com aceite 2. Segundo comprador reserva 3. Abrir saco |
| **Resultado esperado** | Chip «Espera #N» ou secção waitlist; **sem** badge ESGOTADO só por pending |
| **Componentes afectados** | `live_bag_sheet.dart`, `isWaitlistPosition` / `isWaitlistUnit` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | 2 buyers; stock 1; 1 aceite |
| **Validar BD** | 2 pending; `queue_position` distinto |
| **Validar UI** | Label Espera; cor âmbar (A2) |
| **Risco de regressão** | Alto — A2 chips posição |
| **Dependências** | A133, A150; A081 (aceite) |

---

## A193 — Secção «Comprado» (converted)

| Campo | Valor |
|-------|-------|
| **ID** | A193 |
| **Nome** | Histórico converted no saco |
| **Pré-condições** | Reserva `status=converted` ligada a order `pago` |
| **Passos** | 1. Completar pagamento 2. Reabrir saco |
| **Resultado esperado** | Secção purchased; chip «Comprado ✓»; sem botão Pagar |
| **Componentes afectados** | `live_bag_sheet.dart`, `buyerBagRejectedLabel` / status labels |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration |
| **Dados necessários** | converted + order pago |
| **Validar BD** | `live_reservation_requests.status='converted'`; `orders.status` pago |
| **Validar UI** | Chip verde/comprado |
| **Risco de regressão** | Médio — confusão com aceite |
| **Dependências** | A206 ou A209 |

---

## A194 — Secção cancelada (`bag_removed`)

| Campo | Valor |
|-------|-------|
| **ID** | A194 |
| **Nome** | Cancelamento comprador no saco |
| **Pré-condições** | Reserva pending ou accepted |
| **Passos** | 1. Comprador remove do saco 2. Reabrir saco |
| **Resultado esperado** | Secção cancelled; label `buyerBagRejectedLabel`; vendedor sem Aceitar (A085) |
| **Componentes afectados** | `batata_live_bag_remove_request`, `live_bag_sheet.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro + Integration |
| **Dados necessários** | buyer, reserva id |
| **Validar BD** | `status='rejected'`, notes `bag_removed` |
| **Validar UI** | Secção cancelados; sem Pagar |
| **Risco de regressão** | Médio — doc #4 |
| **Dependências** | A191; A230 |

---

## A195 — Checkout sheet com checkboxes multi-linha (R20)

| Campo | Valor |
|-------|-------|
| **ID** | A195 |
| **Nome** | Seleccionar linhas a pagar no saco |
| **Pré-condições** | ≥2 reservas payable (pending ou accepted) mesmo ou diferentes refs |
| **Passos** | 1. Saco → Pagar 2. `LiveBagCheckoutSheet` 3. Toggle checkboxes 3. Ver total |
| **Resultado esperado** | Checkboxes por linha/agregado; total recalcula; CTA pagar desactivado se nenhuma seleccionada |
| **Componentes afectados** | `live_bag_checkout_sheet.dart`, `mergePayableByLiveItem` |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | 2+ payable rows |
| **Validar BD** | — |
| **Validar UI** | Checkboxes visíveis; totais artigos+portes+seguro |
| **Risco de regressão** | Alto — R20 FAIL histórico |
| **Dependências** | A191, A153 |

---

## A196 — Miniaturas no checkout (R20 fotos)

| Campo | Valor |
|-------|-------|
| **ID** | A196 |
| **Nome** | Fotos dos artigos nas linhas do checkout |
| **Pré-condições** | `live_items` com `image_url` ou produto com foto |
| **Passos** | 1. Abrir checkout sheet 2. Ver cada linha |
| **Resultado esperado** | `BatataCachedImage` por linha; placeholder se sem foto |
| **Componentes afectados** | `live_bag_checkout_sheet.dart`, `live_in_stream_checkout.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | item com imagem |
| **Validar BD** | `live_items.image_url` not null |
| **Validar UI** | Thumbnail ≠ ícone vazio |
| **Risco de regressão** | Médio |
| **Dependências** | A195 |

---

## A197 — Uma ref, qty agregada no checkout (#6)

| Campo | Valor |
|-------|-------|
| **ID** | A197 |
| **Nome** | Duas reservas mesma ref → 1 linha qty 2 |
| **Pré-condições** | 2 pending mesma `live_item_id` OU increment qty (R6) |
| **Passos** | 1. Reservar/incrementar qty 2 2. Pagar 3. Inspeccionar sheet + metadata Stripe |
| **Resultado esperado** | `mergePayableByLiveItem` → 1 linha `requested_qty=2`; 1 order ou metadata agregada |
| **Componentes afectados** | `live_bag_checkout_sheet.dart`, edge `create-payment-intent` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | 1 live_item, qty 2 |
| **Validar BD** | 1 ou 2 orders conforme design; metadata `bag_lines` qty total 2 |
| **Validar UI** | Sheet mostra qty 2 |
| **Risco de regressão** | Alto — R6/R31 |
| **Dependências** | A149; A198 |

---

## A198 — Duas refs, metadata compacta (#6)

| Campo | Valor |
|-------|-------|
| **ID** | A198 |
| **Nome** | Checkout saco multi-ref — POST create-payment-intent |
| **Pré-condições** | 2 refs diferentes payable |
| **Passos** | 1. Reservar ref A e B 2. Pagar ambas 3. Capturar POST edge (sem pagar UI opcional) |
| **Resultado esperado** | HTTP 200; `checkoutUrl`; metadata sem `bag_orders_json` >500 chars; `bag_checkout: true` |
| **Componentes afectados** | `create-payment-intent` edge, `LiveInStreamCheckout` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | 2 live_items, 2 pending/accepted |
| **Validar BD** | — (pré-pagamento) |
| **Validar UI** | Sheet 2 linhas; total = soma |
| **Risco de regressão** | Alto — manual #6 |
| **Dependências** | A191 ×2 |

---

## A199 — Portes transportadora 3,50 €

| Campo | Valor |
|-------|-------|
| **ID** | A199 |
| **Nome** | Linha portes Envio Transportadora no checkout |
| **Pré-condições** | Checkout aberto; método transportadora seleccionável |
| **Passos** | 1. Abrir checkout 2. Escolher «Envio Transportadora (€3.50)» 3. Ver breakdown |
| **Resultado esperado** | +3,50 € no total; label exacta BATATA |
| **Componentes afectados** | `live_in_stream_checkout.dart` (`shippingCarrierEur`), `fee_calculator.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Unit |
| **Dados necessários** | 1 linha checkout |
| **Validar BD** | Order `shipping_cost` ou notes = 3.5 após pago |
| **Validar UI** | Linha «Envio Transportadora (€3.50)»; total correcto |
| **Risco de regressão** | Alto — R5 KPI portes |
| **Dependências** | A195 |

---

## A200 — Portes entrega em mão 0 €

| Campo | Valor |
|-------|-------|
| **ID** | A200 |
| **Nome** | Entrega em mão sem portes |
| **Pré-condições** | Seller oferece mão; buyer perfil compatível |
| **Passos** | 1. Checkout 2. Seleccionar «Entrega em Mão (€0.00)» |
| **Resultado esperado** | Portes 0; total = artigos + seguro apenas |
| **Componentes afectados** | `shippingHand`, `shippingCostForMethod` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Unit |
| **Dados necessários** | checkout session |
| **Validar BD** | `shipping_cost=0` ou null |
| **Validar UI** | Linha 0 € explícita |
| **Risco de regressão** | Baixo |
| **Dependências** | A199 |

---

## A201 — Seguro Fleaber 0,65 € + 5%

| Campo | Valor |
|-------|-------|
| **ID** | A201 |
| **Nome** | Protecção Fleaber no breakdown |
| **Pré-condições** | Checkout com seguro activo (pagamento na app) |
| **Passos** | 1. Abrir checkout 2. Ver linha seguro 3. Calcular manualmente |
| **Resultado esperado** | 0,65 + 5% × (artigos + portes); visível no sheet |
| **Componentes afectados** | `fee_calculator.dart`, `live_checkout_fees_test.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Unit |
| **Dados necessários** | artigo 10€ + portes 3.5 → seguro esperado |
| **Validar BD** | `orders` fee fields / `price_total` |
| **Validar UI** | Linha seguro + total |
| **Risco de regressão** | Médio |
| **Dependências** | A199 |

---

## A202 — Price gate bloqueia checkout preço 0

| Campo | Valor |
|-------|-------|
| **ID** | A202 |
| **Nome** | Preço pendente — Pagar bloqueado |
| **Pré-condições** | `live_items.price` null/0; reserva pending |
| **Passos** | 1. Reservar sem preço 2. Tentar Pagar |
| **Resultado esperado** | `LiveItemPriceGate` falha; snack/erro amigável; **sem** Stripe |
| **Componentes afectados** | `live_item_price_gate.dart`, P-series |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot + Unit |
| **Dados necessários** | item price 0 |
| **Validar BD** | `price` null/0; sem order criada |
| **Validar UI** | Pagar desactivado ou erro ao tap |
| **Risco de regressão** | Alto — Stripe 0€ |
| **Dependências** | A020/A046; A227 |

---

## A203 — Qty checkout = requested_qty (R31)

| Campo | Valor |
|-------|-------|
| **ID** | A203 |
| **Nome** | Stepper checkout reflecte qty aceite over-stock |
| **Pré-condições** | Reserva `accepted` `requested_qty=2`; stock 1; aceite confirmado |
| **Passos** | 1. Aceitar over-stock 2. Pagar 3. Ver qty no sheet |
| **Resultado esperado** | Qty **2** no checkout; total 2× preço + taxas |
| **Componentes afectados** | `live_bag_checkout_sheet.dart`, `LiveBagCheckoutPayLine` |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | accepted qty 2 |
| **Validar BD** | `requested_qty=2` |
| **Validar UI** | Stepper/fixado em 2 |
| **Risco de regressão** | Crítico — R31 FAIL repetido |
| **Dependências** | A084; A204; P11 |

---

## A204 — Dialog qty > stock ao Pagar (T1)

| Campo | Valor |
|-------|-------|
| **ID** | A204 |
| **Nome** | Comprador vê dialog; vendedor card urgente — só ao Pagar |
| **Pré-condições** | `requested_qty` > `available_qty`; status pending (não accepted) |
| **Passos** | 1. Reservar qty 2 stock 1 2. **Pagar** (não só reservar) |
| **Resultado esperado** | Dialog comprador; card urgente vendedor; **sem** abrir Stripe |
| **Componentes afectados** | `checkoutQtyExceedsAvailable`, studio urgent card |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | T1 setup |
| **Validar BD** | Sem order pago |
| **Validar UI** | Dialog + card «Pedido total» (R6) |
| **Risco de regressão** | Crítico — T1/T2 BATATA |
| **Dependências** | A086; T2 (negativo) |

---

## A205 — Stripe WebView / browser abre

| Campo | Valor |
|-------|-------|
| **ID** | A205 |
| **Nome** | URL checkout Stripe ao confirmar pagamento |
| **Pré-condições** | Reserva payable; preço > 0; edge A3 deployada; Stripe test mode |
| **Passos** | 1. Pagar 2. Confirmar no sheet 3. Browser/WebView abre |
| **Resultado esperado** | URL `checkout.stripe.com` ou success flow; `FleaberStripeCheckoutContext` grava pending |
| **Componentes afectados** | `fleaber_stripe_checkout_context.dart`, `create-payment-intent` |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | Stripe test keys staging |
| **Validar BD** | Order `reserva_pendente` criada; prefs pending context |
| **Validar UI** | Browser abre; loading inline |
| **Risco de regressão** | Alto — dependência edge |
| **Dependências** | A202 negativo; A227; A199–A201 |

---

## A206 — Stripe success + reconcile (#7)

| Campo | Valor |
|-------|-------|
| **ID** | A206 |
| **Nome** | Retorno success → converted + order pago |
| **Pré-condições** | A205; cartão teste Stripe |
| **Passos** | 1. Pagar com `4242…` 2. Fechar browser 3. App resume `tryResumeOnAppResumed` |
| **Resultado esperado** | `orders.status=pago`; reserva `converted`; notes `stripe_paid:`; `live_id` preenchido |
| **Componentes afectados** | `afterStripeBrowserClosed`, `reconcileStripePaidOrder`, edge settle |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | Stripe test; session_id |
| **Validar BD** | `select status, live_id, notes from orders where id=$oid`; reserva converted |
| **Validar UI** | Saco «Comprado ✓»; snack sucesso |
| **Risco de regressão** | Crítico — dinheiro real em staging |
| **Dependências** | A205; A209 |

**Cobertura transversal (stock):** após reconcile, `available_qty` decrementa pela `requested_qty` paga; waitlist pending **não** consome stock vendido — validar `live_items` / `live_catalog_stock_service` antes e depois.

---

## A207 — Stripe cancel — estado preservado

| Campo | Valor |
|-------|-------|
| **ID** | A207 |
| **Nome** | Cancelar checkout Stripe mantém reserva |
| **Pré-condições** | Checkout aberto |
| **Passos** | 1. Abrir Stripe 2. Cancelar/voltar |
| **Resultado esperado** | Reserva `accepted` ou `pending`; **não** converted; order abortada ou `reserva_pendente` |
| **Componentes afectados** | stripe context cleanup |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | checkout iniciado |
| **Validar BD** | Reserva não converted |
| **Validar UI** | Saco ainda «Aceite · pronto a pagar» |
| **Risco de regressão** | Médio |
| **Dependências** | A205 |

---

## A208 — Settle bag 2 orders (#6)

| Campo | Valor |
|-------|-------|
| **ID** | A208 |
| **Nome** | Um checkout Stripe → 2 orders pago |
| **Pré-condições** | A198; pagamento completo |
| **Passos** | 1. Multi-ref checkout 2. Success URL settle bag 3. Query orders |
| **Resultado esperado** | Ambas orders `pago`; cada reserva `converted`; `bag_orders_json` reconciliado |
| **Componentes afectados** | `settlePaidBagOrders`, `_reconcilePendingBagOrders` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | 2 refs; metadata bag |
| **Validar BD** | 2 orders pago; 2 converted |
| **Validar UI** | — |
| **Risco de regressão** | Alto — V0.3b não implementado |
| **Dependências** | A198; A206 |

---

## A209 — RPC `batata_live_reconcile_stripe_order`

| Campo | Valor |
|-------|-------|
| **ID** | A209 |
| **Nome** | Reconcile manual/API order pago órfã |
| **Pré-condições** | Order `pago` sem converted; notes stripe |
| **Passos** | 1. Seed order pago 2. RPC reconcile 3. Ver reserva |
| **Resultado esperado** | Reserva `converted`; stock atualiza; KPI refresh |
| **Componentes afectados** | `live_reservation_queue_service.dart`, SQL hotfix |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | order id, live_id |
| **Validar BD** | converted + notes stripe_paid |
| **Validar UI** | — (API) |
| **Risco de regressão** | Alto — manual #7/#8; **duplicação pagamento** se reconcile não idempotente |
| **Dependências** | — |

**Cobertura transversal (idempotência):** chamar RPC 2× com mesmo `order_id` + `session_id` — apenas 1 `converted`, 1 crédito wallet (A219).

---

## A210 — Purchase broadcast pós-pagamento

| Campo | Valor |
|-------|-------|
| **ID** | A210 |
| **Nome** | Chat «comprou» após reconcile |
| **Pré-condições** | A206 completo |
| **Passos** | 1. Pagar 2. Ver chat público 3. (Opcional) inbox mensagens vendedor-comprador |
| **Resultado esperado** | `batata_live_purchase_broadcast` → msg social «comprou»; thread privada/order msg se regra encomenda activa |
| **Componentes afectados** | reconcile → broadcast RPC, messages service |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | converted |
| **Validar BD** | `live_messages` comprou; opcional `messages` order thread |
| **Validar UI** | Chat linha social; inbox se aplicável |
| **Risco de regressão** | Médio — dedupe A289 / A217 rifa |
| **Dependências** | A206; A282 |

---

## A211 — Rifa: +2 entradas bónus pós-checkout

| Campo | Valor |
|-------|-------|
| **ID** | A211 |
| **Nome** | Bónus rifa +2 após compra live |
| **Pré-condições** | Rifa activa na live; compra `converted` (A206) |
| **Passos** | 1. Completar pagamento saco/single 2. Abrir painel rifa 3. Ver contador entradas |
| **Resultado esperado** | +2 entradas no total do buyer; disparo único por order |
| **Componentes afectados** | raffle post-checkout hook, edge settle |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | `raffle_id`, buyer, order pago |
| **Validar BD** | `raffle_entries` delta +2 vs baseline |
| **Validar UI** | Contador entradas actualizado |
| **Risco de regressão** | Médio — overlap com reconcile idempotente (A209) |
| **Dependências** | A206 |

---

## A212 — Join rifa +1 entrada

| Campo | Valor |
|-------|-------|
| **ID** | A212 |
| **Nome** | Entrar na rifa durante directo (+1) |
| **Pré-condições** | Rifa activa; buyer autenticado; live `status=live` |
| **Passos** | 1. Player → painel rifa 2. Tocar Join / Participar |
| **Resultado esperado** | +1 entrada base; UI confirma inscrição |
| **Componentes afectados** | raffle join UI/RPC |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | `live_id` com raffle |
| **Validar BD** | `raffle_entries` count buyer +1 |
| **Validar UI** | Estado «inscrito» / contador |
| **Risco de regressão** | Baixo |
| **Dependências** | A145 |

---

## A213 — Share intent rifa +2

| Campo | Valor |
|-------|-------|
| **ID** | A213 |
| **Nome** | Partilha social +2 entradas |
| **Pré-condições** | Buyer já joined (A212) |
| **Passos** | 1. Tocar Partilhar 2. Completar share intent (ou simular claim) |
| **Resultado esperado** | +2 entradas após claim válido; sem duplicar por re-share imediato |
| **Componentes afectados** | share sheet, raffle share claim RPC |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | buyer joined |
| **Validar BD** | entries +2 após claim |
| **Validar UI** | Feedback «+2 entradas» |
| **Risco de regressão** | Baixo |
| **Dependências** | A212 |

---

## A214 — Referral qualify 60s

| Campo | Valor |
|-------|-------|
| **ID** | A214 |
| **Nome** | Visitante referral — qualificação 60s |
| **Pré-condições** | Link referral válido; visitante novo |
| **Passos** | 1. Abrir link referral 2. Permanecer ≥60s (ou regra produto) 3. Ver entradas referrer |
| **Resultado esperado** | Referrer +2 entradas; visitante atribuído |
| **Componentes afectados** | referral tracking, raffle qualify RPC |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | 2 users, referral token |
| **Validar BD** | `referral_id`, entries referrer |
| **Validar UI** | Timer/qualify state |
| **Risco de regressão** | Médio |
| **Dependências** | A212 |

---

## A215 — Leaderboard top 5 (R6)

| Campo | Valor |
|-------|-------|
| **ID** | A215 |
| **Nome** | Ranking top 5 entradas |
| **Pré-condições** | ≥5 participantes ou entries variadas |
| **Passos** | 1. Abrir leaderboard rifa 2. Comparar ordem |
| **Resultado esperado** | Top 5 ordenado por entradas desc; buyer actual destacado |
| **Componentes afectados** | raffle leaderboard widget |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | entries seed |
| **Validar BD** | `order by entries desc limit 5` match UI |
| **Validar UI** | Lista top 5 |
| **Risco de regressão** | Baixo — R6 leaderboard |
| **Dependências** | A212 |

---

## A216 — Timer rifa countdown

| Campo | Valor |
|-------|-------|
| **ID** | A216 |
| **Nome** | Countdown mm:ss até fecho |
| **Pré-condições** | Rifa com `ends_at` futuro |
| **Passos** | 1. Abrir painel rifa 2. Observar timer 3. (Opcional) mock tempo |
| **Resultado esperado** | Decrementa em tempo real; UI fecha/join disabled ao zero |
| **Componentes afectados** | timer widget, raffle state |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Unit |
| **Dados necessários** | `ends_at` |
| **Validar BD** | — |
| **Validar UI** | Formato mm:ss |
| **Risco de regressão** | Baixo |
| **Dependências** | A212 |

---

## A217 — Chat `🎟️ Rifa:` dedupe (R7)

| Campo | Valor |
|-------|-------|
| **ID** | A217 |
| **Nome** | Broadcast rifa sem spam no chat |
| **Pré-condições** | Eventos rifa repetidos (join, +2, draw) |
| **Passos** | 1. Disparar 2+ broadcasts rifa rápidos 2. Ver chat público |
| **Resultado esperado** | Prefixo `🎟️ Rifa:`; dedupe R7 — sem linhas duplicadas em janela curta |
| **Componentes afectados** | `live_system_chat_humanizer.dart`, raffle broadcast |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Unit + Bot |
| **Dados necessários** | live_id, raffle events |
| **Validar BD** | `live_messages` — sem duplicata body em 5s |
| **Validar UI** | Chat legível |
| **Risco de regressão** | Médio — R7 |
| **Dependências** | A212; A210 (dedupe compra) |

---

## A218 — Draw winners notificação

| Campo | Valor |
|-------|-------|
| **ID** | A218 |
| **Nome** | Sorteio + notificação vencedores |
| **Pré-condições** | Rifa fechada; entradas > 0 |
| **Passos** | 1. Trigger draw (timer ou admin) 2. Ver BD + chat + push |
| **Resultado esperado** | `winner_id`(s) persistido; notificação/chat anúncio |
| **Componentes afectados** | draw job/RPC, notifications |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | raffle ended |
| **Validar BD** | winners table / raffle row |
| **Validar UI** | Modal/banner vencedor |
| **Risco de regressão** | Médio |
| **Dependências** | A216 |

---

## A219 — Wallet seller pós-venda

| Campo | Valor |
|-------|-------|
| **ID** | A219 |
| **Nome** | Movimento wallet vendedor após order pago |
| **Pré-condições** | A206; seller com wallet activa |
| **Passos** | 1. Pagar como buyer 2. Login seller 3. Ver wallet |
| **Resultado esperado** | Crédito líquido (total − comissão − taxas Stripe) |
| **Componentes afectados** | wallet RPC, settle edge |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | order pago, seller_id |
| **Validar BD** | `wallet_transactions` tipo credit |
| **Validar UI** | Saldo wallet seller |
| **Risco de regressão** | Crítico — dinheiro |
| **Dependências** | A206; A220 |

---

## A220 — Commission Fleaber

| Campo | Valor |
|-------|-------|
| **ID** | A220 |
| **Nome** | Fee platform na libertação |
| **Pré-condições** | Order `pago`; fluxo libertação activo |
| **Passos** | 1. Inspeccionar order 2. Comparar com `fee_calculator` |
| **Resultado esperado** | Comissão % BATATA correcta; separada do líquido seller |
| **Componentes afectados** | `fee_calculator.dart`, orders fee columns |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | price_total conhecido |
| **Validar BD** | fee / commission fields |
| **Validar UI** | — |
| **Risco de regressão** | Alto — desalinhamento SQL vs Dart |
| **Dependências** | A206 |

---

## A221 — Order dispute pós-live compra

| Campo | Valor |
|-------|-------|
| **ID** | A221 |
| **Nome** | Disputa em encomenda originada na live |
| **Pré-condições** | Order `pago` com `live_id` |
| **Passos** | 1. Minhas encomendas 2. Abrir disputa |
| **Resultado esperado** | Disputa criada; estados order/disputa coerentes |
| **Componentes afectados** | disputes flow |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | order id |
| **Validar BD** | dispute row |
| **Validar UI** | Form disputa |
| **Risco de regressão** | Médio |
| **Dependências** | A206; A223 |

---

## A222 — Devolução fluxo chat/encomenda

| Campo | Valor |
|-------|-------|
| **ID** | A222 |
| **Nome** | Devolução pós-pago (cancelamento depois de pagar) |
| **Pré-condições** | Order pago; disputa ou pedido devolução |
| **Passos** | 1. Iniciar devolução 2. Seller/admin processa 3. Ver stock/wallet |
| **Resultado esperado** | Refund separado de `bag_remove`; reserva permanece `converted`; stock revert conforme política |
| **Componentes afectados** | returns, refunds, stock restore |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | order pago |
| **Validar BD** | return/refund status; stock opcional |
| **Validar UI** | Estado encomenda + chat |
| **Risco de regressão** | Médio |
| **Dependências** | A206; A221 |

---

## A223 — Minhas encomendas contexto live

| Campo | Valor |
|-------|-------|
| **ID** | A223 |
| **Nome** | Order list com `live_id` |
| **Pré-condições** | A206 completo |
| **Passos** | 1. Perfil → Minhas encomendas 2. Localizar order live |
| **Resultado esperado** | Linha com contexto live; `live_id` preenchido e navegável |
| **Componentes afectados** | orders list UI, `orders_live_context_batata` |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | order com live_id |
| **Validar BD** | `orders.live_id` not null |
| **Validar UI** | Badge/link live |
| **Risco de regressão** | Baixo |
| **Dependências** | A206 |

---

## A224 — Gorjeta stripe tip edge

| Campo | Valor |
|-------|-------|
| **ID** | A224 |
| **Nome** | Gorjeta independente do saco |
| **Pré-condições** | Live activa; feature tip; buyer autenticado |
| **Passos** | 1. Player → Gorjeta 2. Pagar tip Stripe |
| **Resultado esperado** | `tip` row criada; **sem** misturar metadata saco (`bag_orders_json`) |
| **Componentes afectados** | tip edge, stripe context |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | live_id, seller |
| **Validar BD** | tip transaction |
| **Validar UI** | CTA gorjeta + confirmação |
| **Risco de regressão** | Médio — clash A229 |
| **Dependências** | A229 |

---

## A225 — Shadow product `live_only` checkout

| Campo | Valor |
|-------|-------|
| **ID** | A225 |
| **Nome** | Item shadow — `checkout_product_id` no pagamento |
| **Pré-condições** | `live_items.kind=live_only` ou shadow; produto marketplace separado |
| **Passos** | 1. Reservar shadow item 2. Pagar 3. Query `orders.product_id` |
| **Resultado esperado** | Resolve product shadow no checkout; marketplace listing **intacto** (Z52) |
| **Componentes afectados** | `create-payment-intent`, catalog sync, shadow rows |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | shadow `checkout_product_id` |
| **Validar BD** | `orders.product_id` = checkout id; marketplace product unchanged |
| **Validar UI** | Título/foto correctos no sheet |
| **Risco de regressão** | Alto — Z52 marketplace merge |
| **Dependências** | A148; A226 |

---

## A226 — Marketplace product checkout TYPE A

| Campo | Valor |
|-------|-------|
| **ID** | A226 |
| **Nome** | TYPE A — `product_id` marketplace no order |
| **Pré-condições** | Item TYPE A ligado a `products`; preço live pode ≠ marketplace |
| **Passos** | 1. Checkout 2. Pagar 3. Ver order + total |
| **Resultado esperado** | `product_id` marketplace; preço cobrado = **live** (`resolveFreshUnitPrice`) |
| **Componentes afectados** | `live_item_price_gate.dart`, TYPE A rules, edge metadata |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual + Integration |
| **Dados necessários** | TYPE A item |
| **Validar BD** | order.product_id marketplace; price = live |
| **Validar UI** | Total = live price × qty + taxas |
| **Risco de regressão** | Alto |
| **Dependências** | A202; A225 |

---

## A227 — P5 botão Pagar activo pós-preço

| Campo | Valor |
|-------|-------|
| **ID** | A227 |
| **Nome** | Preço definido → CTA Pagar habilita (incl. aceite sem preço antes) |
| **Pré-condições** | Reserva `accepted` ou `pending` que foi aceite **sem** preço; depois seller define preço > 0 |
| **Passos** | 1. Reservar item price_pending 2. Seller aceita (BATATA permite) 3. Seller define preço 4. Buyer abre saco |
| **Resultado esperado** | Durante preço 0: Pagar bloqueado (A202); após preço: `buyerCanPayBagReservation` true; Pagar activo |
| **Componentes afectados** | P5 series, `live_item_price_gate`, accept RPC |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | price_pending → price set |
| **Validar BD** | `live_items.price` > 0; reserva accepted |
| **Validar UI** | Botão Pagar enabled; banner «pronto a pagar» |
| **Risco de regressão** | Crítico — P5/P10 histórico |
| **Dependências** | A081; A202; A206 |

**Cobertura transversal:** comprador com reservas **pending** (sem Pagar) vs **accepted** (com Pagar) — contrastar com A191 no mesmo saco.

---

## A228 — P10 preço muda após venda bloqueado

| Campo | Valor |
|-------|-------|
| **ID** | A228 |
| **Nome** | Seller não pode alterar preço após venda/convert |
| **Pré-condições** | Item com venda `converted`; seller no catálogo |
| **Passos** | 1. Converter reserva (A206) 2. Seller tenta mudar preço live |
| **Resultado esperado** | Erro/bloqueio P10; preço histórico preservado na order |
| **Componentes afectados** | P10 guard, catalog edit RPC |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | converted item |
| **Validar BD** | price unchanged pós-tentativa |
| **Validar UI** | Snack erro seller |
| **Risco de regressão** | Médio |
| **Dependências** | A206 |

---

## A229 — SharedPreferences stripe context clash

| Campo | Valor |
|-------|-------|
| **ID** | A229 |
| **Nome** | Single vs bag vs tip — prefs não sobrescrevem |
| **Pré-condições** | 2 fluxos checkout sequenciais (ex. bag cancel → single pay) |
| **Passos** | 1. Iniciar bag checkout 2. Cancelar Stripe 3. Iniciar single/tip 4. Completar pagamento |
| **Resultado esperado** | `FleaberStripeCheckoutContext` reconcile só sessão correcta; sem settle bag fantasma |
| **Componentes afectados** | `fleaber_stripe_checkout_context.dart`, SharedPreferences keys |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | 2 checkout types |
| **Validar BD** | 1 order pago esperada |
| **Validar UI** | — |
| **Risco de regressão** | Crítico |
| **Dependências** | A205; A207; A224 |

---

## A230 — Bag remove RPC `bag_removed`

| Campo | Valor |
|-------|-------|
| **ID** | A230 |
| **Nome** | Cancelamento comprador **antes** de pagar |
| **Pré-condições** | Reserva `pending` ou `accepted`; sem order `pago` |
| **Passos** | 1. Saco → Remover 2. Confirmar 3. Ver vendedor KPI |
| **Resultado esperado** | `status=rejected`, `notes` contém `bag_removed`; stock libertado; vendedor sem Aceitar |
| **Componentes afectados** | `batata_live_bag_remove_request`, stock service |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | reservation id |
| **Validar BD** | rejected + bag_removed |
| **Validar UI** | Secção A194; sem Pagar |
| **Risco de regressão** | Médio — doc live-ops #4 |
| **Dependências** | A194; A191 |

---

## Apêndice A — Resumo A190–A230

| Bloco | IDs | Foco |
|-------|-----|------|
| Saco UI | A190–A194 | Secções in-bag, waitlist, comprado, cancelado |
| Checkout | A195–A204 | Multi-linha, qty, portes, seguro, price gate, T1/R31 |
| Stripe | A205–A210 | WebView, reconcile, bag settle, broadcast, stock, msgs |
| Rifa | A211–A218 | Pós-compra +2, join, share, referral, leaderboard, timer, dedupe, draw |
| Pós-venda | A219–A224 | Wallet, comissão, disputa, devolução, encomendas, tip |
| Catálogo checkout | A225–A230 | Shadow, TYPE A, P5/P10 preço, context clash, bag remove |

**Total fichas:** 41 (A190–A230).

### Temas transversais (sem ID próprio — cobertos nas fichas acima)

| Tema | Fichas principais |
|------|-------------------|
| Múltiplas reservas / multi-unidade | A195, A197, A198, A203 |
| Preço pendente / aceite sem preço / pagar depois | A202, A227, A206 |
| Checkout single vs saco | A195–A198, A208, A229 |
| Stock após pagamento | A206, A209 |
| Duplicação pagamento | A209 (idempotência) |
| Cancel antes vs depois pagar | A230/A194 vs A222 |
| Live vs gravado / replay compra | A193 (histórico saco); regra ended → ver A300+ |
| Mensagens por compra | A210 (+ A282) |

---

## Apêndice B — P0 desta faixa (22)

| ID | Nome curto |
|----|------------|
| A190 | Abrir saco |
| A191 | Secção in-bag |
| A192 | Waitlist |
| A194 | Cancelados |
| A195 | Checkboxes multi-linha |
| A197 | Qty agregada |
| A198 | Multi-ref metadata |
| A199 | Portes 3,50 € |
| A201 | Seguro Fleaber |
| A202 | Price gate 0 € |
| A203 | Qty R31 |
| A204 | Dialog T1 |
| A205 | Stripe abre |
| A206 | Success reconcile |
| A208 | Settle bag 2 orders |
| A209 | RPC reconcile |
| A210 | Broadcast compra |
| A225 | Shadow product |
| A226 | TYPE A checkout |
| A227 | P5 Pagar pós-preço |
| A230 | Bag remove RPC |

---

## Apêndice C — Top 10 a automatizar primeiro

| # | ID | Porquê | Tipo |
|---|-----|--------|------|
| 1 | A209 | RPC reconcile idempotente — base manual #7 | Integration |
| 2 | A198 | Multi-ref metadata — blocker saco (#6) | Integration |
| 3 | A208 | Settle bag 2 orders — dinheiro multi-linha | Integration |
| 4 | A206 | Reconcile pós-pago + stock | Integration |
| 5 | A202 | Price gate — evita Stripe 0 € | Unit + Bot |
| 6 | A201 | Seguro + portes — fee regression | Unit |
| 7 | A197 | Merge qty mesma ref — R6/R31 | Integration |
| 8 | A230 | Bag remove — stock + KPI vendedor | Integration |
| 9 | A225 | Shadow `checkout_product_id` — Z52 | Integration |
| 10 | A227 | P5 fluxo preço pendente → pagar | Bot |

---

## Apêndice D — Classificação por tipo (faixa completa)

| Tipo | IDs |
|------|-----|
| **Unit** | A199, A200, A201, A216, A217 (parcial) |
| **Integration** | A193, A194, A197, A198, A206, A208, A209, A214, A219, A220, A225, A228, A230 |
| **Bot** | A192, A202, A210, A212, A213, A215, A217, A218, A227 |
| **Maestro** | A190, A191, A194 |
| **Manual** | A195, A196, A203, A204, A205, A207, A211, A221, A222, A223, A224, A226, A229 |
| **Híbrido** | A206 (Integration + Manual Stripe UI), A214 (Integration + Manual 60s), A219 (Integration + Manual wallet UI) |

---

## Apêndice E — Riscos críticos (levantamento)

1. **R31 / T1 (A203–A204):** qty checkout e dialog só ao Pagar — regressões históricas R31 FAIL; cenário manual obrigatório até Bot cobrir over-stock.
2. **Settle bag multi-order (A208):** pagamento único Stripe pode não converter todas as linhas do saco (V0.3b).
3. **Price gate vs aceite sem preço (A202 + A227):** aceitar sem preço permitido; Stripe bloqueado até `price > 0` — falha silenciosa se gate omitido no edge.
4. **Duplicação pagamento (A209):** double `settleCheckoutSession` / reconcile credita wallet ou converte 2×.
5. **Stripe context clash (A229 + A224):** prefs `bag_orders_json` vs single vs tip — settle fantasma ou order errada.
6. **Shadow / TYPE A (A225–A226):** `product_id` errado na order quebra marketplace sync (Z52) ou cobra preço marketplace em vez de live.
7. **Portes/seguro (A199–A201):** totais incorrectos → disputas e KPI R5.
8. **Metadata >500 chars (A198):** edge `create-payment-intent` rejeita checkout saco com muitas linhas.
9. **Wallet/comissão (A219–A220):** desalinhamento `fee_calculator.dart` vs SQL settle — seller líquido errado.
10. **Live ended vs pagar (A193 + gravado A300+):** saco histórico em replay; regra se Pagar permitido em `ended` unclear — risco de checkout órfão.

---

*Fim A190–A230. Aguardar aprovação antes de expandir A050–A079.*
