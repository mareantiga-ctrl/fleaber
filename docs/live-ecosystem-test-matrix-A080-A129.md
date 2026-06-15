# Matriz expandida — A080 a A129

**Área:** Vendedor Operação · filas · aceites · pagamentos seller · rifa seller  
**Versão:** 1.0 · **2026-06-14**  
**Estado:** Fichas expandidas — **sem implementação de testes** (runner secção 9 de `live-ecosystem-test-matrix.md`).

Substitui a tabela compacta A080–A129 em `live-ecosystem-test-matrix.md`.

**Nota:** A086/A127 cobrem T1/T2 e `qty_confirm_needed`; A088 cobre reconcile stale (#8); A117–A120 fecham rifa seller; A129 regra BATATA cancelados vs actividade.

---

## A080 — Fila «No saco» mostra reservas pending

| Campo | Valor |
|-------|-------|
| **ID** | A080 |
| **Nome** | Secção «No saco» lista reservas pending com metadata |
| **Pré-condições** | Live `status=live`; comprador autenticado reservou ≥1 artigo (`source=fleaber_live`, `status=pending`); vendedor no studio tab **Operação** |
| **Passos detalhados** | 1. Comprador reserva artigo no player (bot ou Maestro) 2. Vendedor abre studio → Operação 3. Expandir categoria **No saco** 4. Inspeccionar linha da reserva |
| **Resultado esperado** | Linha visível com nome comprador (`profiles.full_name`), ref/título artigo, `requested_qty`, prazo/deadline se aplicável; chip posição ou estado pending; botões Aceitar/Rejeitar/Skip activos |
| **Componentes afectados** | `live_vendor_studio_panel.dart` (`_ReservationListCategory.inBag`), `live_vendor_ops_ui.dart`, RPC `batata_live_reservation_queue_for_live` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot + Maestro (H01) |
| **Dados necessários** | `live_id`, buyer seed, `live_reservation_requests` pending |
| **Como validar na BD** | `select * from live_reservation_requests where live_id=$id and status='pending' order by queue_position` |
| **Como validar na UI** | Label «No saco»; contador summary chip; linha com buyer + ref + qty |
| **Risco de regressão** | Alto — entry point de toda operação seller |
| **Dependências** | A148 (comprador reserva); A071 (harness) |

---

## A081 — Aceitar reserva normal

| Campo | Valor |
|-------|-------|
| **ID** | A081 |
| **Nome** | Aceitar reserva pending → accepted + stock + msg sistema |
| **Pré-condições** | A080; reserva `pending`; stock disponível ≥ `requested_qty`; vendedor com `canManageReservations` |
| **Passos detalhados** | 1. Operação → No saco ou Pendentes 2. Tocar **Aceitar** na linha 3. Aguardar refresh realtime 4. Verificar comprador (chip aceite) e stock catálogo |
| **Resultado esperado** | RPC `batata_process_live_reservation_request` action `accept` → `status=accepted`; mensagem sistema no chat (humanizer); stock reservas/vendidos actualiza; secção **Aceites · aguardar pagamento** |
| **Componentes afectados** | `LiveReservationQueueService.processRequest`, `batata_process_live_reservation_request`, `live_system_chat_humanizer.dart`, `live_vendor_studio_panel.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot + Maestro (H01) |
| **Dados necessários** | `request_id`, seller JWT |
| **Como validar na BD** | `status='accepted'`, `processed_by` preenchido; `batata_live_item_stock` available desce |
| **Como validar na UI** | Linha move para Aceites; actividade «reserva aceite»; comprador R2 banner |
| **Risco de regressão** | Crítico — harness Maestro `.maestro/flows/v2_seller_harness_accept.yaml` |
| **Dependências** | A080; A192 (waitlist negativo) |

---

## A082 — Rejeitar reserva

| Campo | Valor |
|-------|-------|
| **ID** | A082 |
| **Nome** | Rejeitar reserva pending → rejected + notificação comprador |
| **Pré-condições** | Reserva `pending`; sem order `pago` |
| **Passos detalhados** | 1. Operação → linha pending 2. Tocar **Rejeitar** 3. Confirmar se dialog 4. Ver saco comprador e chat |
| **Resultado esperado** | `status=rejected`; comprador vê chip rejeitado no saco; msg sistema P12a no chat; stock libertado; linha sai da fila urgente |
| **Componentes afectados** | `batata_process_live_reservation_request`, `live_bag_sheet.dart`, humanizer P12a |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | pending request, buyer id |
| **Como validar na BD** | `status='rejected'`; sem incremento sold |
| **Como validar na UI** | Comprador: chip rejeitado; vendedor: sem botões na linha |
| **Risco de regressão** | Médio — confusão com cancelamento comprador (A085) |
| **Dependências** | A080; A194 (comprador cancelado — distinto) |

---

## A083 — Skip reserva

| Campo | Valor |
|-------|-------|
| **ID** | A083 |
| **Nome** | Skip reserva pending → skipped; sai da fila urgente |
| **Pré-condições** | Reserva `pending`; fila com ≥1 pedido |
| **Passos detalhados** | 1. Operação → linha pending 2. Tocar **Skip** 3. Ver fila e actividade |
| **Resultado esperado** | `status=skipped`; pedido deixa de aparecer em No saco/Pendentes activos; não converte; comprador informado conforme regra skip |
| **Componentes afectados** | `batata_process_live_reservation_request`, `live_vendor_studio_panel.dart` |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | pending request |
| **Como validar na BD** | `status='skipped'` |
| **Como validar na UI** | Linha ausente da secção activa; histórico se expandido |
| **Risco de regressão** | Baixo |
| **Dependências** | A080 |

---

## A084 — Aceitar over-stock com confirmação

| Campo | Valor |
|-------|-------|
| **ID** | A084 |
| **Nome** | Aceitar qty > stock com dialog confirmação vendedor |
| **Pré-condições** | Reserva `requested_qty=2`; stock disponível `1`; `status=pending` |
| **Passos detalhados** | 1. Comprador reserva qty 2 stock 1 2. Vendedor **Aceitar** 3. Confirmar dialog overbook 4. Ver BD e checkout comprador |
| **Resultado esperado** | `status=accepted`, `requested_qty=2`; notes contém marca qty/overbook; stock reservas reflecte aceite; **sem** card urgente até comprador **Pagar** (T2) |
| **Componentes afectados** | `live_vendor_studio_panel.dart` (overbook dialog), `batata_process_live_reservation_request`, studio overbook UI |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot + Manual |
| **Dados necessários** | item stock 1, qty 2 |
| **Como validar na BD** | `requested_qty=2`, notes `qty_confirm` ou equivalente; accepted |
| **Como validar na UI** | Dialog confirmação vendedor; P11/P203 checkout qty 2 |
| **Risco de regressão** | Alto — R6/R31 histórico |
| **Dependências** | A086 (T2 negativo); A127; A203 |

---

## A085 — Comprador cancelou — sem Aceitar/Rejeitar

| Campo | Valor |
|-------|-------|
| **ID** | A085 |
| **Nome** | Reserva `bag_removed` — vendedor sem acções na fila |
| **Pré-condições** | Comprador removeu do saco (`status=rejected`, notes contém `bag_removed`); sem pagamento |
| **Passos detalhados** | 1. Comprador cancela via saco (A230) 2. Vendedor refresca Operação 3. Localizar reserva |
| **Resultado esperado** | **Sem** botões Aceitar/Rejeitar/Skip; secção cancelados ou histórico; actividade «cancelou» (não «adicionou ao saco»); regra BATATA live-ops |
| **Componentes afectados** | `LiveReservationQueueService.isBuyerCancelledReservation`, `live_vendor_studio_panel.dart`, `batata_live_bag_remove_request` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro + Bot |
| **Dados necessários** | buyer cancel flow |
| **Como validar na BD** | `status='rejected'`, notes `bag_removed` |
| **Como validar na UI** | Sem CTAs acção; secção cancelados; A129 coerente |
| **Risco de regressão** | Médio — doc live-ops #4 |
| **Dependências** | A230; A129 |

---

## A086 — Card urgente qty só ao Pagar (T1/T2)

| Campo | Valor |
|-------|-------|
| **ID** | A086 |
| **Nome** | Card vermelho urgente vendedor — T1 sim, T2 não (BATATA) |
| **Pré-condições** | Artigo stock 1; comprador reserva `requested_qty=2`; notes `qty_confirm_needed` após gate checkout |
| **Passos detalhados** | **T2 (negativo):** 1. Comprador **só Reservar** qty 2 2. Vendedor observa Operação — **sem** card urgente vermelho  **T1 (positivo):** 3. Comprador toca **Pagar** no saco/player 4. Gate marca qty confirm 5. Vendedor vê card «Na live / Livres / Pedido total» |
| **Resultado esperado** | T2: zero card `_buildUrgentReservationCard`; T1: card vermelho com breakdown stock (R6); dialog comprador; **sem** abrir Stripe até resolver |
| **Componentes afectados** | `live_vendor_studio_panel.dart` (`_urgentReservationPrompt`, `_reservationNeedsUrgentQtyConfirm`), `live_in_stream_checkout.dart`, `LiveReservationQueueService.needsUrgentQtyConfirmCard` |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | stock 1, qty 2, 2 contas |
| **Como validar na BD** | T1: notes `qty_confirm_needed`; sem order `pago` |
| **Como validar na UI** | T2: ausência card; T1: card R6 + dialog comprador |
| **Risco de regressão** | Crítico — T1/T2 BATATA; regressões patch v2/v3 |
| **Dependências** | A127; A204; A110 (`checkout.pay_qty_gate`) |

---

## A087 — KPI valor vendido inclui portes (R5)

| Campo | Valor |
|-------|-------|
| **ID** | A087 |
| **Nome** | KPI Operação «valor vendido» = artigo + portes + seguro (R5) |
| **Pré-condições** | Venda convertida com transportadora (3,50 €) + seguro Fleaber; order `status=pago` ligada à live |
| **Passos detalhados** | 1. Comprador completa pagamento Stripe (artigo ~10 € + portes + seguro) 2. Vendedor Operação → tab **Pagamentos** ou KPI topo 3. Comparar total UI vs valor pago comprador 4. Inspeccionar log `payments.refresh` |
| **Resultado esperado** | KPI ≈ total comprador (~14,83 € para artigo 10 € + taxas); **não** só preço artigo (~10 €); `paid_value_eur` em `live_vendor_studio_logs` alinhado |
| **Componentes afectados** | `live_vendor_studio_panel.dart` (`_refreshLiveOrderMetrics`, `_notifyOpsTotals`), `fee_calculator.dart`, payments tab |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | order pago com shipping; Stripe test |
| **Como validar na BD** | `orders.price_total` inclui portes/seguro; `live_id` preenchido |
| **Como validar na UI** | KPI carteira + lista pagamentos ≈ total pago |
| **Risco de regressão** | Alto — R5 FAIL histórico (KPI 10 € vs 14,83 €) |
| **Dependências** | A199–A201; A206; A423 |

---

## A088 — Reconcile stale paid order (#8)

| Campo | Valor |
|-------|-------|
| **ID** | A088 |
| **Nome** | Order `pago` sem convert — auto-reconcile ao abrir painel |
| **Pré-condições** | Reserva `pending` ou `accepted` com notes `stripe_checkout:{order_uuid}`; order correspondente `status=pago`; reserva **não** `converted` (estado stale simulado) |
| **Passos detalhados** | 1. Seed staging: order pago órfã (ver `live_ops_test_seed.sql`) 2. Vendedor abre Operação / refresh fila (`_loadReservationQueue`) 3. Verificar conversão automática 4. Opcional: RPC directo `batata_live_reconcile_stripe_order` |
| **Resultado esperado** | `reconcileStalePaidReservationsForLive` converte; reserva → `converted`; stock sold actualiza; log `stale_reconciled` > 0; KPI actualiza |
| **Componentes afectados** | `LiveReservationQueueService.reconcileStalePaidOrder` / `reconcileStalePaidReservationsForLive`, RPC `batata_live_reconcile_stripe_order`, `tool/live_ops_staging_check.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | stale order seed; seller live_id |
| **Como validar na BD** | `live_reservation_requests.status='converted'`; order link OK; idempotência 2.ª chamada |
| **Como validar na UI** | Reserva em histórico convertida; pagamentos lista |
| **Risco de regressão** | Crítico — manual #8; dinheiro sem conversão |
| **Dependências** | A206; runner secção 9 (adapter V0.3a) |

---

## A089 — Secção Pendentes (não «A tratar» UI)

| Campo | Valor |
|-------|-------|
| **ID** | A089 |
| **Nome** | UI usa «Pendentes» — label legacy «A tratar» ausente |
| **Pré-condições** | ≥1 reserva pending não cancelada |
| **Passos detalhados** | 1. Abrir Operação 2. Percorrer chips/categorias 3. Expandir Pendentes |
| **Resultado esperado** | Label **Pendentes** (`SellerOperationSection.queue` / `_ReservationListCategory.pending`); **sem** texto «A tratar» |
| **Componentes afectados** | `live_vendor_ops_ui.dart`, `live_vendor_studio_panel.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | pending row |
| **Como validar na BD** | — |
| **Como validar na UI** | Snapshot Maestro: «Pendentes» visible; «A tratar» absent |
| **Risco de regressão** | Baixo — copy/regressão harness |
| **Dependências** | A071; A080 |

---

## A090 — Secção Aceites

| Campo | Valor |
|-------|-------|
| **ID** | A090 |
| **Nome** | Secção «Aceites · aguardar pagamento» lista accepted |
| **Pré-condições** | ≥1 reserva `status=accepted`; não cancelada |
| **Passos detalhados** | 1. Aceitar reserva (A081) 2. Operação → Aceites 3. Ver linha e contador |
| **Resultado esperado** | Header «Aceites — aguardam pagamento (N)»; linhas accepted com prazo pagamento; sem botão Aceitar |
| **Componentes afectados** | `live_vendor_studio_panel.dart` (`_ReservationListCategory.accepted`) |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | accepted reservation |
| **Como validar na BD** | `status='accepted'` |
| **Como validar na UI** | Secção Aceites expandida; chip summary |
| **Risco de regressão** | Médio — confusão com pending (R6 banner) |
| **Dependências** | A081 |

---

## A091 — Secção Sem pagamento

| Campo | Valor |
|-------|-------|
| **ID** | A091 |
| **Nome** | Secção «Sem pagamento» — accepted expirados ou unpaid |
| **Pré-condições** | Reserva accepted past deadline ou estado unpaid conforme regra |
| **Passos detalhados** | 1. Simular aceite sem pagamento (tempo ou seed) 2. Operação → Sem pagamento |
| **Resultado esperado** | Linhas na categoria `_ReservationListCategory.unpaid`; acções conforme política (re-offer / expire) |
| **Componentes afectados** | `live_vendor_studio_panel.dart`, `LiveReservationQueueService.isAcceptedAwaitingPayment` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | accepted + deadline passed |
| **Como validar na BD** | status/deadline fields |
| **Como validar na UI** | Secção Sem pagamento não vazia |
| **Risco de regressão** | Médio |
| **Dependências** | A081; A113 |

---

## A092 — Secção Externos/waitlist

| Campo | Valor |
|-------|-------|
| **ID** | A092 |
| **Nome** | Externos e waitlist visíveis ao vendedor |
| **Pré-condições** | Reserva `source=facebook_manual` ou `helper_manual`; OU waitlist pending sem stock |
| **Passos detalhados** | 1. Criar pedido externo ou esgotar stock + nova reserva 2. Operação → Externos 3. Ver chip summary |
| **Resultado esperado** | Secção Externos com linhas correctas; waitlist/external count no summary chip; actividade «pagamento externo» se manual |
| **Componentes afectados** | `live_vendor_studio_panel.dart`, `isWaitlistPosition`, external sources |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | external source row ou waitlist |
| **Como validar na BD** | `source` field; queue_position waitlist |
| **Como validar na UI** | Chip «Externos»; secção expandida |
| **Risco de regressão** | Médio — A114 overlap |
| **Dependências** | A192; A114 |

---

## A093 — Secção Histórico

| Campo | Valor |
|-------|-------|
| **ID** | A093 |
| **Nome** | Histórico de reservas convertidas/rejected/skipped |
| **Pré-condições** | Live com histórico (`includeHistory=true`); ≥1 reserva terminal |
| **Passos detalhados** | 1. Completar ciclo accept→pay ou reject 2. Operação → Histórico 3. Scroll lista |
| **Resultado esperado** | Estados terminais visíveis; ordenação cronológica; read-only |
| **Componentes afectados** | `live_vendor_studio_panel.dart` (`SellerOperationSection.history`) |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | converted/rejected rows |
| **Como validar na BD** | RPC queue com history |
| **Como validar na UI** | Secção Histórico populada |
| **Risco de regressão** | Baixo |
| **Dependências** | A081 ou A082 |

---

## A094 — Cancelados pelo comprador

| Campo | Valor |
|-------|-------|
| **ID** | A094 |
| **Nome** | Secção/filtro cancelados comprador (`bag_removed`) |
| **Pré-condições** | Reserva rejected com notes `bag_removed` |
| **Passos detalhados** | 1. Comprador remove saco 2. Vendedor Pagamentos ou Operação cancelados 3. Ver ausência em Aceites |
| **Resultado esperado** | Cancelados visíveis; **fora** aba Aceites; Pagamentos → «Cancelados pelo comprador»; sem acções |
| **Componentes afectados** | `live_vendor_studio_panel.dart`, BATATA cancelados rule |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | bag_removed row |
| **Como validar na BD** | rejected + bag_removed |
| **Como validar na UI** | Secção cancelados; não em Aceites |
| **Risco de regressão** | Médio — A085/A129 |
| **Dependências** | A085; A230 |

---

## A095 — P11 aceite over-stock → Stripe sem loop

| Campo | Valor |
|-------|-------|
| **ID** | A095 |
| **Nome** | Fluxo T1 → Aceitar → Pagar abre Stripe sem loop urgente |
| **Pré-condições** | qty 2 stock 1; card urgente T1 disparado; vendedor aceita over-stock |
| **Passos detalhados** | 1. T1: comprador Pagar qty>stock → dialog 2. Vendedor **Aceitar** over-stock 3. Comprador **Pagar** novamente 4. Stripe abre |
| **Resultado esperado** | Sem loop card urgente infinito; checkout qty 2; Stripe URL; sem segunda confirmação bloqueante |
| **Componentes afectados** | studio urgent card, `live_bag_checkout_sheet.dart`, P11 checklist |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | T1 setup + accept |
| **Como validar na BD** | accepted qty 2; order reserva_pendente |
| **Como validar na UI** | Stripe abre; card urgente dismiss |
| **Risco de regressão** | Alto — P11 histórico |
| **Dependências** | A084; A086; A203 |

---

## A096 — P12b aceite → notificação comprador

| Campo | Valor |
|-------|-------|
| **ID** | A096 |
| **Nome** | Aceite dispara R1 card + R2 banner comprador |
| **Pré-condições** | Comprador na live; reserva pending |
| **Passos detalhados** | 1. Vendedor aceita 2. Comprador observa player + saco |
| **Resultado esperado** | Card verde player (R1); banner saco «Aceite · pronto a pagar» (R2); msg chat sistema |
| **Componentes afectados** | `fleaber_live_player_widget.dart`, `live_bag_sheet.dart`, humanizer |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | 2 devices ou bot+browser |
| **Como validar na BD** | accepted timestamp |
| **Como validar na UI** | R1+R2 checklist live-ops |
| **Risco de regressão** | Alto — R1 FAIL histórico |
| **Dependências** | A081; A081 player side |

---

## A097 — Fila recompact após create/remove

| Campo | Valor |
|-------|-------|
| **ID** | A097 |
| **Nome** | `batata_recompact_reservation_queue` mantém FIFO posições |
| **Pré-condições** | ≥2 pending mesmo `live_item_id`; após create ou bag remove |
| **Passos detalhados** | 1. Criar 2 reservas 2. Cancelar/remove primeira 3. Inspeccionar `queue_position` |
| **Resultado esperado** | Posições recompactadas 1..N sem buracos; ordem FIFO preservada |
| **Componentes afectados** | RPC `batata_recompact_reservation_queue`, `LiveReservationQueueService` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | 2+ pending same item |
| **Como validar na BD** | `queue_position` sequencial após RPC |
| **Como validar na UI** | Chips #1 #2 comprador alinhados |
| **Risco de regressão** | Médio — A111/A421 |
| **Dependências** | A111; A421 |

---

## A098 — Staff accept sem canManageReservations

| Campo | Valor |
|-------|-------|
| **ID** | A098 |
| **Nome** | Helper/staff **sem** permissão não aceita reservas |
| **Pré-condições** | Conta staff sem `SellerStaffPermissions.canManageReservations`; live activa |
| **Passos detalhados** | 1. Staff abre studio Operação 2. Tentar Aceitar 3. Ver UI bloqueada |
| **Resultado esperado** | Botões Aceitar/Rejeitar ocultos ou disabled; RPC rejeitado se forçado |
| **Componentes afectados** | `SellerStaffPermissions`, `live_vendor_studio_panel.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | staff user restricted |
| **Como validar na BD** | status permanece pending |
| **Como validar na UI** | CTAs ausentes |
| **Risco de regressão** | Alto — segurança operacional |
| **Dependências** | A099; A078 |

---

## A099 — Owner bypass staff context

| Campo | Valor |
|-------|-------|
| **ID** | A099 |
| **Nome** | Owner seller ignora restrições staff context |
| **Pré-condições** | Conta owner (não helper); mesma live |
| **Passos detalhados** | 1. Owner abre Operação 2. Aceitar/Rejeitar livremente |
| **Resultado esperado** | Todas acções fila activas; RPC success |
| **Componentes afectados** | `SellerStaffContext`, permissions bypass owner |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | owner JWT |
| **Como validar na BD** | process RPC ok |
| **Como validar na UI** | Botões visíveis |
| **Risco de regressão** | Médio |
| **Dependências** | A098 (contraste) |

---

## A100 — Private chat mode toggle seller

| Campo | Valor |
|-------|-------|
| **ID** | A100 |
| **Nome** | Toggle modo chat privado vendedor |
| **Pré-condições** | Live activa; tab Chat studio |
| **Passos detalhados** | 1. Chat → activar modo privado 2. Enviar msg 3. Ver routing |
| **Resultado esperado** | Msgs vão para canal privado; comprador vê thread privada; público não expõe |
| **Componentes afectados** | `live_private_chat` batata, studio chat panel |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | buyer + seller |
| **Como validar na BD** | `live_messages` visibility/private flag |
| **Como validar na UI** | Toggle estado; badge privado |
| **Risco de regressão** | Médio — A426 |
| **Dependências** | A425 RLS |

---

## A101 — Private unread badge

| Campo | Valor |
|-------|-------|
| **ID** | A101 |
| **Nome** | Badge unread chat privado vendedor |
| **Pré-condições** | Msg privada não lida para seller |
| **Passos detalhados** | 1. Comprador envia privado 2. Vendedor vê tab Chat |
| **Resultado esperado** | Badge contador incrementa; limpa ao abrir thread |
| **Componentes afectados** | studio chat unread, `live_private_chat` |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | private message |
| **Como validar na BD** | read flag |
| **Como validar na UI** | Badge número |
| **Risco de regressão** | Baixo |
| **Dependências** | A100 |

---

## A102 — Chat filtro perguntas

| Campo | Valor |
|-------|-------|
| **ID** | A102 |
| **Nome** | Filtro chat «Perguntas» |
| **Pré-condições** | Mix msgs públicas: perguntas + sistema + compras |
| **Passos detalhados** | 1. Chat studio 2. Seleccionar filtro Perguntas |
| **Resultado esperado** | Só perguntas de compradores visíveis; sistema/compra ocultos |
| **Componentes afectados** | `live_vendor_studio_panel.dart` chat filters |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | chat history variado |
| **Como validar na BD** | — |
| **Como validar na UI** | Filtro activo; lista filtrada |
| **Risco de regressão** | Baixo |
| **Dependências** | A105 |

---

## A103 — Chat filtro reservas

| Campo | Valor |
|-------|-------|
| **ID** | A103 |
| **Nome** | Filtro chat «Reservas» |
| **Pré-condições** | Msgs reservation_request/outcome no chat |
| **Passos detalhados** | 1. Chat → filtro Reservas |
| **Resultado esperado** | Só eventos reserva; resto oculto |
| **Componentes afectados** | chat filters, humanizer kinds |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | reservation chat msgs |
| **Como validar na BD** | — |
| **Como validar na UI** | Filtro reservas |
| **Risco de regressão** | Baixo |
| **Dependências** | A082; A081 |

---

## A104 — Chat filtro sistema

| Campo | Valor |
|-------|-------|
| **ID** | A104 |
| **Nome** | Filtro chat «Sistema» |
| **Pré-condições** | Msgs `LiveSystemChatEventKind` no feed |
| **Passos detalhados** | 1. Chat → filtro Sistema |
| **Resultado esperado** | Só msgs sistema/humanizer; users ocultos |
| **Componentes afectados** | `live_system_chat_humanizer.dart`, chat filters |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | system msgs |
| **Como validar na BD** | — |
| **Como validar na UI** | Filtro sistema |
| **Risco de regressão** | Baixo |
| **Dependências** | A128 |

---

## A105 — Username full_name no chat (Z54)

| Campo | Valor |
|-------|-------|
| **ID** | A105 |
| **Nome** | Nome chat = `profiles.full_name` (BATATA) |
| **Pré-condições** | Perfil com `full_name` distinto de email; msgs públicas |
| **Passos detalhados** | 1. Comprador envia msg 2. Vendedor vê chat 3. Vendedor envia msg |
| **Resultado esperado** | Labels usam `full_name`/username app; **não** email cru; inclui msgs da própria vendedora |
| **Componentes afectados** | chat display, BATATA live-ops rule |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | profile full_name |
| **Como validar na BD** | profiles join |
| **Como validar na UI** | Nome correcto em bolhas |
| **Risco de regressão** | Médio — Z54 |
| **Dependências** | — |

---

## A106 — Fotos no chat público (Z54)

| Campo | Valor |
|-------|-------|
| **ID** | A106 |
| **Nome** | Imagens comprador renderizam no chat público seller |
| **Pré-condições** | Comprador envia foto no chat live |
| **Passos detalhados** | 1. Upload imagem chat 2. Vendedor vê preview |
| **Resultado esperado** | Thumbnail/cache visível; tap expand se aplicável |
| **Componentes afectados** | chat image widget, Z54 |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | image attachment |
| **Como validar na BD** | msg media url |
| **Como validar na UI** | Foto visível |
| **Risco de regressão** | Médio |
| **Dependências** | A105 |

---

## A107 — Pagamentos lista convertidas

| Campo | Valor |
|-------|-------|
| **ID** | A107 |
| **Nome** | Tab Pagamentos lista orders convertidas da live |
| **Pré-condições** | ≥1 reserva converted + order pago |
| **Passos detalhados** | 1. Completar venda 2. Operação → Pagamentos 3. Ver linha |
| **Resultado esperado** | Lista com buyer, ref, total (incl. portes); estado pago; link order |
| **Componentes afectados** | payments tab, `_refreshLiveOrderMetrics` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | converted + order |
| **Como validar na BD** | orders com live_id |
| **Como validar na UI** | Linha pagamento |
| **Risco de regressão** | Médio — A087 R5 |
| **Dependências** | A088; A206 |

---

## A108 — Pagamentos stale_reconciled log

| Campo | Valor |
|-------|-------|
| **ID** | A108 |
| **Nome** | Log `reservation.load` inclui `stale_reconciled` count |
| **Pré-condições** | Stale order presente (A088 seed) |
| **Passos detalhados** | 1. Abrir Operação 2. Query `live_vendor_studio_logs` |
| **Resultado esperado** | Evento `reservation.load` com `stale_reconciled` ≥ 1 na 1.ª carga; 0 na 2.ª |
| **Componentes afectados** | `_loadReservationQueue`, `live_vendor_studio_logs` |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | stale seed |
| **Como validar na BD** | `select * from live_vendor_studio_logs where event='reservation.load' and live_id=$id order by created_at desc limit 5` |
| **Como validar na UI** | — |
| **Risco de regressão** | Baixo — observabilidade |
| **Dependências** | A088 |

---

## A109 — live_vendor_studio_logs reservation.accept

| Campo | Valor |
|-------|-------|
| **ID** | A109 |
| **Nome** | Log studio `reservation.accept` com qty metadata |
| **Pré-condições** | Aceite normal ou over-stock |
| **Passos detalhados** | 1. Aceitar reserva 2. Query logs |
| **Resultado esperado** | Row `event='reservation.accept'` com `reserved_qty`, `item_qty`, `live_id` |
| **Componentes afectados** | `FleaberLogger.logStudio`, `_logStudio`, SQL trigger |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | accept action |
| **Como validar na BD** | `live_vendor_studio_logs` reservation.accept |
| **Como validar na UI** | — |
| **Risco de regressão** | Médio — diagnóstico R6 |
| **Dependências** | A081; A420 |

---

## A110 — live_vendor_studio_logs checkout.pay_qty_gate

| Campo | Valor |
|-------|-------|
| **ID** | A110 |
| **Nome** | Log `checkout.pay_qty_gate` ao Pagar qty>stock |
| **Pré-condições** | T1: qty>stock; comprador Pagar |
| **Passos detalhados** | 1. Disparar T1 2. Query logs |
| **Resultado esperado** | Evento `checkout.pay_qty_gate` com request_id, qty pedida, available |
| **Componentes afectados** | `live_in_stream_checkout.dart`, studio logs |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | T1 setup |
| **Como validar na BD** | `live_vendor_studio_logs` checkout.pay_qty_gate |
| **Como validar na UI** | — |
| **Risco de regressão** | Médio — A086/A127 |
| **Dependências** | A086; A127 |

---

## A111 — Multi-comprador mesma fila ordem FIFO

| Campo | Valor |
|-------|-------|
| **ID** | A111 |
| **Nome** | Vários compradores — ordem FIFO na fila seller e chips comprador |
| **Pré-condições** | Stock ≥1; 2+ buyers distintos; reservas sequenciais mesmo artigo |
| **Passos detalhados** | 1. Buyer A reserva (t=0) 2. Buyer B reserva (t=1) 3. Vendedor Operação → No saco 4. Ver ordem #1 A, #2 B 5. Aceitar A primeiro |
| **Resultado esperado** | `queue_position` / `created_at` FIFO; seller vê A antes de B; chips comprador #1/#2; após aceite A, B mantém posição waitlist se stock esgotado |
| **Componentes afectados** | `batata_live_reservation_queue_for_live`, `batata_recompact_reservation_queue`, `live_bag_sheet.dart` chips |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | 2 buyer JWTs; 1 live_item |
| **Como validar na BD** | `order by queue_position, created_at`; positions 1,2 |
| **Como validar na UI** | Ordem seller; chips #1 #2; Espera #N se aplicável |
| **Risco de regressão** | Alto — A2 posições; fairness fila |
| **Dependências** | A097; A192; A421 |

---

## A112 — Multi-comprador race 2 accepts

| Campo | Valor |
|-------|-------|
| **ID** | A112 |
| **Nome** | Race: dois aceites simultâneos — só um ganha stock |
| **Pré-condições** | Stock 1; 2 pending diferentes buyers |
| **Passos detalhados** | 1. Bot dispara accept A e B em paralelo 2. Verificar estados finais |
| **Resultado esperado** | Um `accepted`, outro rejected/skipped ou waitlist; stock nunca negativo; sem double-sold |
| **Componentes afectados** | `batata_process_live_reservation_request` locking, stock SQL |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | parallel accept script |
| **Como validar na BD** | sum accepted qty ≤ stock |
| **Como validar na UI** | — |
| **Risco de regressão** | Alto — integridade stock |
| **Dependências** | A111; A429 |

---

## A113 — Expire reserva automático

| Campo | Valor |
|-------|-------|
| **ID** | A113 |
| **Nome** | Expiração automática reserva pending/accepted |
| **Pré-condições** | Deadline passado; cron ou RPC `expire` |
| **Passos detalhados** | 1. Seed reserva com deadline no passado 2. Trigger expire job ou RPC 3. Refresh fila |
| **Resultado esperado** | `status=expired` (ou skipped conforme SQL); stock libertado; comprador notificado |
| **Componentes afectados** | `batata_process_live_reservation_request` action expire, scheduled job |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | expired deadline seed |
| **Como validar na BD** | status expired |
| **Como validar na UI** | Sai de Pendentes/Aceites |
| **Risco de regressão** | Médio |
| **Dependências** | A091 |

---

## A114 — Waitlist externo visível seller

| Campo | Valor |
|-------|-------|
| **ID** | A114 |
| **Nome** | Waitlist e pedidos externos visíveis na Operação |
| **Pré-condições** | Stock esgotado + nova reserva; ou source externo |
| **Passos detalhados** | 1. Esgotar via aceite 2. Nova reserva 3. Operação Externos/No saco |
| **Resultado esperado** | Linha waitlist com label externo/espera; summary chip Externos incrementa |
| **Componentes afectados** | `live_vendor_studio_panel.dart`, external/waitlist filters |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | waitlist row |
| **Como validar na BD** | pending waitlist position |
| **Como validar na UI** | Secção Externos |
| **Risco de regressão** | Médio — A092 overlap |
| **Dependências** | A192; A092 |

---

## A115 — Gorjeta aparece painel (P15)

| Campo | Valor |
|-------|-------|
| **ID** | A115 |
| **Nome** | Tip/gorjeta visível no painel vendedor |
| **Pré-condições** | Comprador envia gorjeta na live |
| **Passos detalhados** | 1. Enviar tip Stripe 2. Vendedor Pagamentos/KPI |
| **Resultado esperado** | Linha gorjeta; `_liveTipsValueEur` incrementa; separada de vendas |
| **Componentes afectados** | tips tab, `_liveTipsCount`, Stripe tip context |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | tip payment test |
| **Como validar na BD** | tip order type |
| **Como validar na UI** | P15 checklist |
| **Risco de regressão** | Médio |
| **Dependências** | A116; A224 |

---

## A116 — Tip KPI não confunde com venda

| Campo | Valor |
|-------|-------|
| **ID** | A116 |
| **Nome** | KPI vendas exclui gorjetas |
| **Pré-condições** | Live com venda + tip |
| **Passos detalhados** | 1. Pagar artigo 2. Enviar tip 3. Comparar KPIs |
| **Resultado esperado** | `sales_value_eur` ≠ tips; contadores separados; wallet tip distinto |
| **Componentes afectados** | `_notifyOpsTotals`, wallet KPI |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | sale + tip |
| **Como validar na BD** | orders vs tips tables |
| **Como validar na UI** | Dois totais distintos |
| **Risco de regressão** | Médio — R5 confusão |
| **Dependências** | A115; A087 |

---

## A117 — Rifa create seller

| Campo | Valor |
|-------|-------|
| **ID** | A117 |
| **Nome** | Vendedor cria rifa activa na live |
| **Pré-condições** | Live `status=live`; seller owner; sem rifa activa conflict |
| **Passos detalhados** | 1. Operação → bar rifa ou sheet 2. Preencher título, prémio, winners, timer 3. **Criar** 4. Ver estado RPC |
| **Resultado esperado** | RPC `batata_create_live_raffle` ok; row `live_raffles`; ops bar mostra countdown; comprador vê card (A211+) |
| **Componentes afectados** | `LiveRaffleService.createRaffle`, `live_raffle_seller_sheet.dart`, `live_raffle_seller_ops_bar.dart`, RPC `batata_create_live_raffle` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | live_id, title, ends_at |
| **Como validar na BD** | `select * from live_raffles where live_id=$id and status='active'` |
| **Como validar na UI** | Ops bar rifa; countdown formatado |
| **Risco de regressão** | Médio — bloco rifa seller |
| **Dependências** | A118–A120 |

---

## A118 — Rifa close entries

| Campo | Valor |
|-------|-------|
| **ID** | A118 |
| **Nome** | Fechar entradas rifa (stop join) |
| **Pré-condições** | Rifa activa com entradas (A117) |
| **Passos detalhados** | 1. Seller ops bar → **Fechar entradas** 2. Comprador tenta join |
| **Resultado esperado** | `LiveRaffleService.closeEntries`; status entries_closed; join bloqueado; draw ainda possível |
| **Componentes afectados** | `LiveRaffleService.closeEntries`, `live_vendor_studio_panel.dart`, RPC `batata_close_live_raffle_entries` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | raffle_id activa |
| **Como validar na BD** | raffle status entries_closed |
| **Como validar na UI** | Botão draw enabled; join disabled buyer |
| **Risco de regressão** | Médio |
| **Dependências** | A117 |

---

## A119 — Rifa draw winners

| Campo | Valor |
|-------|-------|
| **ID** | A119 |
| **Nome** | Sortear vencedores rifa seller |
| **Pré-condições** | Rifa entries closed; ≥1 entry |
| **Passos detalhados** | 1. Seller → **Sortear** 2. Confirmar 3. Ver winners + chat broadcast |
| **Resultado esperado** | RPC `batata_draw_live_raffle`; rows `live_raffle_winners`; msg chat rifa; rifa status completed |
| **Componentes afectados** | `LiveRaffleService.draw`, `live_raffle_winners`, humanizer raffle kind |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | raffle com entries |
| **Como validar na BD** | winners count = winner_count |
| **Como validar na UI** | Lista vencedores; chat 🎟️ |
| **Risco de regressão** | Alto — fairness draw |
| **Dependências** | A118; A218 |

---

## A120 — Rifa cancel

| Campo | Valor |
|-------|-------|
| **ID** | A120 |
| **Nome** | Cancelar rifa activa |
| **Pré-condições** | Rifa activa ou entries_closed; sem draw |
| **Passos detalhados** | 1. Seller → Cancelar rifa 2. Confirmar |
| **Resultado esperado** | `LiveRaffleService.cancel`; status cancelled; entries inactivas; comprador card some |
| **Componentes afectados** | `LiveRaffleService.cancel`, RPC batata cancel raffle |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | raffle_id |
| **Como validar na BD** | status cancelled |
| **Como validar na UI** | Ops bar vazio |
| **Risco de regressão** | Baixo |
| **Dependências** | A117 |

---

## A121 — Top rifas público toggle

| Campo | Valor |
|-------|-------|
| **ID** | A121 |
| **Nome** | Toggle leaderboard público rifa |
| **Pré-condições** | Rifa com `show_public_leaderboard` |
| **Passos detalhados** | 1. Criar rifa com toggle ON/OFF 2. Comprador vê leaderboard |
| **Resultado esperado** | ON: top participantes visível buyer; OFF: oculto |
| **Componentes afectados** | `createRaffle(showPublicLeaderboard)`, buyer raffle card |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | raffle + entries |
| **Como validar na BD** | `show_public_leaderboard` flag |
| **Como validar na UI** | Leaderboard visible/hidden |
| **Risco de regressão** | Baixo |
| **Dependências** | A117; A217 |

---

## A122 — Rifa ops bar em Operação

| Campo | Valor |
|-------|-------|
| **ID** | A122 |
| **Nome** | Barra operações rifa integrada no painel Operação |
| **Pré-condições** | Rifa activa |
| **Passos detalhados** | 1. Operação tab 2. Localizar `LiveRaffleSellerOpsBar` |
| **Resultado esperado** | Bar com título, countdown, acções close/draw/cancel; não obscurece fila |
| **Componentes afectados** | `live_raffle_seller_ops_bar.dart`, `live_vendor_studio_panel.dart` |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | active raffle |
| **Como validar na BD** | — |
| **Como validar na UI** | Ops bar visible |
| **Risco de regressão** | Baixo — layout |
| **Dependências** | A117 |

---

## A123 — More menu studio

| Campo | Valor |
|-------|-------|
| **ID** | A123 |
| **Nome** | Menu «Mais» studio — acções secundárias |
| **Pré-condições** | Studio activo |
| **Passos detalhados** | 1. Abrir ⋮ / More 2. Percorrer itens |
| **Resultado esperado** | Itens esperados (ajustes, ajuda, etc.) sem regressão navegação |
| **Componentes afectados** | studio more menu, `live_vendor_studio_panel.dart` |
| **Prioridade** | P3 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | — |
| **Como validar na BD** | — |
| **Como validar na UI** | Menu abre; itens clicáveis |
| **Risco de regressão** | Baixo |
| **Dependências** | — |

---

## A124 — Bundle discount «em breve»

| Campo | Valor |
|-------|-------|
| **ID** | A124 |
| **Nome** | Placeholder bundle discount «em breve» |
| **Pré-condições** | Feature flag off / placeholder UI |
| **Passos detalhados** | 1. Localizar CTA bundle no studio 2. Tocar |
| **Resultado esperado** | Label «em breve» ou disabled; **sem** crash; **sem** alterar preços |
| **Componentes afectados** | studio bundle placeholder |
| **Prioridade** | P3 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | — |
| **Como validar na BD** | — |
| **Como validar na UI** | Copy «em breve» |
| **Risco de regressão** | Baixo |
| **Dependências** | — |

---

## A125 — Overbook reject path

| Campo | Valor |
|-------|-------|
| **ID** | A125 |
| **Nome** | Vendedor recusa over-stock no dialog (não aceita qty>stock) |
| **Pré-condições** | qty 2 stock 1 pending |
| **Passos detalhados** | 1. Aceitar → dialog overbook 2. **Cancelar/Recusar** confirmação |
| **Resultado esperado** | Permanece pending; sem accepted; comprador pode ajustar qty ou cancelar |
| **Componentes afectados** | overbook dialog, `batata_process_live_reservation_request` |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | overbook setup |
| **Como validar na BD** | status pending |
| **Como validar na UI** | Dialog dismiss; sem aceite |
| **Risco de regressão** | Médio — par A084 |
| **Dependências** | A084; A082 |

---

## A126 — Aceitar com item esgotado noutro live

| Campo | Valor |
|-------|-------|
| **ID** | A126 |
| **Nome** | Aceite bloqueado/aviso quando stock pool noutro directo (Z82) |
| **Pré-condições** | Mesmo produto/ref em 2 lives; stock bloqueado noutro directo (`blocked_qty`>0) |
| **Passos detalhados** | 1. Reservar na live A 2. Bloquear stock na live B (pool Z82) 3. Tentar aceitar na live A |
| **Resultado esperado** | Aceite falha ou aviso; `batata_live_items_same_stock_pool` reflecte blocked; catálogo Disp correcto (A3) |
| **Componentes afectados** | `batata_live_items_same_stock_pool`, stock RPC, accept SQL |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | 2 lives same product pool |
| **Como validar na BD** | blocked_qty; accept error |
| **Como validar na UI** | Snack erro ou dialog |
| **Risco de regressão** | Alto — Z82 cross-pool |
| **Dependências** | A340–A344 |

---

## A127 — Notas qty_confirm_needed no checkout

| Campo | Valor |
|-------|-------|
| **ID** | A127 |
| **Nome** | RPC `batata_live_mark_qty_confirm_needed` ao Pagar qty>stock |
| **Pré-condições** | Reserva pending qty 2 stock 1; comprador inicia Pagar |
| **Passos detalhados** | 1. Comprador **Pagar** (T1) 2. Gate chama `markQtyConfirmNeeded` 3. Query notes 4. Vendedor vê card urgente |
| **Resultado esperado** | Notes contém `qty_confirm_needed`; persistido via RPC (comprador sem RLS update); card urgente activa; log A110 |
| **Componentes afectados** | `LiveReservationQueueService.markQtyConfirmNeeded`, RPC `batata_live_mark_qty_confirm_needed`, `live_in_stream_checkout.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | request_id, qty>stock |
| **Como validar na BD** | `notes ilike '%qty_confirm_needed%'` |
| **Como validar na UI** | Card R6 vendedor; dialog comprador |
| **Risco de regressão** | Crítico — liga T1 a vendedor; R6 |
| **Dependências** | A086; A110; A128 (negativo chat) |

---

## A128 — ERP format oculto chat público

| Campo | Valor |
|-------|-------|
| **ID** | A128 |
| **Nome** | Strings ERP/qty_confirm **não** aparecem no chat público |
| **Pré-condições** | Reserva com notes `qty_confirm_needed` ou tokens ERP |
| **Passos detalhados** | 1. Disparar T1/A127 2. Ler chat público seller e buyer |
| **Resultado esperado** | Humanizer filtra ERP/qty_confirm; chat limpo; card urgente só no studio (não público) |
| **Componentes afectados** | `live_system_chat_humanizer.dart`, `live_public_chat_line_test.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Unit |
| **Dados necessários** | notes qty_confirm_needed |
| **Como validar na BD** | — |
| **Como validar na UI** | Chat sem tokens técnicos |
| **Risco de regressão** | Médio — UX confiança |
| **Dependências** | A127; A291 |

---

## A129 — Activity «adicionou ao saco» vs cancelado

| Campo | Valor |
|-------|-------|
| **ID** | A129 |
| **Nome** | Actividade: «adicionou ao saco» só pending aberto; cancel remove evento |
| **Pré-condições** | Comprador reserva; depois cancela (`bag_removed`) |
| **Passos detalhados** | 1. Comprador reserva → vendedor vê actividade `🛍️ {name} adicionou {ref} ao saco` (`res-new-{id}`) 2. Comprador cancela saco 3. Vendedor vê `↩ {name} cancelou` e **remove** `res-new`/`res-acc` |
| **Resultado esperado** | `_appendActivity` bagAdd em create pending; `_syncBuyerCancelActivities` remove res-new/res-acc; **sem** «adicionou» após cancel; regra BATATA cancelados |
| **Componentes afectados** | `live_vendor_studio_panel.dart` (`_refreshActivityEvents`, `_syncBuyerCancelActivities`), `LiveOpsActivityKind.bagAdd` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | reserve + bag_remove sequence |
| **Como validar na BD** | rejected bag_removed |
| **Como validar na UI** | Feed actividade coerente; sem duplicados |
| **Risco de regressão** | Alto — BATATA cancelados UX |
| **Dependências** | A085; A094; A230 |

---

## Apêndice A — Resumo A080–A129

| Bloco | IDs | Foco |
|-------|-----|------|
| Fila core | A080–A085 | No saco, accept/reject/skip, overbook, cancelados |
| T1/T2 + KPI + reconcile | A086–A088 | Card urgente, R5 portes, stale reconcile #8 |
| Secções Operação | A089–A094 | Pendentes, Aceites, Sem pagamento, Externos, Histórico, Cancelados |
| Fluxos P11/P12 + staff | A095–A099 | Over-stock Stripe, notificações, recompact, permissões |
| Chat seller | A100–A106 | Privado, filtros, full_name, fotos Z54 |
| Pagamentos + logs | A107–A110 | Lista convertidas, stale log, studio logs |
| Multi-buyer + waitlist | A111–A114 | FIFO, race, expire, waitlist |
| Tips | A115–A116 | Gorjeta P15, KPI separado |
| Rifa seller | A117–A122 | Create, close, draw, cancel, leaderboard, ops bar |
| Misc studio | A123–A126 | More menu, bundle, overbook reject, cross-pool Z82 |
| Qty confirm + actividade | A127–A129 | RPC notes, ERP oculto, actividade saco |

**Total fichas:** 50 (A080–A129).

### Temas transversais (sem ID próprio — cobertos nas fichas acima)

| Tema | Fichas principais |
|------|-------------------|
| T1/T2 card urgente | A086, A127, A110, A204 |
| Over-stock aceite → pagar | A084, A095, A125, A203 |
| Cancelados comprador BATATA | A085, A094, A129, A230 |
| R5 KPI portes | A087, A107, A423 |
| Stale reconcile | A088, A108, A206 |
| FIFO / fairness fila | A111, A097, A421 |
| Rifa seller lifecycle | A117–A120, A122 |
| Staff permissões | A098, A099, A078 |
| Cross-pool stock Z82 | A126, A340 |

---

## Apêndice B — P0 desta faixa (14)

| ID | Nome curto |
|----|------------|
| A080 | Fila No saco |
| A081 | Aceitar reserva |
| A082 | Rejeitar reserva |
| A084 | Aceitar over-stock |
| A085 | Cancelados sem acção |
| A086 | Card urgente T1/T2 |
| A087 | KPI portes R5 |
| A088 | Reconcile stale #8 |
| A094 | Secção cancelados |
| A095 | P11 Stripe pós-aceite |
| A098 | Staff sem permissão |
| A111 | FIFO multi-comprador |
| A127 | qty_confirm_needed RPC |
| A129 | Actividade saco vs cancel |

---

## Apêndice C — Top 10 a automatizar primeiro

| # | ID | Porquê | Tipo |
|---|-----|--------|------|
| 1 | A088 | Reconcile stale — dinheiro sem convert (#8); adapter V0.3a | Integration |
| 2 | A081 | Harness accept H01 — smoke seller ops | Bot + Maestro |
| 3 | A111 | FIFO fairness — regressão A2 | Bot |
| 4 | A129 | Actividade BATATA cancelados — UX confiança | Bot |
| 5 | A127 | qty_confirm RPC — base T1/R6 | Integration |
| 6 | A082 | Reject path — stock libertado | Bot |
| 7 | A097 | Recompact posições — A421 related | Integration |
| 8 | A109 | Logs accept — diagnóstico R6 | Integration |
| 9 | A117 | Rifa create — bloco seller | Bot |
| 10 | A085 | Cancelados sem CTAs — segurança operacional | Maestro + Bot |

---

## Apêndice D — Classificação por tipo (faixa completa)

| Tipo | IDs |
|------|-----|
| **Unit** | A128 |
| **Integration** | A088, A097, A107, A108, A109, A110, A113, A127 |
| **Bot** | A082, A083, A091, A092, A111, A112, A114, A117, A118, A119, A120, A126, A129 |
| **Maestro** | A089, A090, A094, A121, A122 |
| **Manual** | A086, A087, A093, A095, A096, A098, A099, A100, A101, A102, A103, A104, A105, A106, A115, A116, A123, A124, A125 |
| **Híbrido Bot+Maestro** | A080, A081, A084, A085 |

---

## Apêndice E — Riscos críticos (levantamento)

1. **T1/T2 (A086 + A127):** card urgente e `qty_confirm_needed` **só** ao Pagar — regressões R6/R31 repetidas se gate no Reservar.
2. **Stale reconcile (A088):** order `pago` sem `converted` — seller KPI errado; comprador pago sem confirmação; idempotência RPC crítica.
3. **R5 KPI (A087):** valor vendido só artigo — disputas wallet; logs `paid_value_eur` OK mas UI 10 € (sessão histórica).
4. **FIFO / posições (A111 + A097):** multi-comprador ordem errada — fairness e chips A2; recompact após cancel.
5. **Cancelados BATATA (A085 + A129):** botões Aceitar ou actividade «adicionou» após `bag_removed` — violação regra live-ops.
6. **Over-stock loop (A084 + A095):** aceitar → Pagar → loop card urgente sem Stripe — P11 histórico.
7. **Staff permissões (A098):** helper aceita sem autorização — risco operacional/fraud.
8. **Cross-pool Z82 (A126):** aceite quando stock bloqueado noutro directo — double-sell cross-live.
9. **Race accept (A112):** dois aceites stock 1 — stock negativo ou double sold.
10. **Rifa draw integrity (A119):** sorteio duplicado ou sem audit — confiança campanha.

---

*Fim A080–A129. Runner secção 9 — implementação de testes pendente.*
