-- Fleaber BATATA: fila operacional de reservas em direto (pré-encomenda).
-- Camada de orquestração antes da criação/continuação do fluxo de orders.

create table if not exists public.live_reservation_requests (
  id uuid primary key default extensions.gen_random_uuid(),
  live_id uuid not null references public.lives (id) on delete cascade,
  live_item_id uuid not null references public.live_items (id) on delete cascade,
  seller_id uuid not null references public.profiles (id) on delete cascade,
  buyer_id uuid references public.profiles (id) on delete set null,
  requested_qty int not null default 1 check (requested_qty > 0),
  queue_position int,
  source text not null default 'fleaber_live',
  status text not null default 'pending',
  notes text,
  processed_by_user_id uuid references public.profiles (id) on delete set null,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint live_reservation_requests_source_chk
    check (source in ('fleaber_live', 'facebook_manual', 'helper_manual')),
  constraint live_reservation_requests_status_chk
    check (status in ('pending', 'accepted', 'rejected', 'expired', 'converted'))
);

create index if not exists live_reservation_requests_live_item_created_idx
  on public.live_reservation_requests (live_id, live_item_id, created_at);

create index if not exists live_reservation_requests_seller_status_idx
  on public.live_reservation_requests (seller_id, status, created_at desc);

create index if not exists live_reservation_requests_buyer_idx
  on public.live_reservation_requests (buyer_id, created_at desc);

alter table public.live_reservation_requests enable row level security;

-- Modo de estado operacional por artigo live (não quebra uso atual).
alter table public.live_items
  add column if not exists status text not null default 'available';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'live_items_status_op_chk'
      and conrelid = 'public.live_items'::regclass
  ) then
    alter table public.live_items
      add constraint live_items_status_op_chk
      check (status in ('available', 'showing', 'reserved_partial', 'reserved_full', 'sold', 'paused'));
  end if;
end $$;

-- Atribui posição de fila por artigo/live mantendo lista de espera (mesmo sem stock).
create or replace function public.batata_live_reservation_assign_queue()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max int;
  v_item_status text;
begin
  select coalesce(li.status, '') into v_item_status
  from public.live_items li
  where li.id = new.live_item_id;

  if v_item_status = 'sold' then
    raise exception 'item_sold';
  end if;

  if new.queue_position is null then
    select coalesce(max(r.queue_position), 0)
    into v_max
    from public.live_reservation_requests r
    where r.live_id = new.live_id
      and r.live_item_id = new.live_item_id
      and r.status = 'pending'
      and r.source = 'fleaber_live';

    new.queue_position := v_max + 1;
  end if;

  if new.status = 'pending' and new.expires_at is null then
    new.expires_at := now() + interval '45 minutes';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists batata_live_reservation_assign_queue_tg
  on public.live_reservation_requests;
create trigger batata_live_reservation_assign_queue_tg
  before insert on public.live_reservation_requests
  for each row
  execute function public.batata_live_reservation_assign_queue();

create or replace function public.batata_live_reservation_touch()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists batata_live_reservation_touch_tg
  on public.live_reservation_requests;
create trigger batata_live_reservation_touch_tg
  before update on public.live_reservation_requests
  for each row
  execute function public.batata_live_reservation_touch();

