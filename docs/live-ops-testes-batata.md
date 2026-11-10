# Testes Live — o que fazer agora

## Bateria L1–L18 (V1.5 linhagem) — ✅ FECHADA (Jun 2026)

| Fonte | Resultado |
| ----- | --------- |
| `dart run tool/live_logical_item_id_check.dart` | **12 PASS · 0 FAIL · 6 SKIP** |
| SKIP confirmados manualmente | L7, L8, L9, L12, L14, L15 |
| Automático | L1–L6, L10, L11, L13, L16–L18 |

Detalhe por teste: `docs/deploy-checklist-v1.5-price-pending.md` (secção «Estado da bateria L»).

**Seguinte:** bateria **P1–P15** (preço pendente) — mesmo checklist, Parte C.

---

## Antes de testar (P)

1. SQL Editor → `supabase/sql/live_ops_hotfix_batata.sql` (já aplicado para L).
2. Edge **A3:** `npx supabase functions deploy create-payment-intent`.
3. Rebuild **vendedora + comprador** (fix preço fresco no saco — A1/P5).

---

## Sessão `86fdbe82-…` (2026-06-04, após patch qty/R1/R32)

| # | Resultado | Notas |
|---|-----------|-------|
| R1 | **FAIL** | Card verde não apareceu após aceite |
| R5 | **OK** | |
| R6 / R6.1 | **FAIL** | Pedido mostrava 1 em vez de 2–3; saco/checkout 1 após aceite over-stock |
| R20 | Parcial | Checkout OK; faltavam **fotos** nas linhas |
| R32 | **FAIL** | Catálogo/carrossel Qtd 8; editor/comprador 10 |

**Patch v2 (SQL + app):** Card urgente **só** após **Pagar** no saco (qty total > disponível); aceite SQL soma reservas irmãs no `requested_qty`; card verde **acima** do chat com foto; fotos no checkout (`LiveBagCheckoutSheet` + `LiveInStreamCheckout`).

## Sessão `5e2d06d3-…` (2026-06-04, patch v3)

| # | Resultado | Notas |
|---|-----------|-------|
| R6 | **FAIL** | Banner «aceite» com pedidos ainda `pending`; card verde ao 2.º pedido |
| R6.1 | **OK** | |
| R1 | **OK** | |
| R20 | **FAIL** | Checkout com portes não abre |

**Patch v3:** Banner saco só `status=accepted`; 2.ª reserva incrementa qty (não duplica linha); gate R6 só soma **pending**; checkout abre com aceites (gate não bloqueia); card verde só em transição `accepted` (não a cada alteração do saco); logs `reservation.create` / `reservation.status` / `checkout.pay_qty_gate` em `live_vendor_studio_logs`.

## Sessão `75945a1a-…` (2026-06-05, patch v3 em produção)

| # | Resultado | Notas |
|---|-----------|-------|
| R6 | **OK** | |
| R20 | **OK** | **Não mexer mais no checkout** |
| A1 | **FAIL** | Botão **Pagar** sumiu dos cards do saco |
| A2 | **FAIL** | Vários artigos: só 1.ª posição; após aceite sumiram chips de fila/espera |
| R1 | **FAIL** | Card verde só no saco, não no player |

