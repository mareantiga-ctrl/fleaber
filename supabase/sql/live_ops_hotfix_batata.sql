-- Hotfix pós-testes (B/C/G): mark_sold + RLS reservas + stock vendidos.
-- Executar no SQL Editor se já tinhas aplicado versões antigas dos scripts.

-- Stock: contar encomendas pagas + mínimo 1 quando status=sold (mark_sold manual).
create or replace function public.batata_live_item_stock(p_live_item_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_live public.lives%rowtype;
  v_total integer;
  v_blocked integer := 0;
  v_reserved_accepted integer := 0;
  v_pending_bag integer := 0;
  v_sold_converted integer := 0;
  v_sold_orders integer := 0;
  v_available integer;
  v_product_id uuid;
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  select * into v_live from public.lives where id = v_li.live_id;

  v_total := public.batata_live_item_total_qty(v_li.id);
  v_product_id := coalesce(v_li.product_id, v_li.checkout_product_id);

  if v_product_id is not null then
    select coalesce(sum(o.quantity), 0)::int into v_blocked
    from public.orders o
    where o.product_id = v_product_id
      and coalesce(o.status, '') not in ('cancelado', 'cancelled', 'rejected', 'expired')
      and lower(trim(coalesce(o.status, ''))) in (
        'pago', 'enviado', 'reservado', 'aguarda_confirmacao',
        'pendente', 'pedido_devolucao', 'em_devolucao'
      );
  end if;

  select coalesce(sum(r.requested_qty), 0)::int into v_reserved_accepted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status in ('accepted', 'converted');

  select coalesce(sum(r.requested_qty), 0)::int into v_pending_bag
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'pending'
    and r.source = 'fleaber_live';

  select coalesce(sum(r.requested_qty), 0)::int into v_sold_converted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'converted';

  select coalesce(sum(o.quantity), 0)::int into v_sold_orders
  from public.orders o
  where lower(trim(coalesce(o.status, ''))) = 'pago'
    and (
      o.live_item_id = v_li.id
      or (
        o.live_id = v_li.live_id
        and v_product_id is not null
        and o.product_id = v_product_id
      )
    );

  v_sold_converted := greatest(v_sold_converted, v_sold_orders);

  v_available := v_total - v_blocked - v_reserved_accepted - v_pending_bag;
  if v_sold_converted >= greatest(v_total, 1) then
    v_available := 0;
  elsif v_available < 0 then
    v_available := 0;
  end if;

  return jsonb_build_object(
    'ok', true,
    'live_item_id', v_li.id,
    'live_id', v_li.live_id,
    'item_kind', v_li.item_kind,
    'product_id', v_li.product_id,
    'checkout_product_id', v_li.checkout_product_id,
    'ref_code', v_li.ref_code,
    'total_qty', v_total,
    'blocked_qty', v_blocked,
    'reserved_accepted_qty', v_reserved_accepted,
    'pending_bag_qty', v_pending_bag,
    'sold_converted_qty', v_sold_converted,
    'available_qty', v_available,
    'live_status', v_live.status
  );
end;
$$;

revoke all on function public.batata_live_item_stock(uuid) from public;
grant execute on function public.batata_live_item_stock(uuid) to authenticated;

-- Renumera fila pending (1..n) após cancelamento/rejeição.
create or replace function public.batata_recompact_reservation_queue(p_live_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated int := 0;
begin
  if p_live_item_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_live_item_id');
  end if;

  with ranked as (
    select
      r.id,
      row_number() over (
        order by r.queue_position nulls last, r.created_at asc
      )::int as new_pos
    from public.live_reservation_requests r
    where r.live_item_id = p_live_item_id
      and r.status = 'pending'
      and r.source = 'fleaber_live'
  )
  update public.live_reservation_requests r
  set
    queue_position = ranked.new_pos,
    updated_at = now()
  from ranked
  where r.id = ranked.id
    and coalesce(r.queue_position, -1) is distinct from ranked.new_pos;

  get diagnostics v_updated = row_count;

  return jsonb_build_object(
    'ok', true,
    'live_item_id', p_live_item_id,
    'reassigned', v_updated
  );
end;
$$;

revoke all on function public.batata_recompact_reservation_queue(uuid) from public;
grant execute on function public.batata_recompact_reservation_queue(uuid) to authenticated;
grant execute on function public.batata_recompact_reservation_queue(uuid) to service_role;

-- Chat FOMO: stock total>=2 e ficou exactamente 1 disponível (ex. pagamento parcial).
create or replace function public.batata_maybe_fomo_last_unit(p_live_item_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_stock jsonb;
  v_total int;
  v_avail int;
  v_ref text;
  v_body text;
begin
  if p_live_item_id is null then
    return false;
  end if;

  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return false;
  end if;

  v_stock := public.batata_live_item_stock(p_live_item_id);
  if coalesce((v_stock->>'ok')::boolean, false) is not true then
    return false;
  end if;

  v_total := coalesce((v_stock->>'total_qty')::int, 1);
  v_avail := coalesce((v_stock->>'available_qty')::int, 0);

  if v_total < 2 or v_avail <> 1 then
    return false;
  end if;

  v_ref := coalesce(nullif(trim(v_li.ref_code), ''), nullif(trim(v_li.title), ''), 'este artigo');
  v_body := '🔥 Ultima unidade — ' || v_ref;

  if exists (
    select 1
    from public.live_messages m
    where m.live_id = v_li.live_id
      and m.kind = 'system'
      and m.body = v_body
      and m.created_at > now() - interval '4 minutes'
  ) then
    return false;
  end if;

  perform public.batata_live_system_message(
    v_li.live_id,
    v_body,
    'Sistema'
  );

  return true;
end;
$$;

revoke all on function public.batata_maybe_fomo_last_unit(uuid) from public;
grant execute on function public.batata_maybe_fomo_last_unit(uuid) to authenticated;
grant execute on function public.batata_maybe_fomo_last_unit(uuid) to service_role;

-- B) Vendido: não pôr products.quantity = 0 (violava products_quantity_check).
create or replace function public.batata_mark_live_item_sold(p_live_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_live public.lives%rowtype;
  v_seller uuid;
begin
  select li.* into v_li
  from public.live_items li
  where li.id = p_live_item_id;

  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  select * into v_live from public.lives where id = v_li.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);

  if not (
    auth.uid() = v_seller
    or public.batata_staff_has_permission(v_seller, 'can_mark_items_sold')
    or public.batata_staff_has_permission(v_seller, 'can_change_current_item')
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  if v_li.item_kind = 'marketplace_product' and v_li.product_id is not null then
    update public.products
    set is_sold = true, list_on_marketplace = false
    where id = v_li.product_id;
  else
    if v_li.checkout_product_id is not null then
      update public.products
      set is_sold = true, list_on_marketplace = false
      where id = v_li.checkout_product_id;
    end if;
  end if;

  update public.live_reservation_requests
  set
    status = 'expired',
    notes = coalesce(notes || ' | ', '') || 'auto:item_vendido',
    updated_at = now()
  where live_item_id = v_li.id
    and status in ('pending', 'accepted');

  update public.live_items
  set
    status = 'sold',
    updated_at = now()
  where id = v_li.id;

  return public.batata_live_item_stock(v_li.id);
end;
$$;

-- Fila de reservas: não bloquear por stock/esgotado — regista interesse (lista de espera).
create or replace function public.batata_live_reservation_assign_queue()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max int;
  v_total int;
begin
  if TG_OP = 'INSERT' then
    v_total := public.batata_live_item_total_qty(new.live_item_id);
    new.requested_qty := greatest(
      least(coalesce(new.requested_qty, 1), greatest(v_total, 1)),
      1
    );
  end if;

  if new.queue_position is null then
    select coalesce(max(r.queue_position), 0)
    into v_max
    from public.live_reservation_requests r
    where r.live_id = new.live_id
      and r.live_item_id = new.live_item_id;

    new.queue_position := v_max + 1;
  end if;

  if new.status = 'pending' and new.expires_at is null then
    new.expires_at := now() + interval '45 minutes';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- Não aceitar reservas nem repor status quando o artigo já está vendido.
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
  v_item_status text;
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

  select coalesce(status, '') into v_item_status
  from public.live_items
  where id = v_req.live_item_id;

  if v_item_status = 'sold' and p_action in ('accept', 'convert') then
    return jsonb_build_object('ok', false, 'error', 'item_sold');
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
    expires_at = case
      when p_action = 'accept' then now() + interval '5 days'
      else expires_at
    end,
    notes = case
      when p_action = 'skip' then coalesce('skip:' || p_notes, 'skip')
      else coalesce(p_notes, notes)
    end,
    processed_by_user_id = coalesce(p_processed_by, auth.uid()),
    updated_at = now()
  where id = v_req.id;

  if v_item_status = 'sold' then
    return jsonb_build_object(
      'ok', true,
      'request_id', v_req.id,
      'item_status', 'sold'
    );
  end if;

  v_item_qty := public.batata_live_item_total_qty(v_req.live_item_id);

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

  if p_action in ('reject', 'skip', 'expire') then
    perform public.batata_recompact_reservation_queue(v_req.live_item_id);
  end if;

  perform public.batata_recompute_live_item_status(v_req.live_item_id);

  select coalesce(status, '') into v_next_status
  from public.live_items
  where id = v_req.live_item_id;

  if p_action = 'accept' then
    perform public.batata_live_reservation_accept_broadcast(
      v_req.live_id,
      v_req.buyer_id,
      v_req.live_item_id
    );
  elsif p_action = 'convert' then
    perform public.batata_live_purchase_broadcast(
      v_req.live_id,
      v_req.buyer_id,
      v_req.live_item_id
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'request_id', v_req.id,
    'item_status', v_next_status,
    'reserved_qty', v_reserved_qty,
    'item_qty', v_item_qty
  );
end;
$$;

-- C) Fila de reservas via RPC (contorna RLS/realtime quando select directo falha).
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

-- Comprador pode cancelar reserva pendente ou aceite (antes do pagamento).
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

  -- Repor estado do artigo (stock / reservas activas).
  select coalesce(p.quantity, 1)::int
  into v_item_qty
  from public.products p
  where p.id = (
    select li.product_id from public.live_items li where li.id = v_req.live_item_id
  );

  if v_item_qty is null or v_item_qty < 1 then
    select coalesce(li.quantity, 1)::int into v_item_qty
    from public.live_items li
    where li.id = v_req.live_item_id;
  end if;

  select coalesce(sum(r.requested_qty), 0)::int
  into v_reserved_qty
  from public.live_reservation_requests r
  where r.live_item_id = v_req.live_item_id
    and r.status in ('accepted', 'converted');

  perform public.batata_recompact_reservation_queue(v_req.live_item_id);
  perform public.batata_recompute_live_item_status(v_req.live_item_id);

  select coalesce(status, '') into v_next_status
  from public.live_items
  where id = v_req.live_item_id;

  return jsonb_build_object(
    'ok', true,
    'request_id', v_req.id,
    'item_status', v_next_status,
    'queue_recompacted', true
  );
end;
$$;

revoke all on function public.batata_live_bag_remove_request(uuid) from public;
grant execute on function public.batata_live_bag_remove_request(uuid) to authenticated;

-- C) Seller vê reservas da live mesmo se seller_id na linha divergir do auth.
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

-- Fix «Artigos do directo»: image_urls é text[] (não jsonb).
create or replace function public.batata_product_first_photo_url(p_image_urls jsonb)
returns text
language sql
immutable
as $$
  select case
    when p_image_urls is null then null
    when jsonb_typeof(p_image_urls) = 'array' and jsonb_array_length(p_image_urls) > 0
      then nullif(trim(p_image_urls->>0), '')
    else null
  end;
$$;

create or replace function public.batata_product_first_photo_url(p_image_urls text[])
returns text
language sql
immutable
as $$
  select case
    when p_image_urls is not null and array_length(p_image_urls, 1) > 0
      then nullif(trim(p_image_urls[1]), '')
    else null
  end;
$$;

create or replace function public.batata_upsert_marketplace_live_item(
  p_seller_id uuid,
  p_product_id uuid,
  p_live_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_live_id uuid;
  v_p public.products%rowtype;
  v_item_id uuid;
  v_ref text;
begin
  if p_seller_id is null or auth.uid() is distinct from p_seller_id then
    raise exception 'not_allowed';
  end if;

  select * into v_p from public.products p
  where p.id = p_product_id and p.seller_id = p_seller_id;
  if v_p.id is null then
    raise exception 'product_not_found';
  end if;

  v_live_id := coalesce(p_live_id, public.batata_ensure_draft_live(p_seller_id));
  v_ref := coalesce(nullif(trim(v_p.ref_code), ''), '#' || left(v_p.id::text, 6));

  select li.id into v_item_id
  from public.live_items li
  where li.live_id = v_live_id and li.product_id = v_p.id
  limit 1;

  if v_item_id is not null then
    update public.live_items
    set
      ref_code = v_ref,
      title = v_p.title,
      price = v_p.price,
      photo_url = coalesce(
        public.batata_product_first_photo_url(v_p.image_urls),
        photo_url
      ),
      item_kind = 'marketplace_product',
      quantity = null,
      updated_at = now()
    where id = v_item_id;
  else
    insert into public.live_items (
      live_id, item_kind, product_id, ref_code, title, price, photo_url,
      quantity, is_active, status, updated_at
    )
    values (
      v_live_id,
      'marketplace_product',
      v_p.id,
      v_ref,
      v_p.title,
      v_p.price,
      public.batata_product_first_photo_url(v_p.image_urls),
      null,
      false,
      'available',
      now()
    )
    returning id into v_item_id;
  end if;

  return v_item_id;
end;
$$;

revoke all on function public.batata_upsert_marketplace_live_item(uuid, uuid, uuid) from public;
grant execute on function public.batata_upsert_marketplace_live_item(uuid, uuid, uuid) to authenticated;

-- Fix «Artigos do directo»: image_urls é text[] (não jsonb).
create or replace function public.batata_product_first_photo_url(p_image_urls jsonb)
returns text
language sql
immutable
as $$
  select case
    when p_image_urls is null then null
    when jsonb_typeof(p_image_urls) = 'array' and jsonb_array_length(p_image_urls) > 0
      then nullif(trim(p_image_urls->>0), '')
    else null
  end;
$$;

create or replace function public.batata_product_first_photo_url(p_image_urls text[])
returns text
language sql
immutable
as $$
  select case
    when p_image_urls is not null and array_length(p_image_urls, 1) > 0
      then nullif(trim(p_image_urls[1]), '')
    else null
  end;
$$;

create or replace function public.batata_upsert_marketplace_live_item(
  p_seller_id uuid,
  p_product_id uuid,
  p_live_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_live_id uuid;
  v_p public.products%rowtype;
  v_item_id uuid;
  v_ref text;
begin
  if p_seller_id is null or auth.uid() is distinct from p_seller_id then
    raise exception 'not_allowed';
  end if;

  select * into v_p from public.products p
  where p.id = p_product_id and p.seller_id = p_seller_id;
  if v_p.id is null then
    raise exception 'product_not_found';
  end if;

  v_live_id := coalesce(p_live_id, public.batata_ensure_draft_live(p_seller_id));
  v_ref := coalesce(nullif(trim(v_p.ref_code), ''), '#' || left(v_p.id::text, 6));

  select li.id into v_item_id
  from public.live_items li
  where li.live_id = v_live_id and li.product_id = v_p.id
  limit 1;

  if v_item_id is not null then
    update public.live_items
    set
      ref_code = v_ref,
      title = v_p.title,
      price = v_p.price,
      photo_url = coalesce(
        public.batata_product_first_photo_url(v_p.image_urls),
        photo_url
      ),
      item_kind = 'marketplace_product',
      quantity = null,
      updated_at = now()
    where id = v_item_id;
  else
    insert into public.live_items (
      live_id, item_kind, product_id, ref_code, title, price, photo_url,
      quantity, is_active, status, updated_at
    )
    values (
      v_live_id,
      'marketplace_product',
      v_p.id,
      v_ref,
      v_p.title,
      v_p.price,
      public.batata_product_first_photo_url(v_p.image_urls),
      null,
      false,
      'available',
      now()
    )
    returning id into v_item_id;
  end if;

  return v_item_id;
end;
$$;

revoke all on function public.batata_upsert_marketplace_live_item(uuid, uuid, uuid) from public;
grant execute on function public.batata_upsert_marketplace_live_item(uuid, uuid, uuid) to authenticated;

-- Stripe: converter apenas UMA reserva (evita pagar uma linha e converter todas).
create or replace function public.batata_live_reservation_stripe_convert(
  p_request_id uuid,
  p_order_id uuid default null
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
  v_converted_qty int := 0;
  v_next_status text;
begin
  select * into v_req
  from public.live_reservation_requests
  where id = p_request_id
  for update;

  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'request_not_found');
  end if;

  if v_req.status not in ('pending', 'accepted') then
    return jsonb_build_object(
      'ok', false,
      'error', 'invalid_status',
      'status', v_req.status
    );
  end if;

  update public.live_reservation_requests
  set
    status = 'converted',
    notes = case
      when p_order_id is not null then
        coalesce(notes || ' | ', '') || 'stripe_paid:' || p_order_id::text
      else coalesce(notes, 'stripe_paid')
    end,
    updated_at = now()
  where id = v_req.id;

  v_item_qty := public.batata_live_item_total_qty(v_req.live_item_id);

  select coalesce(sum(r.requested_qty), 0)::int
  into v_reserved_qty
  from public.live_reservation_requests r
  where r.live_item_id = v_req.live_item_id
    and r.status in ('accepted', 'converted');

  select coalesce(sum(r.requested_qty), 0)::int
  into v_converted_qty
  from public.live_reservation_requests r
  where r.live_item_id = v_req.live_item_id
    and r.status = 'converted';

  v_next_status := case
    when v_converted_qty >= greatest(v_item_qty, 1) then 'sold'
    when v_reserved_qty <= 0 then 'available'
    when v_reserved_qty < greatest(v_item_qty, 1) then 'reserved_partial'
    when v_reserved_qty >= greatest(v_item_qty, 1) then 'reserved_full'
    else 'available'
  end;

  perform public.batata_recompute_live_item_status(v_req.live_item_id);
  perform public.batata_maybe_fomo_last_unit(v_req.live_item_id);

  select coalesce(status, '') into v_next_status
  from public.live_items
  where id = v_req.live_item_id;

  return jsonb_build_object(
    'ok', true,
    'request_id', v_req.id,
    'live_item_id', v_req.live_item_id,
    'item_status', v_next_status
  );
end;
$$;

revoke all on function public.batata_live_reservation_stripe_convert(uuid, uuid) from public;
grant execute on function public.batata_live_reservation_stripe_convert(uuid, uuid) to service_role;
grant execute on function public.batata_live_reservation_stripe_convert(uuid, uuid) to authenticated;

-- Reconciliar encomenda paga ↔ reserva convertida (fallback se a edge falhar).
create or replace function public.batata_live_reconcile_stripe_order(
  p_order_id uuid,
  p_reservation_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_request_id uuid;
  v_req public.live_reservation_requests%rowtype;
  v_convert jsonb;
begin
  select * into v_order
  from public.orders
  where id = p_order_id;

  if v_order.id is null then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  if coalesce(v_order.price_total, 0) <= 0
     and v_order.product_id is not null then
    update public.orders o
    set price_total = p.price * greatest(coalesce(o.quantity, 1), 1)
    from public.products p
    where o.id = p_order_id
      and p.id = v_order.product_id
      and coalesce(o.price_total, 0) <= 0
      and coalesce(p.price, 0) > 0;
    select * into v_order from public.orders where id = p_order_id;
  end if;

  if lower(trim(coalesce(v_order.status, ''))) not in (
    'pago', 'enviado', 'aguarda_confirmacao'
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'order_not_paid',
      'status', v_order.status
    );
  end if;

  if auth.uid() is not null
     and auth.uid() is distinct from v_order.buyer_id
     and auth.uid() is distinct from v_order.seller_id
     and not public.batata_staff_has_permission(
       v_order.seller_id, 'can_manage_reservations'
     ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  v_request_id := p_reservation_request_id;

  if v_request_id is null and v_order.live_id is not null then
    select r.id into v_request_id
    from public.live_reservation_requests r
    where r.live_id = v_order.live_id
      and r.buyer_id = v_order.buyer_id
      and r.source = 'fleaber_live'
      and r.status in ('pending', 'accepted')
      and (
        v_order.live_item_id is null
        or r.live_item_id = v_order.live_item_id
      )
      and coalesce(r.notes, '') ilike (
        '%stripe_checkout:' || p_order_id::text || '%'
      )
    order by r.queue_position nulls last, r.created_at asc
    limit 1;
  end if;

  if v_request_id is null and v_order.live_id is not null then
    select r.id into v_request_id
    from public.live_reservation_requests r
    where r.live_id = v_order.live_id
      and r.buyer_id = v_order.buyer_id
      and r.source = 'fleaber_live'
      and r.status in ('pending', 'accepted')
      and (
        v_order.live_item_id is null
        or r.live_item_id = v_order.live_item_id
      )
    order by r.queue_position nulls last, r.created_at asc
    limit 1;
  end if;

  for v_req in
    select *
    from public.live_reservation_requests r
    where r.status in ('pending', 'accepted')
      and (
        (v_request_id is not null and r.id = v_request_id)
        or coalesce(r.notes, '') ilike (
          '%stripe_checkout:' || p_order_id::text || '%'
        )
      )
    order by r.queue_position nulls last, r.created_at asc
  loop
    update public.orders o
    set
      live_id = coalesce(o.live_id, v_req.live_id),
      live_item_id = coalesce(o.live_item_id, v_req.live_item_id),
      seller_id = coalesce(o.seller_id, v_req.seller_id)
    where o.id = p_order_id;
    select * into v_order from public.orders where id = p_order_id;

    v_convert := public.batata_live_reservation_stripe_convert(
      v_req.id,
      p_order_id
    );
    if coalesce((v_convert->>'ok')::boolean, false) then
      return v_convert || jsonb_build_object('reconciled', true);
    end if;
  end loop;

  if v_order.live_id is not null
     and v_order.live_item_id is not null
     and v_order.buyer_id is not null then
    if not exists (
      select 1
      from public.live_reservation_requests r
      where r.live_id = v_order.live_id
        and r.buyer_id = v_order.buyer_id
        and r.live_item_id = v_order.live_item_id
        and r.status = 'converted'
        and coalesce(r.notes, '') ilike (
          '%stripe_paid:' || p_order_id::text || '%'
        )
    ) then
      insert into public.live_reservation_requests (
        live_id,
        live_item_id,
        seller_id,
        buyer_id,
        requested_qty,
        source,
        status,
        notes
      )
      values (
        v_order.live_id,
        v_order.live_item_id,
        v_order.seller_id,
        v_order.buyer_id,
        greatest(coalesce(v_order.quantity, 1), 1),
        'fleaber_live',
        'converted',
        'stripe_paid_direct:' || p_order_id::text
      );
    end if;

    return jsonb_build_object(
      'ok', true,
      'direct_insert', true,
      'live_item_id', v_order.live_item_id
    );
  end if;

  return jsonb_build_object('ok', false, 'error', 'no_request_to_convert');
end;
$$;

revoke all on function public.batata_live_reconcile_stripe_order(uuid, uuid) from public;
grant execute on function public.batata_live_reconcile_stripe_order(uuid, uuid) to authenticated;
grant execute on function public.batata_live_reconcile_stripe_order(uuid, uuid) to service_role;

-- Timer do directo (comprador): âncora quando a vendedora entra em LIVE.
alter table public.lives
  add column if not exists went_live_at timestamptz;

update public.lives
set went_live_at = created_at
where went_live_at is null
  and lower(coalesce(status, '')) in ('live', 'ended');

comment on column public.lives.went_live_at is
  'Momento em que o directo passou a LIVE (timer comprador/vendedor).';

-- Recalcula live_items.status (available / reserved_partial / reserved_full) a partir de
-- stock bloqueado (encomendas marketplace reservado/pago + fila live). Não altera «sold».
create or replace function public.batata_recompute_live_item_status(p_live_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_stock jsonb;
  v_total int;
  v_available int;
  v_blocked int;
  v_reserved int;
  v_converted int;
  v_next_status text;
begin
  select * into v_li
  from public.live_items
  where id = p_live_item_id
  for update;

  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  v_stock := public.batata_live_item_stock(p_live_item_id);
  if coalesce((v_stock->>'ok')::boolean, false) is not true then
    return v_stock;
  end if;

  v_total := coalesce((v_stock->>'total_qty')::int, 1);
  v_available := coalesce((v_stock->>'available_qty')::int, 0);
  v_blocked := coalesce((v_stock->>'blocked_qty')::int, 0);
  v_reserved := coalesce((v_stock->>'reserved_accepted_qty')::int, 0);
  v_converted := coalesce((v_stock->>'sold_converted_qty')::int, 0);

  -- ESGOTADO (reserved_full) só com reservas ACEITES/convertidas a cobrir o stock — pending não conta.
  v_next_status := case
    when v_converted >= greatest(v_total, 1) then 'sold'
    when v_reserved >= greatest(v_total, 1) then 'reserved_full'
    when v_reserved > 0 then 'reserved_partial'
    when v_blocked > 0 and v_available <= 0 then 'reserved_full'
    else 'available'
  end;

  if coalesce(v_li.status, '') is distinct from v_next_status then
    update public.live_items
    set status = v_next_status, updated_at = now()
    where id = v_li.id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'live_item_id', v_li.id,
    'item_status', v_next_status,
    'total_qty', v_total,
    'available_qty', v_available,
    'blocked_qty', v_blocked,
    'reserved_accepted_qty', v_reserved
  );
end;
$$;

revoke all on function public.batata_recompute_live_item_status(uuid) from public;
grant execute on function public.batata_recompute_live_item_status(uuid) to authenticated;
grant execute on function public.batata_recompute_live_item_status(uuid) to service_role;

-- Após aceitar/recusar/cancelar reserva marketplace com contexto live, actualiza o catálogo.
create or replace function public.batata_sync_live_item_for_order(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_live_item_id uuid;
begin
  select * into v_order
  from public.orders
  where id = p_order_id;

  if v_order.id is null then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  v_live_item_id := v_order.live_item_id;

  if v_live_item_id is null
     and v_order.live_id is not null
     and v_order.product_id is not null then
    select li.id into v_live_item_id
    from public.live_items li
    where li.live_id = v_order.live_id
      and li.product_id = v_order.product_id
    order by li.created_at desc
    limit 1;
  end if;

  if v_live_item_id is null then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'no_live_item');
  end if;

  if auth.uid() is not null
     and auth.uid() is distinct from v_order.seller_id
     and auth.uid() is distinct from v_order.buyer_id
     and not public.batata_staff_has_permission(
       v_order.seller_id, 'can_manage_reservations'
     ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  return public.batata_recompute_live_item_status(v_live_item_id);
end;
$$;

revoke all on function public.batata_sync_live_item_for_order(uuid) from public;
grant execute on function public.batata_sync_live_item_for_order(uuid) to authenticated;
grant execute on function public.batata_sync_live_item_for_order(uuid) to service_role;

-- Chat: reserva aceite pelo vendedor (saco live).
create or replace function public.batata_live_reservation_accept_broadcast(
  p_live_id uuid,
  p_buyer_id uuid,
  p_live_item_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_ref text;
  v_title text;
  v_label text;
  v_body text;
begin
  if p_live_id is null or p_buyer_id is null or p_live_item_id is null then
    return false;
  end if;

  select coalesce(nullif(trim(full_name), ''), 'Comprador')
  into v_name
  from public.profiles
  where id = p_buyer_id;

  select coalesce(nullif(trim(ref_code), ''), ''),
         coalesce(nullif(trim(title), ''), '')
  into v_ref, v_title
  from public.live_items
  where id = p_live_item_id
  limit 1;

  if v_ref <> '' then
    v_label := 'Ref ' || v_ref;
  elsif v_title <> '' then
    v_label := v_title;
  else
    v_label := 'artigo';
  end if;

  v_body := '🔒 Reserva aceite — ' || v_label || ' · ' || v_name || ' tem 5 dias para pagar';

  if exists (
    select 1
    from public.live_messages m
    where m.live_id = p_live_id
      and m.kind = 'system'
      and m.body = v_body
      and m.created_at > now() - interval '15 minutes'
  ) then
    return false;
  end if;

  insert into public.live_messages (
    live_id,
    user_id,
    kind,
    body,
    sender_label
  ) values (
    p_live_id,
    p_buyer_id,
    'system',
    v_body,
    'Sistema'
  );

  return true;
end;
$$;

revoke all on function public.batata_live_reservation_accept_broadcast(uuid, uuid, uuid) from public;
grant execute on function public.batata_live_reservation_accept_broadcast(uuid, uuid, uuid) to authenticated;
grant execute on function public.batata_live_reservation_accept_broadcast(uuid, uuid, uuid) to service_role;

-- Após editar quantidade no catálogo, repõe available / tira sold se houver stock.
create or replace function public.batata_update_live_item(
  p_live_item_id uuid,
  p_quantity integer default null,
  p_price numeric default null,
  p_title text default null,
  p_clothing_size text default null,
  p_gender text default null,
  p_ref_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_live public.lives%rowtype;
  v_seller uuid;
  v_qty integer;
  v_stock jsonb;
begin
  select li.* into v_li
  from public.live_items li
  where li.id = p_live_item_id;

  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  select * into v_live from public.lives where id = v_li.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);

  if not (
    auth.uid() = v_seller
    or public.batata_staff_has_permission(v_seller, 'can_change_current_item')
    or public.batata_staff_has_permission(v_seller, 'can_view_live_dashboard')
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  v_qty := greatest(coalesce(p_quantity, 1), 1);

  if v_li.item_kind = 'marketplace_product' and v_li.product_id is not null then
    update public.products
    set
      quantity = coalesce(p_quantity, quantity),
      price = coalesce(p_price, price),
      title = coalesce(nullif(trim(p_title), ''), title),
      clothing_size = case when p_clothing_size is not null then nullif(trim(p_clothing_size), '') else clothing_size end,
      gender = case when p_gender is not null then nullif(trim(p_gender), '') else gender end
    where id = v_li.product_id;

    update public.live_items
    set
      title = coalesce(nullif(trim(p_title), ''), title),
      price = coalesce(p_price, price),
      clothing_size = case when p_clothing_size is not null then nullif(trim(p_clothing_size), '') else clothing_size end,
      gender = case when p_gender is not null then nullif(trim(p_gender), '') else gender end,
      updated_at = now()
    where id = v_li.id;
  else
    update public.live_items
    set
      quantity = coalesce(p_quantity, quantity),
      price = coalesce(p_price, price),
      title = coalesce(nullif(trim(p_title), ''), title),
      ref_code = coalesce(nullif(trim(p_ref_code), ''), ref_code),
      clothing_size = case when p_clothing_size is not null then nullif(trim(p_clothing_size), '') else clothing_size end,
      gender = case when p_gender is not null then nullif(trim(p_gender), '') else gender end,
      updated_at = now()
    where id = v_li.id;

    if v_li.checkout_product_id is not null and p_quantity is not null then
      update public.products
      set quantity = v_qty
      where id = v_li.checkout_product_id;
    end if;
  end if;

  perform public.batata_recompute_live_item_status(v_li.id);

  return public.batata_live_item_stock(v_li.id);
end;
$$;

revoke all on function public.batata_update_live_item(uuid, integer, numeric, text, text, text, text) from public;
grant execute on function public.batata_update_live_item(uuid, integer, numeric, text, text, text, text) to authenticated;
