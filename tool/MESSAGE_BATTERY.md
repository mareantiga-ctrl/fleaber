# Message Battery (M##)

Bateria dedicada a **todas as mensagens** da Fleaber: chat público de live, DMs
comprador↔vendedor, mensagens geradas por reservas/compras e o varrimento de
**todos os estados de encomenda e de reserva**. Segue o mesmo modelo da matriz
A### (semear staging → recolher evidência BD → auditoria humana/agente).

## Camadas

| Camada | Ferramenta | Device? | Stripe |
|--------|-----------|---------|--------|
| Copy (texto humanizado) | `test/message_battery_humanizer_test.dart` (`flutter test`) | não | n/a |
| Evidência BD (linhas reais) | `tool/message_battery.dart` (staging) | não | **bypass** |

A copy é a garantia de regressão automática; a evidência BD é o que o
agente audita à procura de inconformidades (números, estados, texto cru).

## Como correr

```bash
# 1) Copy (rápido, sem device)
flutter test test/message_battery_humanizer_test.dart

# 2) Evidência BD contra staging (Stripe em bypass)
dart run tool/message_battery.dart            # corre tudo + limpa fixtures
dart run tool/message_battery.dart --keep     # mantém fixtures p/ inspeção
dart run tool/message_battery.dart --area dm  # só um grupo
```

Saídas:
- `tool/reports/message_battery_<stamp>/evidence.json` — linhas BD por caso
- `tool/reports/message_battery_<stamp>/report.md` — tabela auditável
- `tool/message_battery_registry.json` — último estado por caso

Estados: **pass** (esperado = BD) · **warn** (BD diverge / trigger não
observável em staging — auditar) · **fail** (erro a executar).

## Stripe — política de bypass

Não há checkout Stripe real nos testes. A compra é simulada como em produção
pós-pagamento: `orders.status = 'pago'` por patch BD + RPC
`batata_live_reconcile_stripe_order` → reserva `converted` + broadcast de compra
(`✅ … comprou …`). Mesmo padrão do cenário `reconcile` da matriz A###.

## Matriz

### Grupo 1 — Chat público (linhas de sistema do humanizer)

| ID | Evento | Corpo cru | Linha pública | Visível |
|----|--------|-----------|---------------|---------|
| M01 | reserva c/ artigo | `🛍️ Marina reservou Puzzle` | Marina reservou Puzzle | sim |
| M02 | reserva → fila | `🛍️ Marina reservou para o saco da live` | Marina entrou na fila deste artigo | sim |
| M03 | adicionou ao saco | `🛍️ Marina adicionou Puzzle ao saco` | Marina adicionou Puzzle ao carrinho | sim |
| M04 | compra | `✅ Marina comprou Puzzle` | Marina comprou Puzzle | sim |
| M05 | compra c/ preço | `💳 Marina comprou Puzzle (10€)` | Marina comprou Puzzle | sim |
| M06 | reserva aceite | `🔒 Reserva aceite — Puzzle · Marina tem 5 dias para pagar` | Marina ficou com Puzzle | sim |
| M07 | aceite c/ qty | `🔒 Reserva aceite — 2 un. · Puzzle · …` | Marina ficou com Puzzle | sim |
| M08 | aceite painel | `🔒 Marina — reserva aceite · Puzzle · Prazo: 4d` | Marina ficou com Puzzle | sim |
| M09 | preço definido | `💶 Preço definido · Puzzle · 12,00 €` | Puzzle — 12,00 € | sim |
| M10 | última unidade | `🔥 Ultima unidade — Puzzle` | Última unidade de Puzzle | sim |
| M11 | esgotado | `🔴 Puzzle esgotado` | Puzzle esgotou | sim |
| M12 | rifa | `🎟️ Rifa: Ana ganhou +2 rifas` | Ana ganhou +2 rifas | sim |
| M13 | cancelou (comprador) | `↩ Reserva cancelada pelo comprador` | Reserva cancelada | sim |
| M14 | cancelou (nome) | `↩ Marina cancelou a reserva · Puzzle` | Marina cancelou a reserva de Puzzle | sim |
| M15 | pedido > stock | `📋 Pedido de 3 un. · Puzzle — só 1 disponível…` | — (snackbar) | **não** |
| M16 | recusa over-stock | `❌ Recusaste o pedido de 2 un. · Puzzle …` | — (snackbar) | **não** |
| M17 | aceite over-stock | `✅ Aceitaste vender 2 un. · Puzzle — …` | — | **não** |
| M18 | rejeição vendedora | `❌ Vendedora rejeitou reserva · Ref A12` | — | **não** |
| M19 | gorjeta (`kind=tip`) | — | Marina apoiou a live com 5,00 € | sim |

