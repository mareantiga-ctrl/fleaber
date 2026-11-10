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
  v_blocked_orders integer := 0;
  v_blocked_cross_res integer := 0;
  v_reserved_accepted integer := 0;
  v_pending_bag integer := 0;
  v_sold_converted integer := 0;
  v_sold_orders integer := 0;
  v_available integer;
  v_product_id uuid;
  v_seller uuid;
  v_unit_price numeric;
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  select * into v_live from public.lives where id = v_li.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);

  v_total := public.batata_live_item_total_qty(v_li.id);
  v_product_id := coalesce(v_li.product_id, v_li.checkout_product_id);

  if v_product_id is not null then
    select coalesce(sum(o.quantity), 0)::int into v_blocked_orders
    from public.orders o
    where o.product_id = v_product_id
      and coalesce(o.status, '') not in ('cancelado', 'cancelled', 'rejected', 'expired')
      and lower(trim(coalesce(o.status, ''))) in (
        'pago', 'enviado', 'reservado', 'aguarda_confirmacao',
        'pendente', 'pedido_devolucao', 'em_devolucao'
      );

    select coalesce(sum(r.requested_qty), 0)::int into v_blocked_cross_res
    from public.live_reservation_requests r
    join public.live_items li2 on li2.id = r.live_item_id
    where r.status in ('pending', 'accepted')
      and li2.id <> v_li.id
      and coalesce(li2.product_id, li2.checkout_product_id) = v_product_id;
  elsif v_seller is not null
    and v_li.ref_code is not null
    and trim(v_li.ref_code) <> '' then
    select coalesce(sum(r.requested_qty), 0)::int into v_blocked_cross_res
    from public.live_reservation_requests r
    join public.live_items li2 on li2.id = r.live_item_id
    join public.lives l2 on l2.id = li2.live_id
    where r.status in ('pending', 'accepted')
      and li2.id <> v_li.id
      and lower(trim(li2.ref_code)) = lower(trim(v_li.ref_code))
      and coalesce(l2.seller_id, l2.vendedor_id) = v_seller;
  end if;

  v_blocked := v_blocked_orders + v_blocked_cross_res;

  select coalesce(sum(r.requested_qty), 0)::int into v_reserved_accepted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'accepted'
    and not exists (
      select 1
      from public.orders o
      where o.buyer_id = r.buyer_id
        and lower(trim(coalesce(o.status, ''))) in (
          'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
        )
        and (
          o.live_item_id = v_li.id
          or (
            o.live_id = v_li.live_id
            and v_product_id is not null
            and o.product_id = v_product_id
          )
        )
    );

  select coalesce(sum(r.requested_qty), 0)::int into v_pending_bag
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'pending'
    and r.source = 'fleaber_live'
    and not exists (
      select 1
      from public.orders o
      where o.buyer_id = r.buyer_id
        and o.live_item_id = v_li.id
        and lower(trim(coalesce(o.status, ''))) in (
          'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
        )
    );

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

  if v_li.product_id is not null then
    select coalesce(nullif(v_li.price, 0), p.price) into v_unit_price
    from public.products p
    where p.id = v_li.product_id;
  else
    v_unit_price := v_li.price;
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
    'live_status', v_live.status,
    'price', v_unit_price
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
    -- Não capar ao stock: pedidos acima do disponível usam qty_confirm_needed (R6).
    new.requested_qty := greatest(coalesce(new.requested_qty, 1), 1);
  end if;

  if new.queue_position is null then
    -- Só pendentes contam: cancelados/rejeitados mantêm posição antiga na linha.
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
  v_sibling_qty int := 0;
  v_final_qty int := 1;
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

  -- Aceite: agregar qty de reservas irmãs do mesmo comprador/artigo e fechar duplicados.
  if p_action = 'accept' then
    select coalesce(sum(r.requested_qty), 0)::int
    into v_sibling_qty
    from public.live_reservation_requests r
    where r.live_item_id = v_req.live_item_id
      and r.live_id = v_req.live_id
      and r.buyer_id = v_req.buyer_id
      and r.id <> v_req.id
      and r.status = 'pending';

    update public.live_reservation_requests
    set
      status = 'rejected',
      notes = trim(both ' |' from coalesce(notes, '') || ' | superseded:sibling_accept'),
      updated_at = now()
    where live_item_id = v_req.live_item_id
      and live_id = v_req.live_id
      and buyer_id = v_req.buyer_id
      and id <> v_req.id
      and status = 'pending';

    v_final_qty := greatest(
      coalesce(v_req.requested_qty, 1) + coalesce(v_sibling_qty, 0),
      1
    );
  end if;

  update public.live_reservation_requests
  set
    requested_qty = case
      when p_action = 'accept' then v_final_qty
      else requested_qty
    end,
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
      when p_action = 'accept' then trim(both ' |' from regexp_replace(
        regexp_replace(coalesce(notes, ''), 'qty_confirm_needed', '', 'gi'),
        '\s*\|\s*\|', ' | ', 'g'))
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
      v_req.live_item_id,
      v_final_qty
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
    queue_position = null,
    updated_at = now()
  where id = v_req.id;

  perform public.batata_live_system_message(
    v_req.live_id,
    '↩ Reserva cancelada pelo comprador',
    'Sistema'
  );

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

-- Comprador altera quantidade no saco (pendente ou aceite, antes do pagamento).
create or replace function public.batata_live_bag_update_qty(
  p_request_id uuid,
  p_qty int
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.live_reservation_requests%rowtype;
  v_qty int;
begin
  select * into v_req
  from public.live_reservation_requests
  where id = p_request_id
  for update;

  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'request_not_found');
  end if;

  v_qty := greatest(least(coalesce(p_qty, 1), 9999), 1);

  if auth.uid() is null
     or auth.uid() <> v_req.buyer_id
     or v_req.source <> 'fleaber_live'
     or v_req.status not in ('pending', 'accepted') then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  update public.live_reservation_requests
  set
    requested_qty = v_qty,
    updated_at = now()
  where id = v_req.id;

  return jsonb_build_object(
    'ok', true,
    'request_id', v_req.id,
    'requested_qty', v_qty
  );