**Patch v4 (só app, sem SQL):** **Pagar** volta com `buyerCanPayBagReservation` (pendente + aceite); banner aceite mantém-se só em `accepted`; posições no saco com ordem global (#1, #2, #3) + label **Espera #N** quando sem stock; card verde no player via stream do saco + `_loadLiveBagCount` (sem reabrir em cada +1 pendente).

## Sessão `a345cd98-…` / `ec67f0d3-…` (2026-06-05, patch v4 em produção)

| # | Resultado | Notas |
|---|-----------|-------|
| A1 | **OK** | |
| A2 | **FAIL** | Posições no saco ainda incompletas |
| R1 | **OK** | |
| A3 | **FAIL** | Catálogo mostra **total**; barra de fundo **disponível** — p.ex. puxadores Total 13 / Disp 1 após −27; puzzle 20 vs 19 (1 bloqueada noutro directo) |

**Patch v5 (só app):** Catálogo vendedora mostra **Total · Disp** quando diferem; sync `live_items.quantity` após stock adjust; saco mantém chip de posição em «aguarda confirmação»; waitlist usa posição global do saco; logs `stock.add`/`stock.remove` com `available_qty` + `blocked_qty`.

## Sessão `0adb5c84-…` / `5f413f23-…` (2026-06-05, patch v5)

| # | Resultado | Notas |
|---|-----------|-------|
| A2 | **FAIL** | Só #1 amarelo; +/- qty não cria posições; verde/âmbar errado |
| A3 | **FAIL** | Puzzle catálogo 2 / fundo 1; puxadores catálogo 13 / disp 1; gravados não alinhados |

**Patch v6 (app):** Ranking **por unidade** (qty=3 → #1 #2 #3); verde se unidade ≤ stock bruto do artigo (sem descontar o próprio pending); catálogo lidera com **Disp** = barra de fundo; **Reservas** inclui `blocked_qty` (noutros directos no mesmo produto).

---

## Sessão anterior (live `c2c555c1-…`, 2026-06-04)

| # | Resultado | Notas |
|---|-----------|-------|
| R1 | **FAIL** | Card aceite ~30s–1min tarde; **dois** UIs (overlay + dialog) |
| R5 | **FAIL** | KPI/carteira ~10 € (só artigo); logs `paid_value_eur` 14,83 OK |
| R6 | **FAIL** | Card urgente: 0 na live, pedido 1 (comprador pediu 2) |
| R20 / Checkout | **FAIL** | Sem UI saco (checkboxes, escolher linhas) |
| R30 / Stock pós-aceite | **OK** | |
| R31 / Pay qty over-stock | **FAIL** | Checkout mostrava 1 un. |
| P14.3 | **OK** | |
| P12 | OK (sessão anterior) | |

**Patch aplicado após esta sessão** (rebuild obrigatório):

- **R1:** Removido dialog; só card verde **por cima do input** (`bottom: chatPanelBottom + 10`); aceite imediato via realtime `accepted` (sem esperar scan do saco).
- **R5:** KPI «valor vendido» usa total comprador (artigo + portes + proteção) nas convertidas; métricas de pagamentos refrescam **antes** de atualizar totais.
- **R6:** Card urgente: **Na live / Livres / Pedido total** + reservas para este/outro cliente.
- **R20 / R31:** **Pagar** no player e no saco abre `LiveBagCheckoutSheet` (checkboxes, qty real `requested_qty`).

---

## Checklist — retestar só o que falhou

| # | Teste | Fazes | Confere |
|---|-------|-------|---------|
| **R1** | Card aceite no player | Aceitar reserva; comprador **na live** | **Um** card verde baixo (sem dialog); aparece em poucos segundos |
| **R5** | Portes na carteira | Pagar 1 artigo (transportadora) | KPI + painel pagamentos ≈ total pago (~14 € se artigo 10 € + portes) |
| **R6** | Card urgente qty | Reservar **2** com stock **1** → **Pagar** | **Na live: 1 · Livres: … · Pedido total: 2** + texto reservas se aplicável |
| **R20** | UI checkout artigo | **Pagar** (card aceite ou saco) | Sheet com **checkboxes**, linhas do artigo, portes, totais |
| **R31** | Pay qty over-stock | Aceitar pedido **2** com stock **1** → **Pagar** | Stepper / qty **2** no checkout |
| **R32** | Qtd pós-venda | Artigo vendido → menu +10 un. | Catálogo/carrossel **Qtd: 10** (não 8) |
| **R20 fotos** | Checkout | Pagar no saco | Linhas com **miniatura** do artigo |
| **Stock** | Após aceite | Aceitar reserva | Catálogo: vendidos sobe; qtd desce (regressão R30) |
| **P14.3** | Barra catálogo | 2× mesmo artigo → aceitar uma | Vendidos +1; reservas desce (regressão) |

---

## Checklist completo (regressão)

### Regressões saco + comprador

| # | Teste | Fazes | Confere |
|---|-------|-------|---------|
| **R1** | Card aceite no player | Ver tabela «retestar» acima | |
| **R2** | Banner no saco | Abrir saco após aceite | Banner + chip **Aceite · pronto a pagar** |
| **R3** | Botão Pagar | Saco pendente ou aceite | **Pagar** visível |
| **R4** | +/- quantidade | 2 reservas no mesmo artigo | Stepper; qty persiste ao reabrir |
| **R5** | Portes na carteira | Ver tabela «retestar» acima | |
| **R6** | Finalizar compra sem stock | Sacó multi → qty **>** stock → Pagar | Dialog comprador; card urgente vendedora; sem `Erro: …` |

### Checkout qty > stock

| # | Teste | Fazes | Confere |
|---|-------|-------|---------|
| **T1** | Só ao pagar | Qty **>** stock → Pagar / checkout | Card vermelho vendedora; sem Stripe |
| **T2** | Não ao reservar | Só **Reservar** | Sem card urgente |

### P11 — Pagar após aceite over-stock

| # | Teste | Fazes | Confere |
|---|-------|-------|---------|
| **P11** | Sem loop | T1 → **Aceita** → **Pagar** | Stripe; sem loop urgente |

### P12 — Notificações

| # | Teste | Fazes | Confere |
|---|-------|-------|---------|
| **P12a** | Recusa | T1 → **Recusa** | Chat + chip comprador |
| **P12b** | Aceite | T1 → **Aceita** | R1 + R2 |

### P14 — Catálogo vendedora

| # | Teste | Fazes | Confere |
|---|-------|-------|---------|
| **P14.1** | Vendidos | Pagar artigo | Contador vendidos |
| **P14.2** | Reservas | Pedido pendente | Contador reservas |
| **P14.3** | Barra catálogo | Ver tabela «retestar» | |

### P15 — Gorjetas

| # | Teste | Fazes | Confere |
|---|-------|-------|---------|
| **P15** | Tip | Enviar gorjeta na live | Aparece no painel |

---

## Logs úteis (`live_vendor_studio_logs`)

- `payments.refresh` → `paid_value_eur` deve bater certo com o que o comprador pagou.
- `reservation.accept` → `reserved_qty`, `item_qty`.
- `reservation.create` / `reservation.status` / `reservation.increment` / `checkout.pay_qty_gate` → diagnóstico R6/R20.
- `stock.add` / `stock.remove` → `from_qty`, `to_qty`, `available_qty`, `blocked_qty` (A3: total vs disponível).
- `reservation.load` com `error` → reportar stack (ex. null check).
