-- =============================================================================
-- BATATA 2026-09-13 — restaurar chat «reservou» no pending + stock FB + qty live_only
--
-- Causa (hardening): batata_live_system_message ficou seller/staff-only → Hub/app
--   deixaram de publicar «🛍️ X reservou …» no momento da reserva (arquitectura
--   decidida: mensagem no pending, sem precisar de aceitar).
-- FB/OCR nunca chamava o RPC do cliente → também sem mensagem.
-- pending_bag_qty só contava fleaber_live → cards «Reservas» ignoravam Facebook.
-- live_only sem product_id: seller bloqueado a aumentar quantity.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) system_message: allowlist operacional + participantes (buyer com reserva)
--    FOMO / anúncios de compra continuam bloqueados.
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_system_message(
  p_live_id uuid,
  p_body text,
  p_sender_label text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_seller uuid;
  v_body text := trim(coalesce(p_body, ''));
  v_norm text;
  v_stem text;
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
  v_allowed boolean := false;
  v_is_ops boolean := false;
  v_participant boolean := false;
begin
  if p_live_id is null or v_body = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_payload');
  end if;
  if char_length(v_body) > 400 then
    return jsonb_build_object('ok', false, 'error', 'body_too_long');
  end if;
  if v_uid is null and v_role is distinct from 'service_role' then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  v_norm := lower(normalize(v_body, NFKC));
  v_norm := regexp_replace(v_norm, E'[\u200b\u200c\u200d\ufeff\u2800-\u28ff\u00ad\u2060]', '', 'g');
  v_norm := regexp_replace(v_norm, '[0-9]', '', 'g');
  v_norm := translate(
    v_norm,
    E'áàâãäéèêëíìîïóòôõöúùûüçоОаАсСſօოäöüßѕ'
      || E'ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ',
    E'aaaaaeeeeiiiiooooouuuucoaassoaoousss'
      || E'abcdefghijklmnopqrstuvwxyz'
  );
  v_norm := regexp_replace(v_norm, '[-_./]+', ' ', 'g');
  v_stem := regexp_replace(v_norm, '[^a-z\s]', '', 'g');
  v_stem := regexp_replace(v_stem, '\s+', ' ', 'g');
  v_stem := trim(v_stem);

  if v_stem ~ 'bem ?vindos'
     or v_stem ~ 'directo esta a comecar'
     or v_stem ~ 'o directo esta a comecar'
     or v_stem ~ 'recusaste o pedido'
     or v_stem ~ 'pedido de .+ aguarda'
     or v_stem ~ 'reservou( para o saco| )'
     or v_stem ~ 'reserva cancelada'
     or v_stem = 'sistema'
  then
    v_allowed := true;
  end if;

  if not v_allowed then
    return jsonb_build_object('ok', false, 'error', 'purchase_announce_via_broadcast_only');
  end if;

  if v_body like '%🔥%' or v_body like '%🛒%' or v_body like '%💨%'
     or v_body like '%⚡%' or v_body like '%🧨%' then
    return jsonb_build_object('ok', false, 'error', 'purchase_announce_via_broadcast_only');
  end if;

  select coalesce(seller_id, vendedor_id) into v_seller from public.lives where id = p_live_id;
  if v_seller is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  if v_role is distinct from 'service_role' then
    v_is_ops := v_uid = v_seller
      or public.batata_staff_has_permission(v_seller, 'can_manage_chat');

    if not v_is_ops then
      -- Comprador autenticado: só mensagens operacionais allowlisted e só se
      -- já tem (ou teve nesta live) reserva — cobre «reservou» pós-insert e cancel.
      select exists(
        select 1
        from public.live_reservation_requests r
        where r.live_id = p_live_id
          and r.buyer_id = v_uid
          and r.status in ('pending', 'accepted', 'rejected', 'converted')
      ) into v_participant;
      if not coalesce(v_participant, false) then
        return jsonb_build_object('ok', false, 'error', 'not_allowed');
      end if;
    end if;

    insert into public.batata_rpc_rate_limits (uid, rpc, window_start, hits)
    values (v_uid, 'batata_live_system_message', v_window, 1)
    on conflict (uid, rpc, window_start) do update
    set hits = public.batata_rpc_rate_limits.hits + 1
    returning hits into v_hits;
    if v_hits > 60 then
      return jsonb_build_object('ok', false, 'error', 'rate_limited');
    end if;
  end if;

  -- Dedup: cliente + trigger podem coincidir
  if exists (
    select 1
    from public.live_messages m
    where m.live_id = p_live_id
      and m.body = v_body
      and m.created_at > now() - interval '45 seconds'
  ) then
    return jsonb_build_object('ok', true, 'duplicate', true);
  end if;

  insert into public.live_messages (live_id, user_id, kind, body, sender_label)
  values (
    p_live_id,
    coalesce(v_uid, v_seller),
    'system',
    v_body,
    coalesce(nullif(trim(p_sender_label), ''), 'Sistema')
  );
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.batata_live_system_message(uuid, text, text) from public, anon;
grant execute on function public.batata_live_system_message(uuid, text, text)
  to authenticated, service_role;

comment on function public.batata_live_system_message(uuid, text, text) is
  'Mensagens sistema allowlisted. Seller/staff livres (ops). Buyer só se participante da live. Sem FOMO.';

-- ---------------------------------------------------------------------------
-- 2) Anúncio server-side no INSERT pending (Hub + Fleaber + Facebook/OCR)
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_announce_pending_reservation()
returns trigger
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
  v_channel text := 'fleaber';
  v_user uuid;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;
  if lower(trim(coalesce(new.status, ''))) is distinct from 'pending' then
    return new;
  end if;
  if lower(trim(coalesce(new.ingest_status, ''))) = 'rejected' then
    return new;
  end if;
  if new.live_id is null or new.live_item_id is null then
    return new;
  end if;

  if new.buyer_id is not null then
    select coalesce(nullif(trim(full_name), ''), nullif(trim(handle), ''), 'Comprador')
    into v_name
    from public.profiles
    where id = new.buyer_id;
  end if;
  if v_name is null or trim(v_name) = '' then
    v_name := coalesce(nullif(trim(new.external_display_name), ''), 'Comprador');
  end if;

  select coalesce(nullif(trim(ref_code), ''), ''),
         coalesce(nullif(trim(title), ''), '')
  into v_ref, v_title
  from public.live_items
  where id = new.live_item_id
  limit 1;

  if v_title <> '' then
    v_label := v_title;
  elsif v_ref <> '' then
    v_label := 'Ref ' || v_ref;
  else
    v_label := 'artigo';
  end if;

  v_body := '🛍️ ' || v_name || ' reservou ' || v_label;

  if lower(trim(coalesce(new.source, ''))) = 'facebook_manual' then
    v_channel := 'facebook';
  elsif lower(trim(coalesce(new.source, ''))) = 'helper_manual' then
    v_channel := 'fleaber';
  else
    v_channel := 'fleaber';
  end if;

  v_user := coalesce(new.buyer_id, new.seller_id);

  if exists (
    select 1
    from public.live_messages m
    where m.live_id = new.live_id
      and m.body = v_body
      and m.created_at > now() - interval '45 seconds'
  ) then
    return new;
  end if;

  begin
    insert into public.live_messages (
      live_id, user_id, kind, body, sender_label, channel
    ) values (
      new.live_id,
      v_user,
      'system',
      v_body,
      'Sistema',
      v_channel
    );
  exception
    when others then
      -- Nunca falhar o insert da reserva por causa do chat
      null;
  end;

  return new;