end;
$$;

revoke all on function public.batata_live_bag_update_qty(uuid, int) from public;
grant execute on function public.batata_live_bag_update_qty(uuid, int) to authenticated;

-- Comprador marca reserva após checkout com qty > stock (card urgente vendedora).
create or replace function public.batata_live_mark_qty_confirm_needed(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.live_reservation_requests%rowtype;
  v_notes text;
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

  v_notes := trim(coalesce(v_req.notes, ''));
  if v_notes ilike '%qty_confirm_needed%' then
    return jsonb_build_object('ok', true, 'request_id', v_req.id, 'already_marked', true);
  end if;

  update public.live_reservation_requests
  set
    notes = case
      when v_notes = '' then 'qty_confirm_needed'
      else v_notes || ' | qty_confirm_needed'
    end,
    updated_at = now()
  where id = v_req.id;

  return jsonb_build_object('ok', true, 'request_id', v_req.id, 'already_marked', false);
end;
$$;

revoke all on function public.batata_live_mark_qty_confirm_needed(uuid) from public;
grant execute on function public.batata_live_mark_qty_confirm_needed(uuid) to authenticated;

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

  if lower(trim(coalesce(v_order.status, ''))) in (
       'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
     )
     and v_order.buyer_id is not null then
    update public.live_reservation_requests r
    set
      status = 'converted',
      notes = case
        when coalesce(r.notes, '') ilike '%direct_paid:%' then r.notes
        else coalesce(nullif(trim(r.notes), '') || ' | ', '') ||
          'direct_paid:' || p_order_id::text
      end,
      updated_at = now()
    where r.live_item_id = v_live_item_id
      and r.buyer_id = v_order.buyer_id
      and r.status in ('pending', 'accepted');
  end if;

  return public.batata_recompute_live_item_status(v_live_item_id);
end;
$$;

revoke all on function public.batata_sync_live_item_for_order(uuid) from public;
grant execute on function public.batata_sync_live_item_for_order(uuid) to authenticated;
grant execute on function public.batata_sync_live_item_for_order(uuid) to service_role;

-- Chat: reserva aceite pelo vendedor (saco live).
drop function if exists public.batata_live_reservation_accept_broadcast(uuid, uuid, uuid);

create or replace function public.batata_live_reservation_accept_broadcast(
  p_live_id uuid,
  p_buyer_id uuid,
  p_live_item_id uuid,
  p_requested_qty integer default 1
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
  v_qty integer;
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

  if v_title <> '' then
    v_label := v_title;
  elsif v_ref <> '' then
    v_label := 'Ref ' || v_ref;
  else
    v_label := 'artigo';
  end if;

  v_qty := greatest(coalesce(p_requested_qty, 1), 1);
  if v_qty > 1 then
    v_body := '🔒 Reserva aceite — ' || v_qty || ' un. · ' || v_label
      || ' · ' || v_name || ' tem 5 dias para pagar';
  else
    v_body := '🔒 Reserva aceite — ' || v_label || ' · ' || v_name
      || ' tem 5 dias para pagar';
  end if;

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

revoke all on function public.batata_live_reservation_accept_broadcast(uuid, uuid, uuid, integer) from public;
grant execute on function public.batata_live_reservation_accept_broadcast(uuid, uuid, uuid, integer) to authenticated;
grant execute on function public.batata_live_reservation_accept_broadcast(uuid, uuid, uuid, integer) to service_role;

-- V1 price pending: lock pós-venda, broadcast preço definido.
create or replace function public.batata_live_item_price_locked(p_live_item_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.live_reservation_requests r
    where r.live_item_id = p_live_item_id
      and r.status = 'converted'
  )
  or exists (
    select 1
    from public.orders o
    where o.live_item_id = p_live_item_id
      and lower(trim(coalesce(o.status, ''))) in ('pago', 'paid')
  );
$$;

create or replace function public.batata_live_price_defined_broadcast(
  p_live_id uuid,
  p_live_item_id uuid,
  p_price numeric
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
  v_ref text;
  v_label text;
  v_body text;
  v_price_txt text;
  v_uid uuid := auth.uid();
begin
  if p_live_id is null or p_live_item_id is null then
    return false;
  end if;
  if p_price is null or p_price <= 0 then
    return false;
  end if;

  select coalesce(nullif(trim(title), ''), ''),
         coalesce(nullif(trim(ref_code), ''), '')
  into v_title, v_ref
  from public.live_items
  where id = p_live_item_id
  limit 1;

  if v_title <> '' then
    v_label := v_title;
  elsif v_ref <> '' then
    v_label := v_ref;
  else
    v_label := 'artigo';
  end if;

  v_price_txt := replace(trim(to_char(p_price, 'FM999999990.00')), '.', ',');
  v_body := '💶 Preço definido · ' || v_label || ' · ' || v_price_txt || '€';

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
    coalesce(v_uid, (select coalesce(l.seller_id, l.vendedor_id) from public.lives l where l.id = p_live_id)),
    'system',
    v_body,
    'Sistema'
  );

  return true;
end;
$$;

revoke all on function public.batata_live_price_defined_broadcast(uuid, uuid, numeric) from public;
grant execute on function public.batata_live_price_defined_broadcast(uuid, uuid, numeric) to authenticated;
grant execute on function public.batata_live_price_defined_broadcast(uuid, uuid, numeric) to service_role;

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
  v_old_price numeric;
  v_new_price numeric;
  v_should_broadcast boolean := false;
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

  v_old_price := v_li.price;
  v_qty := greatest(coalesce(p_quantity, 1), 1);

  if p_price is not null
     and p_price is distinct from v_old_price
     and public.batata_live_item_price_locked(p_live_item_id) then
    return jsonb_build_object('ok', false, 'error', 'price_locked_after_sale');
  end if;

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

    if v_li.checkout_product_id is not null then
      update public.products
      set
        quantity = case when p_quantity is not null then v_qty else quantity end,
        price = case when p_price is not null then p_price else price end,
        title = coalesce(nullif(trim(p_title), ''), title)
      where id = v_li.checkout_product_id;
    end if;
  end if;

  perform public.batata_recompute_live_item_status(v_li.id);

  if p_quantity is not null and v_li.product_id is not null then
    update public.products
    set is_sold = false, list_on_marketplace = true
    where id = v_li.product_id
      and is_sold = true
      and exists (
        select 1
        from public.live_items li2
        where li2.id = v_li.id
          and coalesce(li2.status, '') <> 'sold'
      );
  end if;

  select li.price into v_new_price
  from public.live_items li
  where li.id = p_live_item_id;

  if p_price is not null and v_new_price is not null and v_new_price > 0 then
    if coalesce(v_old_price, 0) <= 0 then
      v_should_broadcast := true;
    elsif v_old_price is distinct from v_new_price then
      v_should_broadcast := true;
    end if;
  end if;

  if v_should_broadcast then
    perform public.batata_live_price_defined_broadcast(
      v_li.live_id,
      v_li.id,
      v_new_price
    );
  end if;

  return public.batata_live_item_stock(v_li.id);
end;
$$;

revoke all on function public.batata_update_live_item(uuid, integer, numeric, text, text, text, text) from public;
grant execute on function public.batata_update_live_item(uuid, integer, numeric, text, text, text, text) to authenticated;

-- Repor quantidade real mesmo com live_items.status = sold (edição pós-venda no catálogo).
create or replace function public.batata_live_item_total_qty(p_live_item_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_qty integer;
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return 0;
  end if;

  if v_li.item_kind = 'marketplace_product' and v_li.product_id is not null then
    select coalesce(p.quantity, 1) into v_qty
    from public.products p
    where p.id = v_li.product_id;
    return greatest(coalesce(v_qty, 1), 1);
  end if;

  return greatest(coalesce(v_li.quantity, 1), 1);
end;
$$;

revoke all on function public.batata_live_item_total_qty(uuid) from public;
grant execute on function public.batata_live_item_total_qty(uuid) to authenticated;

-- Logs DB: criar/alterar reserva (R6 diagnóstico; não depende do painel vendedora aberto).
create or replace function public.batata_log_reservation_request_tg()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event text;
  v_detail jsonb;
begin
  if TG_OP = 'INSERT' then
    v_event := 'reservation.create';
    v_detail := jsonb_build_object(
      'step', v_event,
      'status', coalesce(new.status, 'pending'),
      'requested_qty', coalesce(new.requested_qty, 1),
      'queue_position', new.queue_position,
      'buyer_id', new.buyer_id,
      'source', coalesce(new.source, 'fleaber_live')
    );
  elsif TG_OP = 'UPDATE' and coalesce(old.status, '') is distinct from coalesce(new.status, '') then
    v_event := 'reservation.status';
    v_detail := jsonb_build_object(
      'step', v_event,
      'old_status', old.status,
      'new_status', new.status,
      'requested_qty', coalesce(new.requested_qty, 1),
      'buyer_id', new.buyer_id
    );
  else
    return new;
  end if;

  insert into public.live_vendor_studio_logs (
    live_id,
    seller_id,
    actor_id,
    live_item_id,
    request_id,
    event,
    status,
    detail
  ) values (
    new.live_id,
    new.seller_id,
    auth.uid(),
    new.live_item_id,
    new.id,
    v_event,
    'ok',
    v_detail
  );

  return new;
exception
  when others then
    return new;
end;
$$;

drop trigger if exists batata_log_reservation_request_tg on public.live_reservation_requests;
create trigger batata_log_reservation_request_tg
  after insert or update of status, requested_qty on public.live_reservation_requests
  for each row
  execute function public.batata_log_reservation_request_tg();

-- Chat: compra confirmada — título antes de referência (alinha com app).
create or replace function public.batata_live_purchase_broadcast(
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

  if v_title <> '' then
    v_label := v_title;
  elsif v_ref <> '' then
    v_label := 'Ref ' || v_ref;
  else
    v_label := 'artigo';
  end if;

  v_body := '✅ ' || v_name || ' comprou ' || v_label;

  if exists (
    select 1
    from public.live_messages m
    where m.live_id = p_live_id
      and m.kind = 'system'
      and m.user_id = p_buyer_id
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
    v_name
  );

  return true;
end;
$$;

revoke all on function public.batata_live_purchase_broadcast(uuid, uuid, uuid) from public;
grant execute on function public.batata_live_purchase_broadcast(uuid, uuid, uuid) to authenticated;
grant execute on function public.batata_live_purchase_broadcast(uuid, uuid, uuid) to service_role;

-- V1.5: logical_item_id — linhagens live_only (ficheiro: live_logical_item_id_batata.sql)
alter table public.live_items
  add column if not exists logical_item_id uuid;

create index if not exists live_items_logical_item_id_idx
  on public.live_items (logical_item_id)
  where logical_item_id is not null;

update public.live_items
set logical_item_id = id
where item_kind = 'live_only'
  and logical_item_id is null;

create or replace function public.batata_live_origin_label(p_live_id uuid)
returns text
language sql
stable
as $$
  select case
    when p_live_id is null then 'Marketplace'
    when exists (
      select 1
      from public.lives lv
      where lv.id = p_live_id
        and (
          coalesce(lv.mux_vod_playback_id, lv.mux_playback_id, lv.playback_id, '')
            <> ''
          or lower(coalesce(lv.status, '')) in ('ended')
        )
    ) then 'Gravado'
    else 'Direto anterior'
  end;
$$;

create or replace function public.batata_live_items_lineage_match(
  p_catalog public.live_items,
  p_source public.live_items
)
returns boolean
language sql
immutable
as $$
  select
    (p_catalog.product_id is not null and p_source.product_id = p_catalog.product_id)
    or (
      p_catalog.checkout_product_id is not null
      and p_source.checkout_product_id = p_catalog.checkout_product_id
    )
    or (
      p_catalog.logical_item_id is not null
      and p_source.logical_item_id is not null
      and p_catalog.logical_item_id = p_source.logical_item_id
    )
    or (
      p_catalog.logical_item_id is null
      and p_catalog.item_kind = 'live_only'
      and public.batata_normalize_ref(p_catalog.ref_code) <> ''
      and public.batata_normalize_ref(p_source.ref_code)
        = public.batata_normalize_ref(p_catalog.ref_code)
      and p_source.logical_item_id = p_source.id
    );
$$;

-- V1: aviso antes de iniciar directo — reservas/pedidos em aberto.
-- (cópia inline; ficheiro dedicado: live_start_open_reservations_batata.sql)

create or replace function public.batata_live_start_open_reservations_check(p_live_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_seller uuid;
  v_result jsonb;
begin
  if p_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'live_id_required');
  end if;

  select coalesce(l.seller_id, l.vendedor_id) into v_seller
  from public.lives l
  where l.id = p_live_id;

  if v_seller is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  if not (
    auth.uid() = v_seller
    or public.batata_staff_has_permission(v_seller, 'can_manage_reservations')
    or public.batata_staff_has_permission(v_seller, 'can_view_live_dashboard')
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  with catalog as (
    select li.*
    from public.live_items li
    where li.live_id = p_live_id
  ),
  matched_requests as (
    select
      ci.id as catalog_item_id,
      r.id::text as entry_id,
      'live_request'::text as kind,
      r.buyer_id,
      r.status,
      greatest(coalesce(r.requested_qty, 1), 1) as quantity,
      r.queue_position,
      r.created_at,
      r.live_id as source_live_id
    from catalog ci
    join public.live_reservation_requests r
      on r.seller_id = v_seller
     and r.status in ('pending', 'accepted')
     and coalesce(lower(r.notes), '') not like '%bag_removed%'
     and coalesce(lower(r.notes), '') not like '%bag_cancelled%'
    join public.live_items li_src on li_src.id = r.live_item_id
    where public.batata_live_items_lineage_match(ci, li_src)
  ),
  matched_orders as (
    select
      ci.id as catalog_item_id,
      o.id::text as entry_id,
      'order'::text as kind,
      o.buyer_id,
      o.status,
      greatest(coalesce(o.quantity, 1), 1) as quantity,
      null::int as queue_position,
      o.created_at,
      o.live_id as source_live_id
    from catalog ci
    join public.orders o
      on o.seller_id = v_seller
     and lower(trim(coalesce(o.status, ''))) in (
       'reserva_pendente', 'reservado', 'aguarda_confirmacao', 'pendente'
     )
     and lower(trim(coalesce(o.status, ''))) not in (
       'cancelado', 'cancelada', 'cancelled', 'canceled', 'anulado', 'anulada'
     )
    left join public.live_items li_src on li_src.id = o.live_item_id
    where (
      (ci.product_id is not null and o.product_id = ci.product_id)
      or (
        ci.checkout_product_id is not null
        and o.product_id = ci.checkout_product_id
      )
      or (
        li_src.id is not null
        and public.batata_live_items_lineage_match(ci, li_src)
      )
    )
  ),
  all_matched as (
    select * from matched_requests
    union all
    select * from matched_orders
  ),
  with_meta as (
    select
      am.*,
      coalesce(nullif(trim(p.full_name), ''), 'Comprador') as buyer_name,
      nullif(trim(p.photo_url), '') as buyer_photo_url,
      case
        when am.source_live_id is null then 'Marketplace'
        when exists (
          select 1
          from public.lives lv
          where lv.id = am.source_live_id
            and (
              coalesce(lv.mux_vod_playback_id, lv.mux_playback_id, lv.playback_id, '')
                <> ''
              or lower(coalesce(lv.status, '')) in ('ended')
            )
        ) then 'Gravado'
        when am.source_live_id = p_live_id then 'Este directo'
        else 'Direto anterior'
      end as origin_label
    from all_matched am
    left join public.profiles p on p.id = am.buyer_id
  ),
  item_rows as (
    select
      ci.id as catalog_item_id,
      coalesce(nullif(trim(ci.title), ''), 'Artigo') as title,
      coalesce(nullif(trim(ci.ref_code), ''), '') as ref_code,
      nullif(trim(ci.photo_url), '') as photo_url,
      coalesce((stk->>'available_qty')::int, coalesce(ci.quantity, 1)) as current_stock,
      coalesce(agg.reservation_count, 0) as reservation_count,
      coalesce(agg.reserved_units, 0) as reserved_units,
      coalesce(agg.reservations, '[]'::jsonb) as reservations,
      coalesce(agg.origins, '[]'::jsonb) as origins
    from catalog ci
    left join lateral (
      select public.batata_live_item_stock(ci.id) as stk
    ) s on true
    left join lateral (
      select
        count(*)::int as reservation_count,
        coalesce(sum(wm.quantity), 0)::int as reserved_units,
        jsonb_agg(
          jsonb_build_object(
            'kind', wm.kind,
            'id', wm.entry_id,
            'buyer_id', wm.buyer_id,
            'buyer_name', wm.buyer_name,
            'buyer_photo_url', wm.buyer_photo_url,
            'status', wm.status,
            'quantity', wm.quantity,
            'queue_position', wm.queue_position,
            'created_at', wm.created_at,
            'origin', wm.origin_label
          )
          order by wm.created_at asc nulls last
        ) as reservations,
        (
          select coalesce(jsonb_agg(distinct o.origin_label order by o.origin_label), '[]'::jsonb)
          from (select distinct wm2.origin_label from with_meta wm2 where wm2.catalog_item_id = ci.id) o
        ) as origins
      from with_meta wm
      where wm.catalog_item_id = ci.id
    ) agg on true
    where coalesce(agg.reservation_count, 0) > 0
  ),
  summary as (
    select
      count(*)::int as items_with_open,
      coalesce(sum(reservation_count), 0)::int as total_reservations,
      coalesce(sum(reserved_units), 0)::int as total_units
    from item_rows
  )
  select jsonb_build_object(
    'ok', true,
    'summary', jsonb_build_object(
      'items_with_open', coalesce((select items_with_open from summary), 0),
      'total_reservations', coalesce((select total_reservations from summary), 0),
      'total_units', coalesce((select total_units from summary), 0)
    ),
    'items', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'live_item_id', ir.catalog_item_id,
            'title', ir.title,
            'ref_code', ir.ref_code,
            'photo_url', ir.photo_url,
            'current_stock', ir.current_stock,
            'reservation_count', ir.reservation_count,
            'reserved_units', ir.reserved_units,
            'stock_warning', ir.reserved_units >= greatest(ir.current_stock, 1),
            'origins', ir.origins,
            'reservations', ir.reservations
          )
          order by ir.reserved_units desc, ir.title asc
        )
        from item_rows ir
      ),
      '[]'::jsonb
    )
  )
  into v_result;

  return coalesce(v_result, jsonb_build_object('ok', true, 'summary', jsonb_build_object(
    'items_with_open', 0, 'total_reservations', 0, 'total_units', 0
  ), 'items', '[]'::jsonb));
end;
$$;

revoke all on function public.batata_live_start_open_reservations_check(uuid) from public;
grant execute on function public.batata_live_start_open_reservations_check(uuid) to authenticated;
grant execute on function public.batata_live_start_open_reservations_check(uuid) to service_role;
-- ---------------------------------------------------------------------------
-- 4) Preview ref reutilizada — linhagens + L1/L2/L3
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_ref_open_reservations_preview(
  p_seller_id uuid,
  p_ref_code text,
  p_live_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_norm text;
  v_ref text;
  v_draft_item_id uuid;
  v_draft_logical_id uuid;
  v_lineages jsonb;
  v_summary jsonb;
  v_should_show boolean := false;
  v_usage_months int := 12;
begin
  if p_seller_id is null then
    return jsonb_build_object('ok', false, 'error', 'seller_required');
  end if;

  if not (
    auth.uid() = p_seller_id
    or public.batata_staff_has_permission(p_seller_id, 'can_manage_reservations')
    or public.batata_staff_has_permission(p_seller_id, 'can_view_live_dashboard')
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  v_ref := trim(coalesce(p_ref_code, ''));
  if v_ref = '' then
    return jsonb_build_object('ok', false, 'error', 'ref_required');
  end if;
  v_norm := public.batata_normalize_ref(v_ref);

  if p_live_id is not null then
    select li.id, li.logical_item_id
    into v_draft_item_id, v_draft_logical_id
    from public.live_items li
    where li.live_id = p_live_id
      and li.item_kind = 'live_only'
      and public.batata_normalize_ref(li.ref_code) = v_norm
    limit 1;
  end if;

  with hist as (
    select
      li.id,
      coalesce(li.logical_item_id, li.id) as lineage_id,
      li.title,
      li.photo_url,
      li.price,
      li.ref_code,
      li.live_id,
      li.updated_at,
      coalesce(l.ended_at, l.created_at, li.updated_at) as used_at,
      public.batata_live_origin_label(li.live_id) as origin_label,
      row_number() over (
        partition by coalesce(li.logical_item_id, li.id)
        order by coalesce(l.ended_at, l.created_at, li.updated_at) desc nulls last,
                 li.updated_at desc nulls last
      ) as rn
    from public.live_items li
    join public.lives l on l.id = li.live_id
    where li.item_kind = 'live_only'
      and public.batata_normalize_ref(li.ref_code) = v_norm
      and coalesce(l.seller_id, l.vendedor_id) = p_seller_id
      and (p_live_id is null or li.live_id <> p_live_id)
  ),
  lineage_heads as (
    select * from hist where rn = 1
  ),
  lineage_item_ids as (
    select
      h.lineage_id,
      array_agg(h.id) as item_ids
    from hist h
    group by h.lineage_id
  ),
  open_requests as (
    select
      lh.lineage_id,
      r.id::text as entry_id,
      'live_request'::text as kind,
      coalesce(nullif(trim(p.full_name), ''), 'Comprador') as buyer_name,
      r.status,
      greatest(coalesce(r.requested_qty, 1), 1) as quantity,
      r.created_at,
      public.batata_live_origin_label(r.live_id) as origin
    from lineage_heads lh
    join lineage_item_ids lii on lii.lineage_id = lh.lineage_id
    join public.live_reservation_requests r
      on r.live_item_id = any (lii.item_ids)
     and r.seller_id = p_seller_id
     and r.status in ('pending', 'accepted')
     and coalesce(lower(r.notes), '') not like '%bag_removed%'
     and coalesce(lower(r.notes), '') not like '%bag_cancelled%'
    left join public.profiles p on p.id = r.buyer_id
  ),
  open_orders as (
    select
      lh.lineage_id,
      o.id::text as entry_id,
      'order'::text as kind,
      coalesce(nullif(trim(p.full_name), ''), 'Comprador') as buyer_name,
      o.status,
      greatest(coalesce(o.quantity, 1), 1) as quantity,
      o.created_at,
      public.batata_live_origin_label(o.live_id) as origin
    from lineage_heads lh
    join lineage_item_ids lii on lii.lineage_id = lh.lineage_id
    join public.orders o
      on o.live_item_id = any (lii.item_ids)
     and o.seller_id = p_seller_id
     and lower(trim(coalesce(o.status, ''))) in (
       'reserva_pendente', 'reservado', 'aguarda_confirmacao', 'pendente'
     )
     and lower(trim(coalesce(o.status, ''))) not in (
       'cancelado', 'cancelada', 'cancelled', 'canceled', 'anulado', 'anulada'
     )
    left join public.profiles p on p.id = o.buyer_id
  ),
  completed_orders as (
    select
      lh.lineage_id,
      o.id::text as entry_id,
      'order'::text as kind,
      coalesce(nullif(trim(p.full_name), ''), 'Comprador') as buyer_name,
      greatest(coalesce(o.quantity, 1), 1) as quantity,
      o.created_at as completed_at,
      public.batata_live_origin_label(o.live_id) as origin
    from lineage_heads lh
    join lineage_item_ids lii on lii.lineage_id = lh.lineage_id
    join public.orders o
      on o.live_item_id = any (lii.item_ids)
     and o.seller_id = p_seller_id
     and lower(trim(coalesce(o.status, ''))) in ('pago', 'paid')
    left join public.profiles p on p.id = o.buyer_id
  ),
  completed_requests as (
    select
      lh.lineage_id,
      r.id::text as entry_id,
      'live_request'::text as kind,
      coalesce(nullif(trim(p.full_name), ''), 'Comprador') as buyer_name,
      greatest(coalesce(r.requested_qty, 1), 1) as quantity,
      coalesce(r.updated_at, r.created_at) as completed_at,
      public.batata_live_origin_label(r.live_id) as origin
    from lineage_heads lh
    join lineage_item_ids lii on lii.lineage_id = lh.lineage_id
    join public.live_reservation_requests r
      on r.live_item_id = any (lii.item_ids)
     and r.seller_id = p_seller_id
     and r.status = 'converted'
    left join public.profiles p on p.id = r.buyer_id
  ),
  lineage_stats as (
    select
      lh.lineage_id,
      lh.title,
      lh.photo_url,
      lh.price,
      lh.used_at as last_used_at,
      lh.origin_label as last_origin,
      lh.live_id as last_live_id,
      coalesce((select count(*)::int from open_requests o where o.lineage_id = lh.lineage_id), 0)
        + coalesce((select count(*)::int from open_orders oo where oo.lineage_id = lh.lineage_id), 0)
        as open_reservation_count,
      coalesce((select coalesce(sum(o.quantity), 0)::int from open_requests o where o.lineage_id = lh.lineage_id), 0)
        + coalesce((select coalesce(sum(oo.quantity), 0)::int from open_orders oo where oo.lineage_id = lh.lineage_id), 0)
        as open_reserved_units,
      coalesce((select count(*)::int from completed_orders c where c.lineage_id = lh.lineage_id), 0)
        + coalesce((select count(*)::int from completed_requests c where c.lineage_id = lh.lineage_id), 0)
        as completed_purchase_count,
      coalesce((select coalesce(sum(c.quantity), 0)::int from completed_orders c where c.lineage_id = lh.lineage_id), 0)
        + coalesce((select coalesce(sum(c.quantity), 0)::int from completed_requests c where c.lineage_id = lh.lineage_id), 0)
        as completed_units
    from lineage_heads lh
  ),
  lineage_payload as (
    select
      ls.*,
      (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'kind', x.kind,
            'id', x.entry_id,
            'buyer_name', x.buyer_name,
            'status', x.status,
            'quantity', x.quantity,
            'origin', x.origin,
            'created_at', x.created_at
          )
          order by x.created_at asc nulls last
        ), '[]'::jsonb)
        from (
          select * from open_requests o where o.lineage_id = ls.lineage_id
          union all
          select * from open_orders oo where oo.lineage_id = ls.lineage_id
        ) x
      ) as reservations_open,
      (
        select coalesce(jsonb_agg(t order by t.completed_at desc nulls last), '[]'::jsonb)
        from (
          select
            c.kind, c.entry_id as id, c.buyer_name, c.quantity, c.origin, c.completed_at
          from completed_orders c where c.lineage_id = ls.lineage_id
          union all
          select
            c.kind, c.entry_id as id, c.buyer_name, c.quantity, c.origin, c.completed_at
          from completed_requests c where c.lineage_id = ls.lineage_id
          order by completed_at desc nulls last
          limit 10
        ) t
      ) as purchases_completed
    from lineage_stats ls
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'logical_item_id', lp.lineage_id,
      'display_title', coalesce(nullif(trim(lp.title), ''), v_ref),
      'display_photo_url', lp.photo_url,
      'display_price', lp.price,
      'last_used_at', lp.last_used_at,
      'last_origin', lp.last_origin,
      'last_live_id', lp.last_live_id,
      'open_reservation_count', lp.open_reservation_count,
      'open_reserved_units', lp.open_reserved_units,
      'completed_purchase_count', lp.completed_purchase_count,
      'completed_units', lp.completed_units,
      'reservations_open', lp.reservations_open,
      'purchases_completed', lp.purchases_completed
    )
    order by
      lp.open_reservation_count desc,
      lp.completed_purchase_count desc,
      lp.last_used_at desc nulls last
  ), '[]'::jsonb)
  into v_lineages
  from lineage_payload lp;

  select jsonb_build_object(
    'lineage_count', jsonb_array_length(v_lineages),
    'open_reservation_count', coalesce((
      select sum((e->>'open_reservation_count')::int)::int from jsonb_array_elements(v_lineages) e
    ), 0),
    'open_reserved_units', coalesce((
      select sum((e->>'open_reserved_units')::int)::int from jsonb_array_elements(v_lineages) e
    ), 0),
    'completed_purchase_count', coalesce((
      select sum((e->>'completed_purchase_count')::int)::int from jsonb_array_elements(v_lineages) e
    ), 0),
    'completed_units', coalesce((
      select sum((e->>'completed_units')::int)::int from jsonb_array_elements(v_lineages) e
    ), 0)
  )
  into v_summary;

  v_should_show := (
    coalesce((v_summary->>'open_reservation_count')::int, 0) > 0
    or coalesce((v_summary->>'completed_purchase_count')::int, 0) > 0
    or exists (
      select 1
      from jsonb_array_elements(v_lineages) e
      where (e->>'last_used_at')::timestamptz >= (now() - make_interval(months => v_usage_months))
        and coalesce((e->>'open_reservation_count')::int, 0) = 0
        and coalesce((e->>'completed_purchase_count')::int, 0) = 0
    )
  );

  return jsonb_build_object(
    'ok', true,
    'ref_code', v_ref,
    'ref_normalized', v_norm,
    'usage_window_months', v_usage_months,
    'has_relevant_history', jsonb_array_length(v_lineages) > 0,
    'should_show_sheet', v_should_show,
    'summary', v_summary,
    'lineages', v_lineages,
    'draft', jsonb_build_object(
      'live_item_id', v_draft_item_id,
      'logical_item_id', v_draft_logical_id,
      'needs_lineage_decision', v_draft_logical_id is null and v_should_show
    )
  );
