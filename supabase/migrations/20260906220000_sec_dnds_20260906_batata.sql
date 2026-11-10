-- POS_DHDM DN–DS fecho 2026-09-06 (mínimo BATATA)
-- CONTAGEM: P0:0 P1:1 P2:2 TOTAL:3
-- DS P2 rifa seal · hold raffle winners · DQ revoke registry
-- production_touched:false · fase4:false

-- ===========================================================================
-- DS P2-1 — selar stock do prémio quando rifa passa a drawn
-- ===========================================================================
create or replace function public.batata_raffle_seal_prize_stock(p_raffle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_raffle public.live_raffles%rowtype;
  v_li public.live_items%rowtype;
  v_product_id uuid;
  v_winners int := 0;
  v_stock int;
begin
  if p_raffle_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_raffle');
  end if;

  select * into v_raffle from public.live_raffles where id = p_raffle_id;
  if v_raffle.id is null then
    return jsonb_build_object('ok', false, 'error', 'raffle_not_found');
  end if;
  if v_raffle.live_item_id is null then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'manual_prize');
  end if;

  select count(*)::int into v_winners
  from public.live_raffle_winners w
  where w.raffle_id = p_raffle_id;
  if v_winners < 1 then
    return jsonb_build_object('ok', false, 'error', 'no_winners');
  end if;

  select * into v_li from public.live_items where id = v_raffle.live_item_id;
  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  v_product_id := coalesce(v_li.product_id, v_li.checkout_product_id);

  begin
    perform public.batata_mark_live_item_sold(v_li.id);
  exception when others then
    update public.live_items
       set status = 'sold',
           is_active = false,
           updated_at = now()
     where id = v_li.id
       and lower(trim(coalesce(status, ''))) is distinct from 'sold';
  end;

  if v_product_id is not null then
    select coalesce(quantity, 0) into v_stock
    from public.products where id = v_product_id for update;

    update public.products
       set quantity = greatest(coalesce(v_stock, 0) - v_winners, 0),
           is_sold = (greatest(coalesce(v_stock, 0) - v_winners, 0) < 1),
           list_on_marketplace = case
             when greatest(coalesce(v_stock, 0) - v_winners, 0) < 1 then false
             else list_on_marketplace
           end
     where id = v_product_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'product_id', v_product_id,
    'winners', v_winners,
    'live_item_id', v_li.id
  );
end;
$$;

revoke all on function public.batata_raffle_seal_prize_stock(uuid) from public, anon;
grant execute on function public.batata_raffle_seal_prize_stock(uuid)
  to authenticated, service_role;

create or replace function public.batata_live_raffles_after_drawn_seal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if lower(trim(coalesce(NEW.status, ''))) = 'drawn'
     and lower(trim(coalesce(OLD.status, ''))) is distinct from 'drawn' then
    perform public.batata_raffle_seal_prize_stock(NEW.id);
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_batata_raffle_drawn_seal on public.live_raffles;
create trigger trg_batata_raffle_drawn_seal
  after update of status on public.live_raffles
  for each row
  execute function public.batata_live_raffles_after_drawn_seal();

-- Hold: vencedores drawn sem encomenda activa
create or replace function public.batata_product_held_qty(
  p_product_id uuid,
  p_exclude_order_id uuid default null,
  p_exclude_order_ids uuid[] default null
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_held int := 0;
  v_live int := 0;
  v_raffle int := 0;
  v_pending_ttl interval := interval '90 minutes';
begin
  if p_product_id is null then
    return 0;
  end if;
  select coalesce(sum(greatest(coalesce(o.quantity, 1), 1)), 0)::int
    into v_held
  from public.orders o
  where o.product_id = p_product_id
    and (p_exclude_order_id is null or o.id is distinct from p_exclude_order_id)
    and (
      p_exclude_order_ids is null
      or cardinality(p_exclude_order_ids) = 0
      or not (o.id = any (p_exclude_order_ids))
    )
    and coalesce(o.status, '') not in (
      'cancelado', 'cancelled', 'rejected', 'expired'
    )
    and (
      public.batata_order_status_holds_product_qty(o.status)
      or lower(trim(coalesce(o.status, ''))) = 'premio_rifa'
    )
    and (
      lower(trim(coalesce(o.status, ''))) in (
        'reservado', 'aguarda_confirmacao', 'aguarda_pagamento', 'premio_rifa'
      )
      or (
        lower(trim(coalesce(o.status, ''))) in ('reserva_pendente', 'pendente')
        and o.created_at > (timezone('utc', now()) - v_pending_ttl)
      )
    );

  select coalesce(sum(greatest(coalesce(r.requested_qty, 1), 1)), 0)::int
    into v_live
  from public.live_reservation_requests r
  join public.live_items li on li.id = r.live_item_id
  where r.status = 'accepted'
    and coalesce(li.product_id, li.checkout_product_id) = p_product_id;

  select coalesce(count(*)::int, 0)
    into v_raffle
  from public.live_raffle_winners w
  join public.live_raffles rf on rf.id = w.raffle_id
  join public.live_items li on li.id = rf.live_item_id
  where coalesce(li.product_id, li.checkout_product_id) = p_product_id
    and lower(trim(coalesce(rf.status, ''))) = 'drawn'
    and not exists (
      select 1 from public.orders o
      where o.live_raffle_id = rf.id
        and o.buyer_id = w.user_id
        and lower(trim(coalesce(o.status, ''))) in (
          'premio_rifa', 'pago', 'enviado', 'entregue', 'concluido',
          'aguarda_pagamento', 'aguarda_confirmacao', 'reservado'
        )
    );

  return v_held + v_live + v_raffle;
end;
$$;

-- ===========================================================================
-- DQ P2 — revoke registry + TTL curto na app (CDN signed até exp = residual)
-- ===========================================================================
create table if not exists public.batata_private_object_revoked (
  object_path text primary key,
  revoked_at timestamptz not null default now(),
  revoked_by uuid null
);

revoke all on table public.batata_private_object_revoked from public, anon, authenticated;
grant select, insert on table public.batata_private_object_revoked to authenticated;
grant all on table public.batata_private_object_revoked to service_role;

create or replace function public.batata_revoke_private_object(p_path text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_path text := trim(coalesce(p_path, ''));
  v_role text := coalesce(auth.role(), '');
begin
  if v_path = '' then
    return false;
  end if;
  v_path := regexp_replace(v_path, '^/+', '');
  v_path := regexp_replace(v_path, '^fleaber_private/', '');
  if v_role is distinct from 'service_role'
     and v_uid is not null
     and v_path not like ('order_disputes/' || v_uid::text || '/%')
     and v_path not like ('order_proofs/' || v_uid::text || '/%') then
    raise exception 'revoke_forbidden' using errcode = '42501';
  end if;
  insert into public.batata_private_object_revoked (object_path, revoked_by)
  values (v_path, v_uid)
  on conflict (object_path) do update set revoked_at = now();
  return true;
end;
$$;

revoke all on function public.batata_revoke_private_object(text) from public, anon;
grant execute on function public.batata_revoke_private_object(text)
  to authenticated, service_role;

notify pgrst, 'reload schema';
