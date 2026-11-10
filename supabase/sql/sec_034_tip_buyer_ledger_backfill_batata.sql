-- Backfill: movimentos gorjeta Stripe no histórico do comprador (sem mexer saldo).
insert into public.wallet_transactions (wallet_id, amount, type, description, tip_id)
select
  lt.buyer_id,
  -round(lt.amount, 2),
  'gorjeta_enviada',
  coalesce(nullif(trim(lt.message), ''), 'Gorjeta paga com cartão'),
  lt.id
from public.live_tips lt
where lt.status = 'completed'
  and lt.payment_source = 'stripe'
  and lt.buyer_id is not null
  and not exists (
    select 1 from public.wallet_transactions wt
    where wt.tip_id = lt.id and wt.type = 'gorjeta_enviada'
  );