end;
$$;

revoke all on function public.batata_live_ref_open_reservations_preview(uuid, text, uuid) from public;
grant execute on function public.batata_live_ref_open_reservations_preview(uuid, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5) Upsert live_only — lineage + jsonb
-- ---------------------------------------------------------------------------
drop function if exists public.batata_upsert_live_only_item(
  uuid, text, text, numeric, integer, text, text, text, uuid
);

create or replace function public.batata_upsert_live_only_item(
  p_seller_id uuid,
  p_ref_code text,
  p_title text default null,
  p_price numeric default null,
  p_quantity integer default 1,
  p_clothing_size text default null,
  p_gender text default null,
  p_photo_url text default null,
  p_live_id uuid default null,
  p_lineage_mode text default 'new',
  p_logical_item_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_live_id uuid;
  v_item_id uuid;
  v_existing_logical uuid;
  v_ref text;
  v_norm text;
  v_mode text;
  v_new_logical uuid;
  v_resolved_price numeric;
begin
  if p_seller_id is null or auth.uid() is distinct from p_seller_id then
    raise exception 'not_allowed';
  end if;

  v_ref := trim(coalesce(p_ref_code, ''));
  if v_ref = '' then
    raise exception 'ref_required';
  end if;
  v_norm := public.batata_normalize_ref(v_ref);
  v_live_id := coalesce(p_live_id, public.batata_ensure_draft_live(p_seller_id));
  v_mode := lower(trim(coalesce(p_lineage_mode, 'new')));

  if p_price is not null and p_price > 0 then
    v_resolved_price := p_price;
  else
    select li.price into v_resolved_price
    from public.live_items li
    join public.lives l on l.id = li.live_id
    where coalesce(l.seller_id, l.vendedor_id) = p_seller_id
      and li.item_kind = 'live_only'
      and public.batata_normalize_ref(li.ref_code) = v_norm
      and li.price is not null
      and li.price > 0
      and li.live_id is distinct from v_live_id
    order by li.updated_at desc nulls last, li.created_at desc
    limit 1;

    if (v_resolved_price is null or v_resolved_price <= 0)
       and p_logical_item_id is not null then
      select li.price into v_resolved_price
      from public.live_items li
      where li.logical_item_id = p_logical_item_id
        and li.price is not null
        and li.price > 0
      order by li.updated_at desc nulls last
      limit 1;
    end if;
  end if;

  select li.id, li.logical_item_id
  into v_item_id, v_existing_logical
  from public.live_items li
  where li.live_id = v_live_id
    and li.item_kind = 'live_only'
    and public.batata_normalize_ref(li.ref_code) = v_norm
  limit 1;

  if v_item_id is not null then
    if v_existing_logical is not null then
      update public.live_items
      set
        ref_code = v_ref,
        title = coalesce(nullif(trim(p_title), ''), title),
        price = coalesce(
          nullif(p_price, 0),
          case when coalesce(price, 0) <= 0 then v_resolved_price else price end
        ),
        quantity = greatest(coalesce(p_quantity, quantity, 1), 1),
        clothing_size = coalesce(nullif(trim(p_clothing_size), ''), clothing_size),
        gender = coalesce(nullif(trim(p_gender), ''), gender),
        photo_url = coalesce(nullif(trim(p_photo_url), ''), photo_url),
        updated_at = now()
      where id = v_item_id;

      return jsonb_build_object(
        'ok', true,
        'live_item_id', v_item_id,
        'logical_item_id', v_existing_logical,
        'lineage_mode', 'keep'
      );
    end if;

    if v_mode = 'inherit' then
      if p_logical_item_id is null then
        raise exception 'logical_item_id_required';
      end if;
      if not exists (
        select 1
        from public.live_items li
        join public.lives l on l.id = li.live_id
        where li.logical_item_id = p_logical_item_id
          and coalesce(l.seller_id, l.vendedor_id) = p_seller_id
          and li.item_kind = 'live_only'
      ) then
        raise exception 'lineage_not_found';
      end if;
      v_new_logical := p_logical_item_id;
    elsif v_mode = 'new' then
      v_new_logical := gen_random_uuid();
    else
      raise exception 'lineage_mode_invalid';
    end if;

    update public.live_items
    set
      ref_code = v_ref,
      title = coalesce(nullif(trim(p_title), ''), title),
      price = coalesce(
        nullif(p_price, 0),
        case when coalesce(price, 0) <= 0 then v_resolved_price else price end
      ),
      quantity = greatest(coalesce(p_quantity, quantity, 1), 1),
      clothing_size = coalesce(nullif(trim(p_clothing_size), ''), clothing_size),
      gender = coalesce(nullif(trim(p_gender), ''), gender),
      photo_url = coalesce(nullif(trim(p_photo_url), ''), photo_url),
      logical_item_id = v_new_logical,
      updated_at = now()
    where id = v_item_id;

    return jsonb_build_object(
      'ok', true,
      'live_item_id', v_item_id,
      'logical_item_id', v_new_logical,
      'lineage_mode', v_mode
    );
  end if;

  if v_mode = 'inherit' then
    if p_logical_item_id is null then
      raise exception 'logical_item_id_required';
    end if;
    if not exists (
      select 1
      from public.live_items li
      join public.lives l on l.id = li.live_id
      where li.logical_item_id = p_logical_item_id
        and coalesce(l.seller_id, l.vendedor_id) = p_seller_id
        and li.item_kind = 'live_only'
    ) then
      raise exception 'lineage_not_found';
    end if;
    v_new_logical := p_logical_item_id;
  else
    v_new_logical := gen_random_uuid();
    v_mode := 'new';
  end if;

  insert into public.live_items (
    live_id, item_kind, product_id, ref_code, title, price, photo_url,
    quantity, clothing_size, gender, is_active, status, logical_item_id, updated_at
  )
  values (
    v_live_id,
    'live_only',
    null,
    v_ref,
    coalesce(nullif(trim(p_title), ''), v_ref),
    v_resolved_price,
    nullif(trim(p_photo_url), ''),
    greatest(coalesce(p_quantity, 1), 1),
    nullif(trim(p_clothing_size), ''),
    nullif(trim(p_gender), ''),
    false,
    'available',
    v_new_logical,
    now()
  )
  returning id into v_item_id;

  return jsonb_build_object(
    'ok', true,
    'live_item_id', v_item_id,
    'logical_item_id', v_new_logical,
    'lineage_mode', v_mode
  );
end;
$$;

revoke all on function public.batata_upsert_live_only_item(
  uuid, text, text, numeric, integer, text, text, text, uuid, text, uuid
) from public;
grant execute on function public.batata_upsert_live_only_item(
  uuid, text, text, numeric, integer, text, text, text, uuid, text, uuid
) to authenticated;

-- Colunas usadas pelo shadow live (se ainda não existirem).
alter table public.products add column if not exists quantity integer default 1;
alter table public.products add column if not exists is_sold boolean default false;

-- Shadow Stripe: sincronizar preço quando já existe checkout_product_id.
create or replace function public.batata_ensure_checkout_product(p_live_item_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_live public.lives%rowtype;
  v_seller uuid;
  v_pid uuid;
  v_img_json jsonb;
  v_img_text text[];
  v_image_urls_udt text;
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    raise exception 'live_item_not_found';
  end if;

  if v_li.checkout_product_id is not null then
    update public.products
    set
      price = case
        when v_li.price is not null and v_li.price > 0 then v_li.price
        else price
      end,
      title = coalesce(nullif(trim(v_li.title), ''), title),
      quantity = greatest(coalesce(v_li.quantity, 1), 1)
    where id = v_li.checkout_product_id;
    return v_li.checkout_product_id;
  end if;

  if v_li.item_kind = 'marketplace_product' and v_li.product_id is not null then
    return v_li.product_id;
  end if;

  select * into v_live from public.lives where id = v_li.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);
  if v_seller is null then
    raise exception 'seller_missing';
  end if;

  v_img_json := case
    when v_li.photo_url is not null and trim(v_li.photo_url) <> ''
    then jsonb_build_array(trim(v_li.photo_url))
    else '[]'::jsonb
  end;
  v_img_text := case
    when v_li.photo_url is not null and trim(v_li.photo_url) <> ''
    then array[trim(v_li.photo_url)]
    else array[]::text[]
  end;

  select c.udt_name
  into v_image_urls_udt
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'products'
    and c.column_name = 'image_urls'
  limit 1;

  if v_image_urls_udt = '_text' then
    insert into public.products (
      seller_id, title, price, image_urls, ref_code,
      list_on_marketplace, available_for_live, quantity, is_sold
    )
    values (
      v_seller,
      coalesce(nullif(trim(v_li.title), ''), 'Artigo live'),
      coalesce(v_li.price, 0),
      v_img_text,
      coalesce(nullif(trim(v_li.ref_code), ''), 'LIVE-' || left(v_li.id::text, 8)),
      false,
      false,
      greatest(coalesce(v_li.quantity, 1), 1),
      false
    )
    returning id into v_pid;
  else
    insert into public.products (
      seller_id, title, price, image_urls, ref_code,
      list_on_marketplace, available_for_live, quantity, is_sold
    )
    values (
      v_seller,
      coalesce(nullif(trim(v_li.title), ''), 'Artigo live'),
      coalesce(v_li.price, 0),
      v_img_json,
      coalesce(nullif(trim(v_li.ref_code), ''), 'LIVE-' || left(v_li.id::text, 8)),
      false,
      false,
      greatest(coalesce(v_li.quantity, 1), 1),
      false
    )
    returning id into v_pid;
  end if;

  update public.live_items
  set checkout_product_id = v_pid, updated_at = now()
  where id = v_li.id;

  return v_pid;
end;
$$;

revoke all on function public.batata_ensure_checkout_product(uuid) from public;
grant execute on function public.batata_ensure_checkout_product(uuid) to authenticated;

create or replace function public.batata_resolve_live_checkout_product(p_live_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_p public.products%rowtype;
  v_pid uuid;
  v_unit_price numeric;
  v_image_urls_json jsonb;
  v_image_urls_udt text;
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  if v_li.item_kind = 'marketplace_product' and v_li.product_id is not null then
    v_pid := v_li.product_id;
  else
    v_pid := public.batata_ensure_checkout_product(p_live_item_id);
    select * into v_li from public.live_items where id = p_live_item_id;
  end if;

  select * into v_p from public.products where id = v_pid;
  if v_p.id is null then
    return jsonb_build_object('ok', false, 'error', 'product_not_found');
  end if;

  if coalesce(v_li.price, 0) > 0 then
    v_unit_price := v_li.price;
  elsif coalesce(v_p.price, 0) > 0 then
    v_unit_price := v_p.price;
  else
    v_unit_price := null;
  end if;

  select c.udt_name
  into v_image_urls_udt
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'products'
    and c.column_name = 'image_urls'
  limit 1;

  if v_image_urls_udt = '_text' then
    execute
      'select to_jsonb(coalesce(image_urls, array[]::text[]))
       from public.products where id = $1'
    into v_image_urls_json
    using v_pid;
  else
    v_image_urls_json := coalesce(v_p.image_urls, '[]'::jsonb);
  end if;

  return jsonb_build_object(
    'ok', true,
    'live_item_id', v_li.id,
    'product_id', v_p.id,
    'seller_id', v_p.seller_id,
    'price', v_unit_price,
    'live_item_price', v_li.price,
    'product_price', v_p.price,
    'title', coalesce(nullif(trim(v_li.title), ''), v_p.title),
    'ref_code', coalesce(v_li.ref_code, v_p.ref_code),
    'image_urls', v_image_urls_json,
    'checkout_product_id', v_li.checkout_product_id,
    'item_kind', v_li.item_kind
  );
end;
$$;

revoke all on function public.batata_resolve_live_checkout_product(uuid) from public;
grant execute on function public.batata_resolve_live_checkout_product(uuid) to authenticated;

drop policy if exists "products_select_live_checkout_shadow" on public.products;
create policy "products_select_live_checkout_shadow"
  on public.products
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.live_items li
      inner join public.lives l on l.id = li.live_id
      where (
        li.checkout_product_id = products.id
        or li.product_id = products.id
      )
      and (
        l.status in ('live', 'ended')
        or l.is_active = true
      )
    )
  );

-- Gestão de referências (históricos, encerrar, juntar, Z5 upsert): correr também
-- supabase/sql/ref_histories_batata.sql no SQL Editor (staging/prod).

notify pgrst, 'reload schema';