-- Seller/Helper processa pedido e atualiza estado do item live por stock reservado.
create or replace function public.batata_process_live_reservation_request(
  p_request_id uuid,
  p_action text,
  p_processed_by uuid default auth.uid(),
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.live_reservation_requests%rowtype;
  v_item_qty int := 1;
  v_reserved_qty int := 0;
  v_next_status text;
begin
  select * into v_req
  from public.live_reservation_requests
  where id = p_request_id
  for update;

  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'request_not_found');
  end if;

  if p_action not in ('accept', 'reject', 'skip', 'expire', 'convert') then
    return jsonb_build_object('ok', false, 'error', 'invalid_action');
  end if;

  if not (
    auth.uid() = v_req.seller_id
    or public.batata_staff_has_permission(v_req.seller_id, 'can_manage_reservations')
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  update public.live_reservation_requests
  set
    status = case
      when p_action = 'accept' then 'accepted'
      when p_action = 'reject' then 'rejected'
      when p_action = 'skip' then 'rejected'
      when p_action = 'expire' then 'expired'
      else 'converted'
    end,
    notes = case
      when p_action = 'skip' then coalesce('skip:' || p_notes, 'skip')
      else coalesce(p_notes, notes)
    end,
    processed_by_user_id = coalesce(p_processed_by, auth.uid()),
    updated_at = now()
  where id = v_req.id;

  select coalesce(p.quantity, 1)::int
  into v_item_qty
  from public.products p
  where p.id = (
    select li.id from public.live_items li where li.id = v_req.live_item_id
  );

  select coalesce(sum(r.requested_qty), 0)::int
  into v_reserved_qty
  from public.live_reservation_requests r
  where r.live_item_id = v_req.live_item_id
    and r.status in ('accepted', 'converted');

  v_next_status := case
    when v_reserved_qty <= 0 then 'available'
    when v_reserved_qty < greatest(v_item_qty, 1) then 'reserved_partial'
    when v_reserved_qty >= greatest(v_item_qty, 1) then 'reserved_full'
    else 'available'
  end;

  -- Mantém lista de espera: pendentes ficam na fila mesmo com stock esgotado.
  update public.live_items
  set status = v_next_status
  where id = v_req.live_item_id;

  return jsonb_build_object(
    'ok', true,
    'request_id', v_req.id,
    'item_status', v_next_status,
    'reserved_qty', v_reserved_qty,
    'item_qty', v_item_qty
  );
end;
$$;

revoke all on function public.batata_process_live_reservation_request(uuid, text, uuid, text) from public;
grant execute on function public.batata_process_live_reservation_request(uuid, text, uuid, text) to authenticated;

create or replace function public.batata_live_bag_remove_request(
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.live_reservation_requests%rowtype;
begin
  select * into v_req
  from public.live_reservation_requests
  where id = p_request_id
  for update;

  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'request_not_found');
  end if;

  if auth.uid() is null
     or auth.uid() <> v_req.buyer_id
     or v_req.source <> 'fleaber_live'
     or v_req.status not in ('pending', 'accepted') then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  update public.live_reservation_requests
  set
    status = 'rejected',
    notes = coalesce(notes || ' | ', '') || 'bag_removed',
    updated_at = now()
  where id = v_req.id;

  perform public.batata_recompact_reservation_queue(v_req.live_item_id);
  perform public.batata_recompute_live_item_status(v_req.live_item_id);

  perform public.batata_live_system_message(
    v_req.live_id,
    '↩ Reserva cancelada pelo comprador',
    'Sistema'
  );

  return jsonb_build_object('ok', true, 'request_id', v_req.id);
end;
$$;

revoke all on function public.batata_live_bag_remove_request(uuid) from public;
grant execute on function public.batata_live_bag_remove_request(uuid) to authenticated;

drop policy if exists live_reservation_requests_select on public.live_reservation_requests;
create policy live_reservation_requests_select on public.live_reservation_requests
  for select using (
    seller_id = auth.uid()
    or buyer_id = auth.uid()
    or exists (
      select 1
      from public.lives l
      where l.id = live_reservation_requests.live_id
        and (l.seller_id = auth.uid() or l.vendedor_id = auth.uid())
    )
    or public.batata_staff_has_permission(seller_id, 'can_manage_reservations')
    or public.batata_staff_has_permission(seller_id, 'can_view_live_dashboard')
  );

drop policy if exists live_reservation_requests_insert on public.live_reservation_requests;
create policy live_reservation_requests_insert on public.live_reservation_requests
  for insert with check (
    (
      source = 'fleaber_live'
      and auth.uid() = buyer_id
    )
    or (
      source in ('facebook_manual', 'helper_manual')
      and (
        auth.uid() = seller_id
        or public.batata_staff_has_permission(seller_id, 'can_manage_reservations')
      )
    )
  );

drop policy if exists live_reservation_requests_update on public.live_reservation_requests;
create policy live_reservation_requests_update on public.live_reservation_requests
  for update using (
    seller_id = auth.uid()
    or exists (
      select 1
      from public.lives l
      where l.id = live_reservation_requests.live_id
        and (l.seller_id = auth.uid() or l.vendedor_id = auth.uid())
    )
    or public.batata_staff_has_permission(seller_id, 'can_manage_reservations')
  )
  with check (
    seller_id = auth.uid()
    or exists (
      select 1
      from public.lives l
      where l.id = live_reservation_requests.live_id
        and (l.seller_id = auth.uid() or l.vendedor_id = auth.uid())
    )
    or public.batata_staff_has_permission(seller_id, 'can_manage_reservations')
  );

-- Fila operacional via RPC (seller/staff; contorna falhas de RLS/realtime no select directo).
create or replace function public.batata_live_reservation_queue_for_live(
  p_live_id uuid,
  p_include_history boolean default true
)
returns setof public.live_reservation_requests
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_seller uuid;
begin
  if p_live_id is null then
    return;
  end if;

  select coalesce(l.seller_id, l.vendedor_id) into v_seller
  from public.lives l
  where l.id = p_live_id;

  if v_seller is null then
    return;
  end if;

  if not (
    auth.uid() = v_seller
    or public.batata_staff_has_permission(v_seller, 'can_manage_reservations')
    or public.batata_staff_has_permission(v_seller, 'can_view_live_dashboard')
  ) then
    raise exception 'not_allowed';
  end if;

  return query
  select r.*
  from public.live_reservation_requests r
  where r.live_id = p_live_id
    and (p_include_history or r.status = 'pending')
  order by r.created_at asc;
end;
$$;

revoke all on function public.batata_live_reservation_queue_for_live(uuid, boolean) from public;
grant execute on function public.batata_live_reservation_queue_for_live(uuid, boolean) to authenticated;