### Grupo 2 — Emissores reais (RPC end-to-end)

| ID | RPC | Linha esperada |
|----|-----|----------------|
| M20 | `batata_process_live_reservation_request` (accept) | `🔒 Reserva aceite …` |
| M21 | `batata_live_bag_remove_request` | `↩ Reserva cancelada …` |

### Grupo 3 — Sweep estados de encomenda (`orders.status`)

M30–M43: `reserva_pendente, reservado, pendente, aguarda_confirmacao, pago,
enviado, entregue, concluido, cancelado, pedido_devolucao, em_devolucao,
devolucao_entregue, disputa_devolucao_vendedor, devolvida`.

### Grupo 4 — Sweep estados de reserva (`live_reservation_requests.status`)

M50–M54: `pending, accepted, rejected, expired, converted`.

### Grupo 5 — DM de sistema (`FLEABER_JSON_V1:` ciclo de vida)

M60+: `reservation_request`, `reservation_request_outcome` (accepted/declined),
`reservation_accepted`, `reservation_payment_submitted`, `reservation_reminder`,
`reservation_payment_check_reminder`, `reservation_shipping_reminder`,
`reservation_seller_confirmed_receipt`, `reservation_order_shipped`,
`reservation_order_completed`, `reservation_cancelled_by_seller`,
`cancel_request`, `cancel_request_outcome`, `order_dispute_opened`,
`price_offer`, `price_offer_outcome`, `bundle_proposal`, `chat_image`,
+ DM texto «comprador cancelou pedido».

> Round-trip BD apenas (armazenamento + JSON válido + `kind`). O **render dos
> cards** é app-side — validar por widget/Maestro num passo com device.

### Grupo 6 — Chat humano

M80: comprador↔vendedor (texto livre) + `chats.last_message` actualizado.

### Grupo 7 — Stripe bypass

M90: order→`pago` (patch) + reconcile RPC → reserva `converted` + broadcast compra.

## Achados de auditoria

### ⚠️ M20 — aceitar reserva não emite a linha social na live (staging)

`batata_process_live_reservation_request(p_action='accept')` devolve `ok:true`,
muda a reserva para `accepted` e o item para `reserved_partial`, **mas não insere
qualquer mensagem de sistema** na live. Consequência: a linha pública
«X ficou com Y / Reserva aceite» e o overlay privado do comprador
(«Ficaste com Y — 5 dias para pagar») **não aparecem** ao aceitar.

Evidência de que é o *emissor dentro da RPC* que falha (e não a função de
broadcast nem o humanizer):
- **M22** chama `batata_live_reservation_accept_broadcast(...)` directamente na
  mesma live → emite `🔒 Reserva aceite …` ✅
- **M21** (cancelar) e **M23** (compra) emitem normalmente ✅
- O repo tem a chamada em `supabase/sql/live_ops_hotfix_batata.sql:485`, logo a
  versão **deployed em staging está dessincronizada** (não corre o broadcast).

A app nunca chama `accept_broadcast` à parte (grep), por isso a linha social do
accept depende 100% desta RPC. **Não corrigido aqui** (regra BATATA — alteração
de função/SQL precisa de autorização). Acção sugerida: redeploy do hotfix
`batata_process_live_reservation_request` em staging e re-correr M20.

### Compra via reconcile não faz broadcast (esperado)

`batata_live_reconcile_stripe_order` converte a reserva (`converted`) mas **não**
emite a linha de compra — esta é emitida pela edge `create-payment-intent` e por
`live_reservation_queue_service.dart`. Não é bug; M23 cobre o emissor real.

## Cobertura conhecida / limites

- Render de cards de DM e overlays do player: **app-side** (precisa device).
- RLS por utilizador não é exercida (semente via service role).
- Triggers de broadcast podem estar desligados em staging → caso fica **warn**
  (não é falha de copy; o humanizer é validado à parte no flutter test).
