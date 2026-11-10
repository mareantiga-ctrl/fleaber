-- Block B1: align orders_status_batata_check with SQL FSM/hold predicates.
-- Product UI uses aguarda_confirmacao for "prova enviada / seller confirma".
-- aguarda_pagamento is a prepay synonym already referenced by:
--   batata_order_status_is_prepay, holds, create-payment-intent allowlists.
-- Staging/prod CHECK historically omitted it → writes would fail (22P02/check).
-- Safe: additive only; no data rewrite.

alter table public.orders drop constraint if exists orders_status_batata_check;

alter table public.orders
  add constraint orders_status_batata_check
  check (
    status is null
    or status in (
      'reserva_pendente',
      'reservado',
      'pendente',
      'aguarda_confirmacao',
      'aguarda_pagamento',
      'pago',
      'premio_rifa',
      'enviado',
      'entregue',
      'concluido',
      'cancelado',
      'pedido_devolucao',
      'em_devolucao',
      'devolucao_entregue',
      'disputa_devolucao_vendedor',
      'devolvida'
    )
  );

comment on constraint orders_status_batata_check on public.orders is
  'Block B1: inclui aguarda_pagamento (sinónimo pré-pago SQL). UI canónica MB WAY = aguarda_confirmacao.';