end;
$$;

drop trigger if exists batata_live_announce_pending_reservation_tg
  on public.live_reservation_requests;
create trigger batata_live_announce_pending_reservation_tg
  after insert on public.live_reservation_requests
  for each row
  execute function public.batata_live_announce_pending_reservation();

comment on function public.batata_live_announce_pending_reservation() is
  'No pending (Fleaber/Hub/FB): publica «🛍️ X reservou …» no chat do directo sem aceitar.';

-- ---------------------------------------------------------------------------
-- 3) Qty live_only: seller/staff podem aumentar; outsider bloqueado
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_items_guard_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_live_owner uuid;
  v_product_seller uuid;
  v_has_any_res boolean := false;
  v_reserved int := 0;
  v_prod_qty int;
  v_is_staff boolean := false;
  v_can_mark boolean := false;
  v_mark_sold_internal boolean := false;
  v_kind text;
begin
  v_mark_sold_internal :=
    coalesce(current_setting('batata.mark_sold_internal', true), '') = '1';

  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if lower(trim(coalesce(NEW.status, ''))) = 'sold'
     and (
       TG_OP = 'INSERT'
       or lower(trim(coalesce(OLD.status, ''))) is distinct from 'sold'
     )
     and not v_mark_sold_internal
     and v_role is distinct from 'service_role' then
    raise exception 'live_item_status_sold_rpc_only' using errcode = '42501';
  end if;

  if NEW.live_id is not null then
    select coalesce(l.seller_id, l.vendedor_id) into v_live_owner
    from public.lives l where l.id = NEW.live_id limit 1;
  end if;

  if v_live_owner is not null then
    v_is_staff := v_live_owner is distinct from v_uid
      and public.batata_staff_has_permission(v_live_owner, 'can_manage_reservations');
    v_can_mark := v_live_owner = v_uid
      or public.batata_staff_has_permission(v_live_owner, 'can_mark_items_sold');
  end if;

  if v_live_owner is not null and v_live_owner is distinct from v_uid
     and not public.batata_is_admin() and not v_is_staff then
    raise exception 'live_item_not_authorized' using errcode = '42501';
  end if;

  v_kind := lower(trim(coalesce(NEW.item_kind, '')));

  -- Seller/owner ou staff com mark: pode aumentar qty (incl. live_only sem catálogo).
  if TG_OP = 'UPDATE'
     and coalesce(NEW.quantity, 0) > coalesce(OLD.quantity, 0)
     and v_role is distinct from 'service_role' then
    if not coalesce(v_can_mark, false) then
      raise exception 'live_item_qty_increase_not_allowed' using errcode = '42501';
    end if;
  end if;

  if NEW.checkout_product_id is not null and v_live_owner is not null then
    select p.seller_id into v_product_seller
    from public.products p where p.id = NEW.checkout_product_id limit 1;
    if v_product_seller is not null
       and v_product_seller is distinct from v_live_owner then
      raise exception 'live_item_checkout_product_seller_mismatch'
        using errcode = '42501';
    end if;
  end if;

  if TG_OP = 'UPDATE' and NEW.live_id is distinct from OLD.live_id then
    select exists(
      select 1 from public.live_reservation_requests r
      where r.live_item_id = NEW.id
    ) into v_has_any_res;
    if v_has_any_res then
      raise exception 'live_item_live_id_immutable' using errcode = '42501';
    end if;
  end if;

  if NEW.product_id is not null and v_live_owner is not null then
    select p.seller_id, p.quantity into v_product_seller, v_prod_qty
    from public.products p where p.id = NEW.product_id limit 1;
    if v_product_seller is not null and v_product_seller is distinct from v_live_owner then
      raise exception 'live_item_product_seller_mismatch' using errcode = '42501';
    end if;
    if v_prod_qty is not null and coalesce(NEW.quantity, 0) > v_prod_qty then
      raise exception 'live_item_qty_exceeds_product' using errcode = '42501';
    end if;
  end if;

  if TG_OP = 'UPDATE' and NEW.id is not null then
    select coalesce(sum(r.requested_qty), 0)::int into v_reserved
    from public.live_reservation_requests r
    where r.live_item_id = NEW.id
      and r.status in ('accepted', 'converted');
    if coalesce(NEW.quantity, 0) < v_reserved then
      raise exception 'live_item_qty_below_reservations' using errcode = '42501';
    end if;
  end if;

  return NEW;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- 4) pending_bag_qty: incluir facebook_manual + helper_manual (cards «Reservas»)
