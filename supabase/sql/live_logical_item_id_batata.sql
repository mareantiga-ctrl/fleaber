-- Fleaber BATATA V1.5: logical_item_id — linhagens por ref live_only.
-- Executar no SQL Editor (ou incluído em live_ops_hotfix_batata.sql).
-- Depende de: live_items_inventory_batata.sql, live_start_open_reservations_batata.sql

-- ---------------------------------------------------------------------------
-- 1) Coluna + índices + backfill (1 linhagem = 1 live_item histórico)
-- ---------------------------------------------------------------------------
alter table public.live_items
  add column if not exists logical_item_id uuid;

create index if not exists live_items_logical_item_id_idx
  on public.live_items (logical_item_id)
  where logical_item_id is not null;

update public.live_items
set logical_item_id = id
where item_kind = 'live_only'
  and logical_item_id is null;

-- ---------------------------------------------------------------------------
-- 2) Helper — origem legível de uma live
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 3) Helper — match catálogo ↔ item histórico (M1–M4)
-- ---------------------------------------------------------------------------
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
      coalesce(o.updated_at, o.created_at) as completed_at,
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
        price = coalesce(p_price, price),
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
      price = coalesce(p_price, price),
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
    p_price,
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

notify pgrst, 'reload schema';
