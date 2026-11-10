-- BATATA: histórico comprador — reembolso/cancelamento no ledger (sem mexer saldo
-- quando o dinheiro voltou pelo Stripe/fora da carteira). Corrige is_sold vs qty.

create or replace function public.batata_record_buyer_refund_ledger(
  p_order_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_amount numeric;
  v_title text;
  v_row_count integer := 0;
begin
  if p_order_id is null then
    return false;
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id;

  if not found or v_order.buyer_id is null then
    return false;
  end if;

  if lower(coalesce(v_order.status, '')) not in (
    'cancelado', 'devolvida', 'reembolsado'
  ) then
    return false;
  end if;

  -- Só se já houver «compra» no histórico (pagamento confirmado antes).
  if not exists (
    select 1
    from public.wallet_transactions wt
    where wt.wallet_id = v_order.buyer_id
      and wt.order_id = v_order.id
      and wt.type = 'compra'
  ) then
    return false;
  end if;

  if exists (
    select 1
    from public.wallet_transactions wt
    where wt.wallet_id = v_order.buyer_id
      and wt.order_id = v_order.id
      and wt.type = 'reembolso'
  ) then
    return true;
  end if;

  v_amount := public.batata_order_amount(v_order);
  if coalesce(v_amount, 0) <= 0 then
    return false;
  end if;

  select nullif(trim(title), '') into v_title
  from public.products
  where id = v_order.product_id;

  perform public.batata_ensure_wallet(v_order.buyer_id);

  insert into public.wallet_transactions (
    wallet_id,
    amount,
    type,
    description,
    order_id
  ) values (
    v_order.buyer_id,
    round(v_amount, 2),
    'reembolso',
    'Reembolso · ' || coalesce(v_title, 'compra'),
    v_order.id
  )
  on conflict (wallet_id, order_id, type) where order_id is not null do nothing;

  get diagnostics v_row_count = row_count;
  -- Sem alterar balance — espelho do ledger «compra» (pagamento fora da carteira).
  return v_row_count > 0;
end;
$$;

revoke all on function public.batata_record_buyer_refund_ledger(uuid)
  from public, anon;
grant execute on function public.batata_record_buyer_refund_ledger(uuid)
  to authenticated, service_role;

create or replace function public.batata_wallet_order_status_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if lower(coalesce(new.status, '')) = 'devolvida' then
    perform public.batata_refund_buyer_wallet_for_order(new.id);
  end if;

  if lower(coalesce(new.status, '')) in ('pago', 'enviado', 'concluido')
     and (
       tg_op = 'INSERT'
       or lower(coalesce(old.status, ''))
            is distinct from lower(coalesce(new.status, ''))
     ) then
    perform public.batata_record_buyer_purchase_ledger(new.id);
  end if;

  if lower(coalesce(new.status, '')) in ('cancelado', 'devolvida', 'reembolsado')
     and (
       tg_op = 'INSERT'
       or lower(coalesce(old.status, ''))
            is distinct from lower(coalesce(new.status, ''))
     ) then
    perform public.batata_record_buyer_refund_ledger(new.id);
  end if;

  return new;
end;
$$;

-- Backfill reembolsos em cancelados/devolvidos com «compra» sem «reembolso».
insert into public.wallet_transactions (
  wallet_id,
  amount,
  type,
  description,
  order_id
)
select
  o.buyer_id,
  round(public.batata_order_amount(o), 2),
  'reembolso',
  'Reembolso · ' || coalesce(nullif(trim(p.title), ''), 'compra'),
  o.id
from public.orders o
left join public.products p on p.id = o.product_id
where o.buyer_id is not null
  and lower(coalesce(o.status, '')) in ('cancelado', 'devolvida', 'reembolsado')
  and public.batata_order_amount(o) > 0
  and exists (
    select 1 from public.wallet_transactions c
    where c.order_id = o.id and c.type = 'compra' and c.wallet_id = o.buyer_id
  )
  and not exists (
    select 1 from public.wallet_transactions r
    where r.order_id = o.id and r.type = 'reembolso' and r.wallet_id = o.buyer_id
  );

-- Corrigir is_sold inconsistente com stock > 0.
update public.products
set is_sold = false,
    list_on_marketplace = coalesce(list_on_marketplace, true)
where coalesce(quantity, 0) > 0
  and is_sold = true;