--    available_qty: mantém RT-E-P2-01 (pending informativo, não consome).
-- ---------------------------------------------------------------------------
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
  v_live_only boolean := false;
  v_uid uuid := auth.uid();
  v_staff boolean := false;
  v_lineage uuid;
  v_hub boolean := false;
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  select * into v_live from public.lives where id = v_li.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);
  v_lineage := coalesce(v_li.logical_item_id, v_li.id);

  if v_uid is not null and v_seller is not null then
    v_staff := public.batata_staff_has_permission(v_seller, 'can_manage_chat')
      or v_uid = v_seller;
  end if;

  select coalesce(p.hub_published, false) into v_hub
  from public.profiles p where p.id = v_seller;

  if not coalesce(v_staff, false) then
    if not coalesce(v_hub, false) then
      return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
    end if;
    if not public.batata_live_is_broadcasting(v_li.live_id)
       or lower(trim(coalesce(v_li.status, ''))) in (
         'paused', 'inactive', 'sold', 'reserved_full'
       ) then
      return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
    end if;
    if lower(trim(coalesce(v_li.item_kind, ''))) = 'live_only'
       and coalesce(v_li.quantity, 0) <= 0 then
      return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
    end if;
  end if;

  v_live_only := lower(trim(coalesce(v_li.item_kind, ''))) = 'live_only';
  v_total := public.batata_live_item_total_qty(v_li.id);
  v_product_id := coalesce(v_li.product_id, v_li.checkout_product_id);

  if v_product_id is not null then
    select coalesce(sum(o.quantity), 0)::int into v_blocked_orders
    from public.orders o
    where o.product_id = v_product_id
      and coalesce(o.status, '') not in ('cancelado', 'cancelled', 'rejected', 'expired')
      and lower(trim(coalesce(o.status, ''))) in (
        'reservado', 'aguarda_confirmacao', 'pendente',
        'pedido_devolucao', 'em_devolucao'
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

  if v_live_only and v_lineage is not null then
    select coalesce(v_blocked_cross_res, 0) + coalesce(sum(r.requested_qty), 0)::int
    into v_blocked_cross_res
    from public.live_reservation_requests r
    join public.live_items li2 on li2.id = r.live_item_id
    where r.status in ('pending', 'accepted')
      and li2.id <> v_li.id
      and coalesce(li2.logical_item_id, li2.id) = v_lineage;
  end if;

  v_blocked := v_blocked_orders + v_blocked_cross_res;

  select coalesce(sum(r.requested_qty), 0)::int into v_reserved_accepted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'accepted'
    and not exists (
      select 1 from public.orders o
      where o.buyer_id = r.buyer_id
        and (
          public.batata_order_status_is_sold_fulfilled(o.status)
          or coalesce(o.stock_units_applied, 0) > 0
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

  -- Hub + Fleaber + Facebook/PS + helper: todos contam em «Reservas» no card
  select coalesce(sum(r.requested_qty), 0)::int into v_pending_bag
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'pending'
    and r.source in ('fleaber_live', 'facebook_manual', 'helper_manual')
    and not exists (
      select 1 from public.orders o
      where o.buyer_id = r.buyer_id
        and o.live_item_id = v_li.id
        and (
          public.batata_order_status_is_sold_fulfilled(o.status)
          or coalesce(o.stock_units_applied, 0) > 0
        )
    );

  select coalesce(sum(r.requested_qty), 0)::int into v_sold_converted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id and r.status = 'converted';

  select coalesce(sum(o.quantity), 0)::int into v_sold_orders
  from public.orders o
  where (
      public.batata_order_status_is_sold_fulfilled(o.status)
      or coalesce(o.stock_units_applied, 0) > 0
    )
    and (
      o.live_item_id = v_li.id
      or (
        o.live_id = v_li.live_id
        and v_product_id is not null
        and o.product_id = v_product_id
      )
    );

  v_sold_converted := greatest(v_sold_converted, v_sold_orders);
  -- RT-E-P2-01: pending não consome available (informativo via pending_bag_qty)
  v_available := v_total - v_blocked - v_reserved_accepted;
  if v_live_only or v_product_id is null then
    v_available := v_available - v_sold_converted;
  elsif v_sold_converted >= greatest(v_total, 1) then
    v_available := 0;
  end if;
  if v_available < 0 then v_available := 0; end if;

  if v_li.product_id is not null then
    select coalesce(nullif(v_li.price, 0), p.price) into v_unit_price
    from public.products p where p.id = v_li.product_id;
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

grant execute on function public.batata_live_item_stock(uuid) to anon, authenticated, service_role;

notify pgrst, 'reload schema';
