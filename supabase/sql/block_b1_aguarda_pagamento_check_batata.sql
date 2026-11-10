-- Mirror of migration 20260927190000 (SQL Editor / batata apply).
-- Block B1: orders_status_batata_check inclui aguarda_pagamento.

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
