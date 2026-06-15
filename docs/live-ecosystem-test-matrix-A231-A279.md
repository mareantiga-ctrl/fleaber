# Matriz expandida — A231 a A279

**Área:** Pagamentos extendidos · encomendas pós-live · gorjetas · disputas · rifa social comprador/vendedor  
**Versão:** 1.0 · **2026-06-14**  
**Estado:** Fichas expandidas — **sem implementação de testes**.

Substitui a tabela compacta A231–A279 em `live-ecosystem-test-matrix.md`.

**Nota:** A219–A230 já expandidos em [`live-ecosystem-test-matrix-A190-A230.md`](./live-ecosystem-test-matrix-A190-A230.md) — esta faixa continua em **A231+**. A211–A218 (rifa checkout-adjacent) e A117–A120 (rifa seller) são pré-requisitos sociais; A088 cobre reconcile stale em Operação (manual #8).

---

## A231 — Lista sessões live pós-directo (KPI cards)

| Campo | Valor |
|-------|-------|
| **ID** | A231 |
| **Nome** | `/operacoesLive` — cards sessão com KPIs agregados |
| **Pré-condições** | Seller (ou staff com permissão) autenticado; ≥1 live `status=ended` com vendas ou reservas; rota `/operacoesLive` acessível |
| **Passos detalhados** | 1. Perfil vendedor → **Operações live** (ou navegar `/operacoesLive`) 2. Aguardar `LiveSalesSessionsPageWidget` carregar 3. Verificar cards por sessão 4. Comparar métricas com live conhecida (artigos vendidos, receita, pendentes) 5. Tocar card → detalhe sessão |
| **Resultado esperado** | Lista `LiveSessionSummary` com `articlesSold`, `revenueEur`, `pendingPayments`, `hasAlerts`; realtime refresh via subscriptions; navegação para `LiveSalesSessionDetailPageWidget` |
| **Componentes afectados** | `live_sales_sessions_page_widget.dart`, `live_session_results_service.dart` (`listSummariesForSeller`), `seller_staff_gate.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro + Integration |
| **Dados necessários** | `live_id` ended; orders/reservas seed; seller JWT |
| **Como validar na BD** | `_computeMetrics`: `converted` requests + orders `pago`/`enviado`/`concluido` com `live_id`; `pendingPayments` = pending/accepted + `reserva_pendente` |
| **Como validar na UI** | Card mostra data sessão, receita €, contador pendentes; badge alerta se `hasAlerts` |
| **Risco de regressão** | Alto — KPI pós-live desalinhado com Operação in-stream (A087) |
| **Dependências** | A058 (ended); A206; A087; A223 |

---

## A232 — Timeline estado encomenda `reserva_pendente` → `pago`

| Campo | Valor |
|-------|-------|
| **ID** | A232 |
| **Nome** | Transição visual e BD order live checkout |
| **Pré-condições** | Reserva `accepted`; checkout iniciado; order criada `status=reserva_pendente` com `live_id` e notes `stripe_checkout:` |
| **Passos detalhados** | 1. Comprador Pagar (A205) 2. Antes do Stripe: query order `reserva_pendente` 3. Completar pagamento test 4. Reconcile (A206/A209) 5. Buyer **Minhas encomendas** + seller detalhe sessão |
| **Resultado esperado** | Order `reserva_pendente` → `pago`; label UI «Pago» via `normalizeOrderStatusKey`; reserva → `converted`; timeline coerente em detalhe sessão (`statusLabel`) |
| **Componentes afectados** | `order_cancel_eligibility.dart`, `live_session_results_service.dart` (`_orderStatusLabel`), `minhas_encomendas_widget.dart`, edge settle |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | order uuid; Stripe test session |
| **Como validar na BD** | `orders.status='pago'`; `live_reservation_requests.status='converted'`; notes `stripe_paid:` |
| **Como validar na UI** | Chip verde comprador; linha venda «Pago» no detalhe sessão |
| **Risco de regressão** | Crítico — dinheiro sem estado UI correcto |
| **Dependências** | A206; A209; A223; A088 |

---

## A233 — Refund parcial Stripe pós-live

| Campo | Valor |
|-------|-------|
| **ID** | A233 |
| **Nome** | Reembolso parcial encomenda originada na live |
| **Pré-condições** | Order `pago` com `live_id`; valor parcial definido (ex. portes ou artigo parcial conforme política) |
| **Passos detalhados** | 1. Admin/seller inicia refund parcial (Stripe dashboard ou fluxo app) 2. Ver order + wallet 3. Buyer Minhas encomendas 4. Ver KPI sessão |
| **Resultado esperado** | Refund registado; saldo seller/wallet ajustado; order mantém histórico live; **sem** reverter reserva `converted` para pending |
| **Componentes afectados** | Stripe refund webhooks, `wallet_service.dart`, `orders` fee columns |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | order pago; Stripe refund test |
| **Como validar na BD** | refund row / `orders` notes; wallet transaction débito parcial |
| **Como validar na UI** | Estado encomenda reflecte reembolso parcial; total sessão não duplica |
| **Risco de regressão** | Alto — desalinhamento wallet vs Stripe |
| **Dependências** | A206; A219; A222 |

---

## A234 — Refund total + política stock

| Campo | Valor |
|-------|-------|
| **ID** | A234 |
| **Nome** | Reembolso integral pós-pago live |
| **Pré-condições** | Order `pago` live; política devolução activa |
| **Passos detalhados** | 1. Iniciar devolução/refund total (A222) 2. Processar refund Stripe 3. Ver stock `live_items` e marketplace se TYPE A 4. Ver wallet seller |
| **Resultado esperado** | Refund 100%; wallet seller debita líquido; stock restore conforme política BATATA (pode não repor automaticamente); reserva permanece `converted` |
| **Componentes afectados** | returns/refunds flow, `live_catalog_stock_service.dart`, wallet RPC |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | order pago; seller wallet balance |
| **Como validar na BD** | order status pós-refund; stock qty; wallet_transactions |
| **Como validar na UI** | Estado «Reembolsado» ou equivalente; chat thread se disputa ligada |
| **Risco de regressão** | Alto — stock fantasma ou double-restore |
| **Dependências** | A222; A206; A226 |

---

## A235 — Abrir disputa comprador (encomenda live)

| Campo | Valor |
|-------|-------|
| **ID** | A235 |
| **Nome** | `order_disputes` criada para order com `live_id` |
| **Pré-condições** | Order `pago` ou `enviado`; buyer autenticado; sem disputa aberta |
| **Passos detalhados** | 1. Minhas encomendas → order live (A223) 2. Abrir disputa 3. Preencher motivo + anexos opcionais 4. Submeter |
| **Resultado esperado** | Row `order_disputes` `status=aberta`; order coerente; card disputa no chat se thread existir |
| **Componentes afectados** | `minhas_encomendas_widget.dart`, `order_disputes` table, `chat_page_widget.dart` (`_buildOrderDisputeOpenedCard`) |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | order id com `live_id` |
| **Como validar na BD** | `select * from order_disputes where order_id=$id` |
| **Como validar na UI** | Form disputa; badge estado na lista encomendas |
| **Risco de regressão** | Médio — overlap A221 |
| **Dependências** | A221; A223; A206 |

---

## A236 — Resposta vendedor disputa + chat

| Campo | Valor |
|-------|-------|
| **ID** | A236 |
| **Nome** | Seller responde disputa; thread `order_dispute_replies` |
| **Pré-condições** | A235 completo; seller owner da order |
| **Passos detalhados** | 1. Seller abre chat/encomenda com disputa 2. Responde com texto 3. Buyer vê resposta 4. Verificar transição `respondida_vendedor` |
| **Resultado esperado** | Reply persistida; status disputa actualizado; notificação buyer opcional; sem expor dados internos admin |
| **Componentes afectados** | `chat_page_widget.dart`, `order_dispute_replies.dart`, `OrderDisputesTable().update` |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | dispute id; 2 contas |
| **Como validar na BD** | `order_dispute_replies` count++; `order_disputes.status` |
| **Como validar na UI** | Card disputa no chat; histórico replies |
| **Risco de regressão** | Médio |
| **Dependências** | A235; A210 |

---

## A237 — Escalar disputa para Fleaber (admin)

| Campo | Valor |
|-------|-------|
| **ID** | A237 |
| **Nome** | Estado `escalada_fleaber` + painel admin |
| **Pré-condições** | Disputa em `respondida_vendedor` ou `respondida_comprador`; buyer ou seller escala |
| **Passos detalhados** | 1. Participante escala disputa 2. Admin login → painel disputas 3. Abrir `admin_dispute_sheet` 4. Resolver ou pedir mais info |
| **Resultado esperado** | `status=escalada_fleaber`; métricas admin (`activeDisputes`, `escalated`) incrementam; acção admin fecha ou mantém |
| **Componentes afectados** | `admin_page_widget.dart`, `admin_dispute_sheet.dart`, `order_disputes` |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | dispute escalada; conta admin |
| **Como validar na BD** | `order_disputes.status='escalada_fleaber'` |
| **Como validar na UI** | Admin summary card «Escaladas»; sheet detalhe |
| **Risco de regressão** | Médio — saldo retido admin KPI |
| **Dependências** | A236; A235 |

---

## A238 — Wallet saque (levantamento) seller pós-vendas live

| Campo | Valor |
|-------|-------|
| **ID** | A238 |
| **Nome** | Levantamento wallet após créditos de orders live |
| **Pré-condições** | A219 completo; saldo wallet ≥ mínimo levantamento; seller verificado |
| **Passos detalhados** | 1. Vendedor → Wallet 2. Solicitar levantamento valor X 3. Confirmar 4. Ver histórico transacções |
| **Resultado esperado** | `wallet_transactions` tipo `levantamento`; saldo disponível reduz; **sem** afectar orders `pago` nem comissão já contabilizada (A220) |
| **Componentes afectados** | `wallet_service.dart`, wallet UI, admin métrica levantamentos |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | seller wallet credit; IBAN/método configurado |
| **Como validar na BD** | `wallet_transactions.type='levantamento'`; amount negativo |
| **Como validar na UI** | Saldo actualizado; confirmação UX |
| **Risco de regressão** | Crítico — dinheiro |
| **Dependências** | A219; A220 |

---

## A239 — Notificação comprador order pago live

| Campo | Valor |
|-------|-------|
| **ID** | A239 |
| **Nome** | Push/in-app pós-pagamento saco live |
| **Pré-condições** | Buyer com push activo; A206 completo |
| **Passos detalhados** | 1. Completar pagamento 2. Verificar notificação device/in-app 3. Tocar notificação → encomenda ou player |
| **Resultado esperado** | Notificação única por order (debounce P15); deep link coerente; **sem** spam duplicado reconcile |
| **Componentes afectados** | notifications service, `FleaberStripeCheckoutContext` reconcile hooks |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | buyer device; order pago |
| **Como validar na BD** | notifications table se existir; timestamps |
| **Como validar na UI** | 1 notificação; navegação correcta |
| **Risco de regressão** | Médio — P15 debounce (A174) |
| **Dependências** | A206; A210; A174 |

---

## A240 — Comissão multi-order bag checkout

| Campo | Valor |
|-------|-------|
| **ID** | A240 |
| **Nome** | Fee platform em settle 2+ orders (saco) |
| **Pré-condições** | A208 completo; 2 orders `pago` mesmo Stripe session; seller wallet |
| **Passos detalhados** | 1. Pagar saco multi-linha 2. Inspeccionar cada order fee 3. Somar comissão vs `fee_calculator.dart` 4. Ver wallet seller líquido total |
| **Resultado esperado** | Comissão **por order** correcta; soma líquida seller = total pago − comissões − taxas; sem fee duplicada no settle bag |
| **Componentes afectados** | `fee_calculator.dart`, settle edge bag, `wallet_transactions` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | 2 orders mesmo `stripe_session`; price_total conhecidos |
| **Como validar na BD** | `orders` fee fields ×2; wallet credit = expected net |
| **Como validar na UI** | — (validação BD/calculator) |
| **Risco de regressão** | Crítico — A220 desalinhamento multi-linha |
| **Dependências** | A208; A220; A219 |

---

## A241 — Gorjeta KPI Operação vs vendas (P15)

| Campo | Valor |
|-------|-------|
| **ID** | A241 |
| **Nome** | Painel in-stream: tips separados de `sales_value_eur` |
| **Pré-condições** | Live activa; 1 venda convertida + 1 gorjeta (A224) |
| **Passos detalhados** | 1. Comprador paga artigo (A206) 2. Envia gorjeta (A174) 3. Seller Operação → Pagamentos/KPI 4. Comparar `_liveTipsValueEur` vs vendas |
| **Resultado esperado** | KPI vendas ≠ gorjetas; contadores separados; tip não entra em `articlesSold` nem comissão venda |
| **Componentes afectados** | `live_vendor_studio_panel.dart` (`_notifyOpsTotals`, `_liveTipsCount`), `live_tip_flow.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | sale + tip amounts |
| **Como validar na BD** | `live_tips` vs `orders` separados |
| **Como validar na UI** | P15 checklist; dois totais distintos |
| **Risco de regressão** | Médio — confusão R5 (A087/A116) |
| **Dependências** | A115; A116; A224; A174 |

---

## A242 — Gorjeta KPI pós-live sessão (P15)

| Campo | Valor |
|-------|-------|
| **ID** | A242 |
| **Nome** | Tips incluídos no resumo `/resultadosLive` sem misturar receita artigos |
| **Pré-condições** | Live `ended`; tips e vendas na mesma sessão |
| **Passos detalhados** | 1. Abrir detalhe sessão (A231) 2. Tab estatísticas / vendas 3. Localizar linha gorjetas se exposta 4. Comparar `LiveSessionStats` |
| **Resultado esperado** | Receita artigos = orders+converted; gorjetas agregadas à parte ou excluídas de `totalRevenueEur` artigos; coerente com in-stream A241 |
| **Componentes afectados** | `live_session_results_service.dart`, `live_sales_session_detail_page_widget.dart` |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | ended live; tips + orders seed |
| **Como validar na BD** | sum orders vs sum tips por `live_id` |
| **Como validar na UI** | KPI sessão não soma tip como «artigo vendido» |
| **Risco de regressão** | Médio |
| **Dependências** | A231; A241; A224 |

---

## A243 — Detectar stale orders na lista sessões

| Campo | Valor |
|-------|-------|
| **ID** | A243 |
| **Nome** | Alerta `hasAlerts` — order `pago` sem reserva `converted` |
| **Pré-condições** | Seed stale: order `pago` + reserva `accepted` não converted (manual #8) |
| **Passos detalhados** | 1. Seed `live_ops_test_seed.sql` stale row 2. Abrir `/operacoesLive` 3. Ver badge alerta no card sessão 4. Entrar detalhe → tab vendas/pendentes |
| **Resultado esperado** | `hasAlerts=true`; `pendingPayments` ou conflitos visíveis; não esconde stale |
| **Componentes afectados** | `LiveSessionResultsService._computeMetrics`, `live_sales_sessions_page_widget.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | stale seed; `live_id` |
| **Como validar na BD** | order `pago` + request ≠ `converted` |
| **Como validar na UI** | Badge alerta; copy «pendentes» ou conflitos |
| **Risco de regressão** | Crítico — manual #8 visibilidade |
| **Dependências** | A088; A231; A249 |

---

## A244 — Reconcile stale a partir do detalhe sessão

| Campo | Valor |
|-------|-------|
| **ID** | A244 |
| **Nome** | Acção refresh/reconcile no pós-live converte órfãos |
| **Pré-condições** | A243; seller owner sessão |
| **Passos detalhados** | 1. Abrir detalhe sessão com stale 2. Pull refresh ou reabrir página 3. Verificar RPC `batata_live_reconcile_stripe_order` disparado (via service refresh) 4. Confirmar conversão |
| **Resultado esperado** | Reserva → `converted`; alerta limpa; KPI receita alinhada; idempotente na 2.ª visita |
| **Componentes afectados** | `LiveSessionResultsService.detailForLive`, `LiveReservationQueueService.reconcileStalePaidReservationsForLive`, `tool/live_ops_staging_check.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | stale seed |
| **Como validar na BD** | `converted` + log `stale_reconciled` |
| **Como validar na UI** | Alerta desaparece; linha venda «Pago» |
| **Risco de regressão** | Crítico — dinheiro sem conversão |
| **Dependências** | A088; A243; A209 |

---

## A245 — Export / partilha resumo sessão

| Campo | Valor |
|-------|-------|
| **ID** | A245 |
| **Nome** | Exportar ou copiar resumo comercial da sessão |
| **Pré-condições** | Detalhe sessão carregado com vendas |
| **Passos detalhados** | 1. Detalhe sessão → acção export/share se disponível 2. Verificar conteúdo (data, refs, totais) 3. Validar sem PII excessiva |
| **Resultado esperado** | Resumo legível (CSV, share intent ou clipboard); totais = BD; refs correctas |
| **Componentes afectados** | `live_sales_session_detail_page_widget.dart`, `LiveSessionResultsService` |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | sessão com ≥2 vendas |
| **Como validar na BD** | totais export = query orders |
| **Como validar na UI** | Ficheiro/texto partilhado coerente |
| **Risco de regressão** | Baixo |
| **Dependências** | A231 |

---

## A246 — Filtro encomendas comprador — contexto live

| Campo | Valor |
|-------|-------|
| **ID** | A246 |
| **Nome** | Minhas encomendas destaca/filtra orders com `live_id` |
| **Pré-condições** | Buyer com orders marketplace + live |
| **Passos detalhados** | 1. Minhas encomendas 2. Identificar orders live (badge/link A223) 3. Se filtro existir: aplicar «Live» 4. Abrir order → navegar para replay se ended |
| **Resultado esperado** | Orders live identificáveis; filtro não esconde marketplace; `live_id` navegável |
| **Componentes afectados** | `minhas_encomendas_widget.dart`, `orders_live_context_batata` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | orders com/sem `live_id` |
| **Como validar na BD** | `orders.live_id` not null nas linhas filtradas |
| **Como validar na UI** | Badge live; link player |
| **Risco de regressão** | Baixo |
| **Dependências** | A223; A206 |

---

## A247 — Filtro encomendas seller — status e disputa

| Campo | Valor |
|-------|-------|
| **ID** | A247 |
| **Nome** | Lista vendas sessão filtra por estado pago/disputa/devolução |
| **Pré-condições** | Sessão com orders `pago`, `em_devolucao` ou disputa aberta |
| **Passos detalhados** | 1. Detalhe sessão → tab vendas 2. Aplicar filtros/chips status 3. Verificar contagem vs BD |
| **Resultado esperado** | Filtros reduzem lista correctamente; disputas visíveis; `normalizeOrderStatusKey` labels PT |
| **Componentes afectados** | `live_sales_session_detail_page_widget.dart`, `live_session_results_service.dart` |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration |
| **Dados necessários** | orders multi-status |
| **Como validar na BD** | count por status = UI |
| **Como validar na UI** | Chips filtro; lista vazia quando sem match |
| **Risco de regressão** | Baixo |
| **Dependências** | A231; A235 |

---

## A248 — Manual #8 playbook reconcile órfão

| Campo | Valor |
|-------|-------|
| **ID** | A248 |
| **Nome** | Procedimento operacional stale order documentado e reproduzível |
| **Pré-condições** | Staging com order `pago` órfã; acesso `live_ops_staging_check` |
| **Passos detalhados** | 1. Seguir `live-ops-automacao-batata.md` V0.3a (#7) 2. Seed stale 3. Abrir Operação OU detalhe sessão 4. RPC reconcile 5. Verificar checklist manual #8 |
| **Resultado esperado** | Playbook 100% reproduzível; estados finais documentados; suporte consegue repetir sem código |
| **Componentes afectados** | `tool/live_ops_staging_check.dart`, `live-ops-automacao-batata.md`, runner manifest A088/A244 |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | staging credentials; stale seed SQL |
| **Como validar na BD** | checklist #7/#8 verde |
| **Como validar na UI** | KPI + saco coerentes pós-fix |
| **Risco de regressão** | Crítico — runbook desactualizado |
| **Dependências** | A088; A244; A209 |

---

## A249 — Manual #8 idempotência double-reconcile

| Campo | Valor |
|-------|-------|
| **ID** | A249 |
| **Nome** | 2.ª chamada reconcile não duplica crédito/conversão |
| **Pré-condições** | A244 completo; stale já reconciliado |
| **Passos detalhados** | 1. Repetir `batata_live_reconcile_stripe_order` ou refresh painel 2. Query wallet + reserva 3. Ver logs `stale_reconciled` |
| **Resultado esperado** | Reserva permanece `converted`; wallet **sem** segundo crédito; RPC idempotente (A209 pattern) |
| **Componentes afectados** | `batata_live_reconcile_stripe_order`, `LiveReservationQueueService.reconcileStalePaidOrder` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | reconciled order id |
| **Como validar na BD** | 1 wallet credit; 1 converted; 2.ª RPC no-op |
| **Como validar na UI** | — |
| **Risco de regressão** | Crítico — double money |
| **Dependências** | A209; A244; A248 |

---

## A250 — H04 participar rifa (Bot + Maestro)

| Campo | Valor |
|-------|-------|
| **ID** | A250 |
| **Nome** | Suite H04: bot join + buyer Maestro «Participar na Rifa (+1)» |
| **Pré-condições** | Live `status=live` com rifa activa (A117); `.maestro/.env` com `MAESTRO_LIVE_ID`; buyer JWT |
| **Passos detalhados** | 1. Bot seed rifa + opcional join 2. Maestro `v2_buyer_raffle_bag.yaml` 3. Player → «Rifa da Live» → «Participar na Rifa (+1)» 4. Ver sheet «Ganha mais rifas» |
| **Resultado esperado** | `viewer.joined=true`; `ticketBalance` +1; BD `raffle_entries` incrementa; sem crash saco/rifa |
| **Componentes afectados** | `live_raffle_buyer_card.dart`, `LiveRaffleService.join`, `.maestro/flows/v2_buyer_raffle_bag.yaml`, bot H04 |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Híbrido Bot+Maestro |
| **Dados necessários** | `live_id`, `raffle_id`, buyer |
| **Como validar na BD** | entries buyer +1 |
| **Como validar na UI** | Maestro asserts «Participar» / «Ganha mais rifas» |
| **Risco de regressão** | Alto — smoke release rifa |
| **Dependências** | A212; A117; A145; H04 |

---

## A251 — Seguir vendedor bónus rifa (+follow)

| Campo | Valor |
|-------|-------|
| **ID** | A251 |
| **Nome** | Follow seller durante rifa — `follow_bonus_claimed` |
| **Pré-condições** | Buyer joined (A250); seller com perfil seguível; rifa activa |
| **Passos detalhados** | 1. Painel rifa → Seguir vendedor 2. Confirmar follow 3. Ver contador entradas 4. Repetir — sem 2.º bónus |
| **Resultado esperado** | Bónus entradas conforme regra produto; `follow_bonus_claimed=true`; UI «+N entradas» |
| **Componentes afectados** | `live_raffle_buyer_card.dart`, `LiveRaffleService`, follow RPC |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | buyer not following seller |
| **Como validar na BD** | `follow_bonus_claimed`; entries delta |
| **Como validar na UI** | Estado seguindo; tickets actualizados |
| **Risco de regressão** | Médio |
| **Dependências** | A250; A212 |

---

## A252 — Share intent rifa +2 (buyer)

| Campo | Valor |
|-------|-------|
| **ID** | A252 |
| **Nome** | Partilha social — `batata_claim_live_raffle_share_intent` |
| **Pré-condições** | Buyer joined; `share_bonus_claimed=false` |
| **Passos detalhados** | 1. Tocar Partilhar no painel rifa 2. Completar share intent (ou simular claim RPC) 3. Ver feedback +2 |
| **Resultado esperado** | `LiveRaffleShareClaimResult.ok`; entries +2; `share_bonus_claimed=true` |
| **Componentes afectados** | `LiveRaffleService.claimShareIntent`, share sheet UI |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | joined buyer |
| **Como validar na BD** | entries +2; flag claimed |
| **Como validar na UI** | Toast «+2 entradas» |
| **Risco de regressão** | Baixo |
| **Dependências** | A213; A250 |

---

## A253 — Referral link ensure + visita

| Campo | Valor |
|-------|-------|
| **ID** | A253 |
| **Nome** | `ensureReferralLink` + `registerReferralVisit` |
| **Pré-condições** | Rifa activa; referrer joined |
| **Passos detalhados** | 1. Buyer gera/copia link referral 2. Visitante abre link (novo user ou anónimo) 3. `registerReferralVisit` 4. Ver pending qualify |
| **Resultado esperado** | Link único por raffle; visita registada; referrer ainda sem bónus até qualify |
| **Componentes afectados** | `LiveRaffleService.ensureReferralLink`, `registerReferralVisit`, deep link handler |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration |
| **Dados necessários** | 2 users; referral token |
| **Como validar na BD** | referral visit row |
| **Como validar na UI** | Link copiável; contador «visitas» se exposto |
| **Risco de regressão** | Médio |
| **Dependências** | A214; A250 |

---

## A254 — Referral qualify 60s (batch)

| Campo | Valor |
|-------|-------|
| **ID** | A254 |
| **Nome** | `qualifyReferralVisits` após permanência |
| **Pré-condições** | A253; visitante ≥60s no player (regra A214) |
| **Passos detalhados** | 1. Manter visitante no player 60s+ 2. Trigger qualify (timer ou RPC batch) 3. Ver entradas referrer +2 |
| **Resultado esperado** | Referrer +2 entradas; visita marcada qualified; sem qualify em <60s |
| **Componentes afectados** | `LiveRaffleService.qualifyReferralVisits`, player dwell tracking |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | referral visit id |
| **Como validar na BD** | referrer entries +2; visit qualified_at |
| **Como validar na UI** | Referrer vê tickets subir |
| **Risco de regressão** | Médio — timing flake |
| **Dependências** | A214; A253 |

---

## A255 — Leaderboard buyer top 5 realtime

| Campo | Valor |
|-------|-------|
| **ID** | A255 |
| **Nome** | Ranking comprador actualizado com entradas |
| **Pré-condições** | ≥3 participantes; `show_public_leaderboard=true` (A121) |
| **Passos detalhados** | 1. Bot seed entries variadas 2. Buyer abre leaderboard rifa 3. Comparar ordem com query BD 4. Buyer actual destacado |
| **Resultado esperado** | Top 5 desc por tickets; highlight self; refresh após join/share |
| **Componentes afectados** | `live_raffle_buyer_card.dart`, `LiveRaffleState.leaderboard` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | entries seed |
| **Como validar na BD** | `order by tickets desc limit 5` |
| **Como validar na UI** | Lista top 5; posição buyer |
| **Risco de regressão** | Baixo — R6 |
| **Dependências** | A215; A121; A250 |

---

## A256 — Leaderboard seller ops bar

| Campo | Valor |
|-------|-------|
| **ID** | A256 |
| **Nome** | Vendedor vê resumo participantes na ops bar |
| **Pré-condições** | Rifa activa; entries > 0 |
| **Passos detalhados** | 1. Seller Operação → `LiveRaffleSellerOpsBar` 2. Ver contador participantes/entradas 3. Toggle top público ON/OFF (A121) |
| **Resultado esperado** | Ops bar mostra métricas; toggle reflecte em buyer card; não bloqueia fila reservas |
| **Componentes afectados** | `live_raffle_seller_ops_bar.dart`, `live_vendor_studio_panel.dart`, A121 toggle |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | active raffle + entries |
| **Como validar na BD** | count distinct buyers entries |
| **Como validar na UI** | Ops bar visible; toggle funcional |
| **Risco de regressão** | Baixo — layout A122 |
| **Dependências** | A122; A121; A117 |

---

## A257 — FIFO integridade ordem entradas (seller)

| Campo | Valor |
|-------|-------|
| **ID** | A257 |
| **Nome** | Ordem cronológica entradas preservada no sorteio |
| **Pré-condições** | Múltiplos buyers join sequencial (bots) |
| **Passos detalhados** | 1. Bot A join t0 2. Bot B join t1 3. Inspeccionar payload draw/audit 4. Draw (A261) |
| **Resultado esperado** | Entradas com `created_at` FIFO; draw weighted fair; sem inversão timestamps |
| **Componentes afectados** | `live_raffle_service.dart`, draw RPC, entries table |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | timed joins |
| **Como validar na BD** | entries `created_at` ordering |
| **Como validar na UI** | — |
| **Risco de regressão** | Médio — confiança sorteio |
| **Dependências** | A117; A250 |

---

## A258 — Deep link `?ref=` entrada player rifa

| Campo | Valor |
|-------|-------|
| **ID** | A258 |
| **Nome** | Abrir live via link referral pré-preenche contexto rifa |
| **Pré-condições** | Link `fleaberLivePlayer?liveId=X&ref=Y` válido |
| **Passos detalhados** | 1. Abrir deep link cold start 2. Player carrega 3. Ver atribuição referral 4. Join opcional |
| **Resultado esperado** | `registerReferralVisit` disparado; painel rifa acessível; sem crash auth |
| **Componentes afectados** | `fleaber_live_player_widget.dart`, deep link routing, `LiveRaffleService` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | referral deep link |
| **Como validar na BD** | visit row com ref param |
| **Como validar na UI** | Player abre; rifa CTA visível |
| **Risco de regressão** | Médio |
| **Dependências** | A253; A145 |

---

## A259 — Follow + notificação debounce rifa

| Campo | Valor |
|-------|-------|
| **ID** | A259 |
| **Nome** | Seguir vendedor não dispara spam notificações (P15 overlap) |
| **Pré-condições** | Buyer segue durante rifa; notificações ON |
| **Passos detalhados** | 1. A251 follow 2. Observar notificações 60s 3. Draw iminente — 1 notificação draw max |
| **Resultado esperado** | ≤1 notificação follow; draw notif única; debounce alinhado P15 |
| **Componentes afectados** | notifications, follow service, raffle events |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | device push |
| **Como validar na BD** | notification timestamps spacing |
| **Como validar na UI** | Sem flood centro notificações |
| **Risco de regressão** | Médio |
| **Dependências** | A251; A174; A265 |

---

## A260 — Share claim dedupe janela curta

| Campo | Valor |
|-------|-------|
| **ID** | A260 |
| **Nome** | Re-share imediato não duplica +2 |
| **Pré-condições** | A252 completo; `share_bonus_claimed=true` |
| **Passos detalhados** | 1. Tocar Partilhar novamente <30s 2. Tentar claim RPC duplicado 3. Ver entries |
| **Resultado esperado** | Segundo claim rejeitado ou no-op; entries estáveis; mensagem UX clara |
| **Componentes afectados** | `claimShareIntent`, dedupe server-side |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | buyer claimed |
| **Como validar na BD** | entries unchanged; error code duplicate |
| **Como validar na UI** | «Já reclamaste» ou equivalente |
| **Risco de regressão** | Médio — farming entradas |
| **Dependências** | A252; A213 |

---

## A261 — Draw manual seller (RPC)

| Campo | Valor |
|-------|-------|
| **ID** | A261 |
| **Nome** | Vendedor dispara sorteio — `batata_draw_live_raffle_winners` |
| **Pré-condições** | Rifa `entries_closed` ou timer zero; entries > 0 |
| **Passos detalhados** | 1. Seller ops bar → Sortear 2. Confirmar 3. Ver winners BD + UI buyer |
| **Resultado esperado** | `status=drawn`; `winner_id`(s) persistidos; `drawn_at` preenchido; buyer card mostra resultado |
| **Componentes afectados** | `LiveRaffleService.draw`, `live_raffle_seller_ops_bar.dart`, A119 |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | raffle_id; entries |
| **Como validar na BD** | winners + `drawn_at` |
| **Como validar na UI** | Modal/banner vencedor |
| **Risco de regressão** | Alto — integridade sorteio |
| **Dependências** | A119; A118; A218 |

---

## A262 — Draw auto ao expirar timer

| Campo | Valor |
|-------|-------|
| **ID** | A262 |
| **Nome** | Timer zero → close + draw automático (se política activa) |
| **Pré-condições** | Rifa com `ends_at` próximo; entries > 0 |
| **Passos detalhados** | 1. Observar countdown A216 2. Ao zero: entries fecham 3. Draw auto ou CTA seller 4. Ver estado final |
| **Resultado esperado** | `isActive=false`; join disabled; draw executado conforme config; chat anúncio |
| **Componentes afectados** | timer widget, `LiveRaffleService.close`, draw job |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot + Manual |
| **Dados necessários** | `ends_at` mockável |
| **Como validar na BD** | status drawn/closed |
| **Como validar na UI** | Timer 00:00; CTA join off |
| **Risco de regressão** | Médio — race timer/draw |
| **Dependências** | A216; A118; A261 |

---

## A263 — Audit trail winners BD

| Campo | Valor |
|-------|-------|
| **ID** | A263 |
| **Nome** | Sorteio auditável — `tickets_at_draw` por winner |
| **Pré-condições** | A261 completo |
| **Passos detalhados** | 1. Query winners payload 2. Comparar `tickets_at_draw` com snapshot pré-draw 3. Verificar imutabilidade pós-draw |
| **Resultado esperado** | Winners com tickets congelados; sem alteração entries pós-draw; log RPC ok |
| **Componentes afectados** | draw RPC response, winners table, `LiveRaffleWinner` |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | drawn raffle id |
| **Como validar na BD** | winners rows + tickets_at_draw |
| **Como validar na UI** | — |
| **Risco de regressão** | Alto — disputas legais |
| **Dependências** | A261; A119 |

---

## A264 — Chat broadcast sorteio (🎟️ Rifa:)

| Campo | Valor |
|-------|-------|
| **ID** | A264 |
| **Nome** | Anúncio draw no chat público humanizado |
| **Pré-condições** | A261; chat público activo |
| **Passos detalhados** | 1. Executar draw 2. Ver `live_messages` chat 3. Confirmar prefixo `🎟️ Rifa:` |
| **Resultado esperado** | Mensagem sistema/chat com vencedor(es); humanizer activo; dedupe R7 |
| **Componentes afectados** | raffle broadcast, `live_system_chat_humanizer.dart`, A217 |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | live_id drawn |
| **Como validar na BD** | `live_messages` body prefix |
| **Como validar na UI** | Chat legível; sem spam |
| **Risco de regressão** | Médio — R7 |
| **Dependências** | A218; A217; A261 |

---

## A265 — Push notification vencedor buyer

| Campo | Valor |
|-------|-------|
| **ID** | A265 |
| **Nome** | Vencedor recebe push «Ganhaste a rifa» |
| **Pré-condições** | Buyer winner com push ON; A261 |
| **Passos detalhados** | 1. Draw com buyer winner 2. Verificar push device 3. Tocar → player ou prémio info |
| **Resultado esperado** | Push única ao winner; não enviada a não-winners; deep link válido |
| **Componentes afectados** | notifications service, draw hook |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | winner device token |
| **Como validar na BD** | notification row winner_id |
| **Como validar na UI** | Push recebida 1× |
| **Risco de regressão** | Médio |
| **Dependências** | A261; A218; A259 |

---

## A266 — Push notification resumo draw seller

| Campo | Valor |
|-------|-------|
| **ID** | A266 |
| **Nome** | Seller notificado sorteio concluído |
| **Pré-condições** | Seller push ON; A261 |
| **Passos detalhados** | 1. Draw completo 2. Ver push seller 3. Abrir → ops bar ou detalhe rifa |
| **Resultado esperado** | Notificação resumo (vencedor, entradas totais); sem duplicar A265 |
| **Componentes afectados** | seller notifications, draw completion |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | seller device |
| **Como validar na BD** | notification type draw_complete |
| **Como validar na UI** | Push seller recebida |
| **Risco de regressão** | Baixo |
| **Dependências** | A261; A122 |

---

## A267 — Timer rifa em VOD — join disabled

| Campo | Valor |
|-------|-------|
| **ID** | A267 |
| **Nome** | Replay gravado: countdown histórico; join/participar bloqueado |
| **Pré-condições** | Live `status=ended`; rifa estava activa ou drawn; buyer em replay (`_isVodReplay`) |
| **Passos detalhados** | 1. Abrir player gravado 2. Abrir painel rifa 3. Tentar Participar 4. Ver timer estático ou estado drawn |
| **Resultado esperado** | `joined` read-only histórico; CTA join disabled; timer não decrementa em tempo real |
| **Componentes afectados** | `fleaber_live_player_widget.dart` (`_isVodReplay`), `live_raffle_buyer_card.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | ended live + playback_id |
| **Como validar na BD** | raffle status drawn/ended |
| **Como validar na UI** | Sem CTA «Participar (+1)» activo |
| **Risco de regressão** | Alto — commerce VOD rules |
| **Dependências** | A295; A310; A216 |

---

## A268 — Participar rifa só em live activa

| Campo | Valor |
|-------|-------|
| **ID** | A268 |
| **Nome** | Guard `_liveIsActive` bloqueia join em ended |
| **Pré-condições** | Live ended; rifa row ainda presente historicamente |
| **Passos detalhados** | 1. Player gravado 2. Sidebar «Rifa da Live» 3. Ver estado 4. Contrastar com live activa A250 |
| **Resultado esperado** | Join RPC não chamado; UI mostra resultado histórico ou «rifa terminada» |
| **Componentes afectados** | player guards, `LiveRaffleService.join` client gate |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration |
| **Dados necessários** | ended vs live same seller |
| **Como validar na BD** | sem new entries pós-ended |
| **Como validar na UI** | Join absent/disabled |
| **Risco de regressão** | Crítico — rifa fantasma em VOD |
| **Dependências** | A267; A250; A058 |

---

## A269 — Share/referral disabled em VOD

| Campo | Valor |
|-------|-------|
| **ID** | A269 |
| **Nome** | Bónus share/referral não disponíveis em replay |
| **Pré-condições** | A267; buyer em VOD |
| **Passos detalhados** | 1. Abrir painel rifa gravado 2. Verificar ausência Partilhar/Referral activos 3. Tentar deep link referral |
| **Resultado esperado** | CTAs share/referral hidden ou disabled; `registerReferralVisit` não credita em ended |
| **Componentes afectados** | `live_raffle_buyer_card.dart`, referral guards |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | ended live referral link |
| **Como validar na BD** | no new visits post-ended |
| **Como validar na UI** | Botões share greyed |
| **Risco de regressão** | Médio — farming VOD |
| **Dependências** | A267; A253; A252 |

---

## A270 — Dedupe chat rifa stress (R7 extended)

| Campo | Valor |
|-------|-------|
| **ID** | A270 |
| **Nome** | Rajada eventos rifa (join, +2, draw) sem spam chat |
| **Pré-condições** | Live activa; bot dispara 5+ eventos rifa em 10s |
| **Passos detalhados** | 1. Bot join+share+referral qualify rápido 2. Ver chat público 3. Contar linhas `🎟️ Rifa:` |
| **Resultado esperado** | Dedupe R7 — máx 1 linha por tipo em janela 5s; chat legível |
| **Componentes afectados** | `live_system_chat_humanizer.dart`, A217 |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | live_id; bot flood |
| **Como validar na BD** | `live_messages` sem duplicata body 5s |
| **Como validar na UI** | Chat não scroll infinito rifa |
| **Risco de regressão** | Médio |
| **Dependências** | A217; A250; A264 |

---

## A271 — Maestro smoke `v2_buyer_raffle_bag`

| Campo | Valor |
|-------|-------|
| **ID** | A271 |
| **Nome** | Flow Maestro comprador rifa+saco sem falha |
| **Pré-condições** | `.maestro/.env` seeded; APK debug; emulador |
| **Passos detalhados** | 1. `maestro test .maestro/flows/v2_buyer_raffle_bag.yaml` 2. Ver optional asserts 3. Logs sem timeout |
| **Resultado esperado** | Login buyer → player → rifa optional → saco abre; exit 0 |
| **Componentes afectados** | `.maestro/flows/v2_buyer_raffle_bag.yaml`, subflows login |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | MAESTRO_LIVE_ID; buyer creds |
| **Como validar na BD** | opcional entries +1 |
| **Como validar na UI** | Maestro green |
| **Risco de regressão** | Alto — CI smoke |
| **Dependências** | A250; A190; A071 |

---

## A272 — Maestro seller harness + rifa ops

| Campo | Valor |
|-------|-------|
| **ID** | A272 |
| **Nome** | `v2_seller_harness_accept` + ops bar rifa visível |
| **Pré-condições** | Harness live; rifa activa seed |
| **Passos detalhados** | 1. Maestro seller harness flow 2. Ver Operação 3. Assert ops bar rifa 4. Aceitar reserva paralela (H07) |
| **Resultado esperado** | Harness não crash; ops bar presente; fila reservas funcional |
| **Componentes afectados** | `.maestro/flows/v2_seller_harness_accept.yaml`, `maestro_seller_studio_page_widget.dart`, A122 |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | seller creds; live seed |
| **Como validar na BD** | — |
| **Como validar na UI** | Maestro green; ops bar |
| **Risco de regressão** | Médio |
| **Dependências** | A071; A117; A122; H07 |

---

## A273 — Editar prémio rifa mid-live (seller)

| Campo | Valor |
|-------|-------|
| **ID** | A273 |
| **Nome** | `LiveRafflePrizeEditSheet` actualiza título/imagem |
| **Pré-condições** | Rifa activa sem draw |
| **Passos detalhados** | 1. Seller → editar prémio 2. Mudar título/foto 3. Guardar 4. Buyer refresh card |
| **Resultado esperado** | BD actualizada; buyer card reflecte sem restart app; entries preservadas |
| **Componentes afectados** | `live_raffle_prize_edit_sheet.dart`, `LiveRaffleService` update |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | raffle_id |
| **Como validar na BD** | prize title/image url |
| **Como validar na UI** | Buyer vê novo prémio |
| **Risco de regressão** | Baixo |
| **Dependências** | A117; A274 |

---

## A274 — Prémio rifa display buyer card

| Campo | Valor |
|-------|-------|
| **ID** | A274 |
| **Nome** | Imagem e título prémio no `LiveRaffleBuyerCard` |
| **Pré-condições** | Rifa com prize image_url |
| **Passos detalhados** | 1. Abrir painel rifa buyer 2. Ver `BatataCachedImage` prémio 3. Placeholder se sem foto |
| **Resultado esperado** | Prémio legível; countdown; tickets badge; layout BATATA sidebar |
| **Componentes afectados** | `live_raffle_buyer_card.dart`, `LiveRaffleSidebarButton` |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | raffle com imagem |
| **Como validar na BD** | prize image field |
| **Como validar na UI** | Thumbnail ≠ vazio |
| **Risco de regressão** | Baixo — layout player |
| **Dependências** | A117; A145 |

---

## A275 — Cancel rifa mid-entries buyer UX

| Campo | Valor |
|-------|-------|
| **ID** | A275 |
| **Nome** | Seller cancela rifa — comprador vê estado cancelado |
| **Pré-condições** | Rifa activa com entries; sem draw |
| **Passos detalhados** | 1. Seller A120 cancel 2. Buyer reabre painel 3. Ver mensagem cancelada 4. Entries inactivas |
| **Resultado esperado** | Card some ou mostra «cancelada»; join disabled; **sem** refund entradas (não pagas) |
| **Componentes afectados** | `LiveRaffleService.cancel`, buyer card state |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | raffle com entries |
| **Como validar na BD** | status cancelled |
| **Como validar na UI** | Buyer UX clara |
| **Risco de regressão** | Baixo |
| **Dependências** | A120; A250 |

---

## A276 — Rifa +2 pós-checkout idempotência

| Campo | Valor |
|-------|-------|
| **ID** | A276 |
| **Nome** | Bónus A211 não duplica em reconcile/repay |
| **Pré-condições** | Rifa activa; order pago; +2 já aplicado |
| **Passos detalhados** | 1. Pagar (A206) 2. Ver +2 entradas 3. Repetir reconcile (A209) 4. Segunda order mesma live — regra única por order |
| **Resultado esperado** | +2 uma vez por order_id; reconcile não re-aplica; total tickets correcto |
| **Componentes afectados** | raffle post-checkout hook, settle edge |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | order pago + raffle |
| **Como validar na BD** | bonus audit per order unique |
| **Como validar na UI** | Contador estável pós-reconcile |
| **Risco de regressão** | Médio — overlap A209/A211 |
| **Dependências** | A211; A209; A206 |

---

## A277 — Bot stress N viewers entries + leaderboard

| Campo | Valor |
|-------|-------|
| **ID** | A277 |
| **Nome** | 20+ bots join/share — leaderboard estável |
| **Pré-condições** | Live test; rifa activa; bot simulator |
| **Passos detalhados** | 1. `fleaber_bot_simulator` N viewers join 2. Alguns share claim 3. Abrir leaderboard seller+buyer 4. Performance 60s |
| **Resultado esperado** | Sem crash; top 5 correcto; ops bar contador ≈ BD; latência aceitável |
| **Componentes afectados** | bot simulator, raffle RPCs, leaderboard widget |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | staging live; N bot JWTs |
| **Como validar na BD** | count entries = N |
| **Como validar na UI** | Leaderboard render <3s |
| **Risco de regressão** | Médio — escala |
| **Dependências** | A255; A256; H08 |

---

## A278 — Top público OFF oculta leaderboard buyer

| Campo | Valor |
|-------|-------|
| **ID** | A278 |
| **Nome** | `show_public_leaderboard=false` esconde ranking |
| **Pré-condições** | Rifa criada com toggle OFF (A121) |
| **Passos detalhados** | 1. Seller cria rifa OFF 2. Bot seed entries 3. Buyer abre painel — sem lista top 4. Toggle ON — lista aparece |
| **Resultado esperado** | OFF: buyer não vê top 5; ON: A255 visível; seller ops mantém contagem |
| **Componentes afectados** | `createRaffle(showPublicLeaderboard)`, buyer card |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot + Maestro |
| **Dados necessários** | raffle toggle variants |
| **Como validar na BD** | flag boolean |
| **Como validar na UI** | Leaderboard hidden/shown |
| **Risco de regressão** | Baixo |
| **Dependências** | A121; A255 |

---

## A279 — H04 end-to-end suite (manifest)

| Campo | Valor |
|-------|-------|
| **ID** | A279 |
| **Nome** | Suite H04 completa: bot seed → Maestro → verify BD |
| **Pré-condições** | Runner manifest H04; device + staging |
| **Passos detalhados** | 1. Bot join+follow seed 2. Maestro A271 3. Integration verify entries 4. `state.json` pass |
| **Resultado esperado** | Cadeia H04 verde; `.maestro/.env` válido; entries buyer ≥1; sem cleanup kill live (H07) |
| **Componentes afectados** | runner manifest, bot simulator, Maestro flows, `test/regression/state.json` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Híbrido Bot+Maestro+Integration |
| **Dados necessários** | full H04 env |
| **Como validar na BD** | entries + follow flags |
| **Como validar na UI** | Maestro + manual spot check |
| **Risco de regressão** | Alto — gate release rifa social |
| **Dependências** | A250; A251; A271; A272; H04; H07 |

---

## Apêndice A — Resumo A231–A279

| Bloco | IDs | Foco |
|-------|-----|------|
| Pós-live KPI | A231–A232 | Sessões `/operacoesLive`, timeline order |
| Refunds/disputas | A233–A237 | Reembolso, disputa buyer/seller/admin |
| Wallet/notificações | A238–A240 | Saque, push, comissão multi-order bag |
| Gorjetas P15 | A241–A242 | KPI in-stream vs pós-live |
| Stale/manual #8 | A243–A249 | Detect, reconcile, export, filtros, idempotência |
| Rifa social core | A250–A256 | H04 join, follow, share, referral, leaderboards |
| Rifa integridade | A257–A266 | FIFO, deep link, draw, audit, push, chat |
| Rifa VOD | A267–A270 | Replay guards, dedupe stress |
| Maestro/automação | A271–A279 | Smoke flows, prize edit, cancel, idempotência +2, stress, H04 suite |

**Total fichas:** 49 (A231–A279).

### Temas transversais

| Tema | Fichas principais |
|------|-------------------|
| Stale reconcile manual #8 | A243–A249, A088 |
| Gorjeta ≠ vendas (P15) | A241–A242, A115–A116, A224 |
| Disputa pós-live | A235–A237, A221 |
| Rifa VOD vs live | A267–A269, A295, A310 |
| H04 bot+Maestro | A250, A271, A279 |
| Checkout + rifa +2 | A276, A211 |

---

## Apêndice B — P0 desta faixa (10)

| ID | Nome curto |
|----|------------|
| A232 | Timeline reserva_pendente→pago |
| A240 | Comissão multi-order bag |
| A243 | Stale detect alertas |
| A244 | Reconcile stale detalhe sessão |
| A248 | Manual #8 playbook |
| A249 | Idempotência double-reconcile |
| A250 | H04 participar rifa |
| A268 | Join bloqueado em VOD |
| A271 | Maestro buyer rifa+bag |
| A279 | H04 suite end-to-end |

---

## Apêndice C — Top 10 a automatizar primeiro

| # | ID | Porquê | Tipo |
|---|-----|--------|------|
| 1 | A249 | Idempotência stale — evita double money | Integration |
| 2 | A244 | Reconcile pós-live — manual #8 extend | Integration |
| 3 | A240 | Comissão bag multi-order — dinheiro | Integration |
| 4 | A276 | +2 rifa idempotente — overlap reconcile | Integration |
| 5 | A260 | Share dedupe — anti-farming | Integration |
| 6 | A250 | H04 join — base rifa social | Bot+Maestro |
| 7 | A271 | Maestro smoke CI | Maestro |
| 8 | A268 | VOD join guard — regressão crítica | Integration |
| 9 | A243 | Stale visibility — ops alert | Integration |
| 10 | A277 | Stress N bots — escala leaderboard | Bot |

---

## Apêndice D — Classificação por tipo (faixa completa)

| Tipo | IDs |
|------|-----|
| **Unit** | — |
| **Integration** | A232, A240, A243, A244, A248, A249, A253, A254, A260, A263, A268, A276 |
| **Bot** | A251, A252, A255, A257, A261, A264, A270, A275, A277 |
| **Maestro** | A246, A256, A258, A267, A269, A271, A272, A274 |
| **Manual** | A233, A234, A235, A236, A237, A238, A239, A241, A245, A259, A265, A266, A273 |
| **Híbrido Bot+Maestro** | A250, A279 |
| **Híbrido Integration+Manual** | A231, A242, A248, A262 |
| **Híbrido Bot+Maestro+Integration** | A279 |

---

## Apêndice E — Riscos críticos (levantamento)

1. **Stale reconcile (A243–A249 + A088):** order `pago` sem `converted` — dinheiro sem KPI/stock; double-reconcile credita 2× wallet.
2. **Comissão multi-order bag (A240):** settle único Stripe com fee errada por linha — seller líquido errado (extend A220/A208).
3. **Timeline order (A232):** `reserva_pendente` preso após Stripe success — buyer vê pendente com dinheiro capturado.
4. **Gorjeta vs vendas (A241–A242):** tip misturado em `revenueEur` sessão — KPI R5/P15 regressão.
5. **Disputa + wallet (A235–A238):** saldo retido admin desalinhado com order live `live_id`.
6. **Rifa VOD join (A267–A268):** participar em gravado cria entries inválidas — fairness e suporte.
7. **Draw integrity (A261–A263):** sorteio duplicado ou audit trail ausente — confiança campanha (extend A119).
8. **Share/referral farming (A260, A269):** dedupe falha — entradas inflacionadas.
9. **Checkout +2 idempotência (A276):** reconcile re-aplica bónus A211 — tickets inflacionados.
10. **H04 Maestro flake (A250, A271, A279):** live morre no cleanup (A063) — smoke rifa vermelho em CI.

---

*Fim A231–A279. Continua A350–A369 (marketplace/cross-pool bridge) em ficheiro separado.*
