-- RTBB-B-2012 P1s (staging BATATA)
-- B-STOCK-UNPAID-HOLD: reserva_pendente contava como hold sem TTL → DoS catálogo.
--   Intenção B-01 era hold em reservado/aguarda_*; pending = lista de espera.
-- B-COMPOSE: Edge+settle — ver create-payment-intent (off-platform sem Session).
-- production_touched: false · fase4: false

create or replace function public.batata_order_status_holds_product_qty(p_status text)
returns boolean
language sql
immutable
as $$
  -- Hold económico: seller já aceitou / pagamento plataforma em curso.
  -- NÃO inclui reserva_pendente / pendente (lista de espera; sem TTL → DoS).
  select lower(trim(coalesce(p_status, ''))) in (
    'reservado',
    'aguarda_confirmacao',
    'aguarda_pagamento'
  );
$$;

comment on function public.batata_order_status_holds_product_qty(text) is
  'RTBB-B-2012: hold só após accept (reservado/aguarda_*). Pending não trava stock.';

notify pgrst, 'reload schema';
