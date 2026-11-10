-- Histórico carteira comprador: «compra» quando encomenda fica paga
-- (sem alterar saldo — pagamento fora da carteira Fleaber).

create or replace function public.batata_record_buyer_purchase_ledger(
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
    'pago', 'enviado', 'concluido'
  ) then
    return false;
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
    -round(v_amount, 2),
    'compra',
    coalesce(v_title, 'Compra Fleaber'),
    v_order.id
  )
  on conflict (wallet_id, order_id, type) where order_id is not null do nothing;

  get diagnostics v_row_count = row_count;
  return v_row_count > 0;
end;
$$;

revoke all on function public.batata_record_buyer_purchase_ledger(uuid)
  from public, anon;
grant execute on function public.batata_record_buyer_purchase_ledger(uuid)
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

  return new;
end;
$$;

-- Garantir carteiras em falta antes do backfill.
insert into public.wallets (id, balance)
select distinct o.buyer_id, 0.00
from public.orders o
where o.buyer_id is not null
  and lower(coalesce(o.status, '')) in ('pago', 'enviado', 'concluido')
  and not exists (select 1 from public.wallets w where w.id = o.buyer_id)
on conflict (id) do nothing;

insert into public.wallet_transactions (
  wallet_id,
  amount,
  type,
  description,
  order_id
)
select
  o.buyer_id,
  -round(public.batata_order_amount(o), 2),
  'compra',
  coalesce(nullif(trim(p.title), ''), 'Compra Fleaber'),
  o.id
from public.orders o
left join public.products p on p.id = o.product_id
where o.buyer_id is not null
  and lower(coalesce(o.status, '')) in ('pago', 'enviado', 'concluido')
  and public.batata_order_amount(o) > 0
  and not exists (
    select 1
    from public.wallet_transactions wt
    where wt.order_id = o.id
      and wt.type = 'compra'
      and wt.wallet_id = o.buyer_id
  );
