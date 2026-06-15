-- Fleaber BATATA — Gestão de referências (históricos reutilizados).
-- Correr no SQL Editor APÓS live_ops_hotfix_batata.sql (ou inventory equivalente).
-- logical_item_id = id do histórico (ref_histories.id).

-- ---------------------------------------------------------------------------
-- 1) Tabelas
-- ---------------------------------------------------------------------------
create table if not exists public.ref_histories (
  id uuid primary key,
  seller_id uuid not null,
  ref_code_normalized text not null,
  ref_code_display text,
  display_title text,
  display_photo_url text,
  status text not null default 'active'
    check (status in ('active', 'closed', 'merged')),
  merged_into_id uuid references public.ref_histories (id) on delete set null,
  closed_at timestamptz,
  closed_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ref_histories_seller_ref_idx
  on public.ref_histories (seller_id, ref_code_normalized);

create index if not exists ref_histories_seller_status_idx
  on public.ref_histories (seller_id, status);

create table if not exists public.ref_history_audit_log (
  id uuid primary key default extensions.gen_random_uuid(),
  history_id uuid references public.ref_histories (id) on delete set null,
  seller_id uuid not null,
  action text not null,
  reason text,
  payload jsonb not null default '{}'::jsonb,
  actor_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists ref_history_audit_seller_idx
  on public.ref_history_audit_log (seller_id, created_at desc);

create table if not exists public.ref_history_merges (
  id uuid primary key default extensions.gen_random_uuid(),
  seller_id uuid not null,
  target_history_id uuid not null references public.ref_histories (id),
  source_history_id uuid not null references public.ref_histories (id),
  merged_by uuid,
  merged_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb
);

alter table public.ref_histories enable row level security;
alter table public.ref_history_audit_log enable row level security;
alter table public.ref_history_merges enable row level security;

drop policy if exists "ref_histories_select_own" on public.ref_histories;
create policy "ref_histories_select_own"
  on public.ref_histories for select to authenticated
  using (
    seller_id = auth.uid()
    or public.batata_staff_has_permission(seller_id, 'can_view_live_dashboard')
    or public.batata_staff_has_permission(seller_id, 'can_manage_reservations')
  );

drop policy if exists "ref_history_audit_select_own" on public.ref_history_audit_log;
create policy "ref_history_audit_select_own"
  on public.ref_history_audit_log for select to authenticated
  using (
    seller_id = auth.uid()
    or public.batata_staff_has_permission(seller_id, 'can_view_live_dashboard')
  );

drop policy if exists "ref_history_merges_select_own" on public.ref_history_merges;
create policy "ref_history_merges_select_own"
  on public.ref_history_merges for select to authenticated
  using (
    seller_id = auth.uid()
    or public.batata_staff_has_permission(seller_id, 'can_view_live_dashboard')
  );

-- Backfill a partir de live_items existentes.
insert into public.ref_histories (
  id, seller_id, ref_code_normalized, ref_code_display,
  display_title, display_photo_url, status
)
select distinct on (coalesce(li.logical_item_id, li.id))
  coalesce(li.logical_item_id, li.id),
  coalesce(l.seller_id, l.vendedor_id),
  public.batata_normalize_ref(li.ref_code),
  li.ref_code,
  li.title,
  li.photo_url,
  'active'
from public.live_items li
join public.lives l on l.id = li.live_id
where li.item_kind = 'live_only'
  and coalesce(li.logical_item_id, li.id) is not null
  and coalesce(l.seller_id, l.vendedor_id) is not null
order by coalesce(li.logical_item_id, li.id), li.updated_at desc nulls last
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 2) Helpers
-- ---------------------------------------------------------------------------
create or replace function public.batata_ref_history_item_ids(p_history_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(li.id), array[]::uuid[])
  from public.live_items li
  where coalesce(li.logical_item_id, li.id) = p_history_id;
$$;

create or replace function public.batata_ref_history_audit(
  p_history_id uuid,
  p_seller_id uuid,
  p_action text,
  p_reason text default null,
  p_payload jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.ref_history_audit_log (
    history_id, seller_id, action, reason, payload, actor_id
  )
  values (
    p_history_id,
    p_seller_id,
    trim(p_action),
    nullif(trim(p_reason), ''),
    coalesce(p_payload, '{}'::jsonb),
    auth.uid()
  );
end;
$$;

create or replace function public.batata_ensure_ref_history(
  p_seller_id uuid,
  p_history_id uuid,
  p_ref_code text,
  p_title text default null,
  p_photo_url text default null,
  p_action text default 'history_continued'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_norm text;
  v_ref text;
begin
  v_ref := trim(coalesce(p_ref_code, ''));
  v_norm := public.batata_normalize_ref(v_ref);
  if p_history_id is null or p_seller_id is null or v_norm = '' then
    return;
  end if;

  insert into public.ref_histories (
    id, seller_id, ref_code_normalized, ref_code_display,
    display_title, display_photo_url, status, updated_at
  )
  values (
    p_history_id,
    p_seller_id,
    v_norm,
    v_ref,
    nullif(trim(p_title), ''),
    nullif(trim(p_photo_url), ''),
    'active',
    now()
  )
  on conflict (id) do update
  set
    ref_code_display = excluded.ref_code_display,
    display_title = coalesce(excluded.display_title, ref_histories.display_title),
    display_photo_url = coalesce(excluded.display_photo_url, ref_histories.display_photo_url),
    updated_at = now()
  where ref_histories.status = 'active';

  perform public.batata_ref_history_audit(
    p_history_id, p_seller_id, p_action, null,
    jsonb_build_object('ref_code', v_ref)
  );
end;
$$;

revoke all on function public.batata_ref_history_item_ids(uuid) from public;
grant execute on function public.batata_ref_history_item_ids(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Preview ref reutilizada — históricos + stats extra
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
  v_histories jsonb;
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
      coalesce(li.logical_item_id, li.id) as history_id,
      li.title,
      li.photo_url,
      li.price,
      li.quantity,
      li.ref_code,
      li.live_id,
      li.updated_at,
      coalesce(l.ended_at, l.created_at, li.updated_at) as used_at,
      public.batata_live_origin_label(li.live_id) as origin_label,
      row_number() over (
        partition by coalesce(li.logical_item_id, li.id)
        order by
          case l.status when 'ended' then 0 when 'live' then 1 else 2 end,
          case when coalesce(li.price, 0) > 0 then 0 else 1 end,
          coalesce(l.ended_at, l.created_at, li.updated_at) desc nulls last,
          li.updated_at desc nulls last
      ) as rn
    from public.live_items li
    join public.lives l on l.id = li.live_id
    where li.item_kind = 'live_only'
      and public.batata_normalize_ref(li.ref_code) = v_norm
      and coalesce(l.seller_id, l.vendedor_id) = p_seller_id
      and l.status in ('live', 'ended')
      and (p_live_id is null or li.live_id <> p_live_id)
  ),
  history_heads_raw as (
    select * from hist where rn = 1
  ),
  history_heads as (
    select distinct on (public.batata_normalize_ref(h.ref_code))
      h.*
    from history_heads_raw h
    left join public.ref_histories rh on rh.id = h.history_id
    order by
      public.batata_normalize_ref(h.ref_code),
      case coalesce(rh.status, 'active') when 'active' then 0 else 1 end,
      (
        select coalesce(sum(greatest(coalesce(o.quantity, 1), 1)), 0)::bigint
        from public.orders o
        join public.live_items li_o on li_o.id = o.live_item_id
        where coalesce(li_o.logical_item_id, li_o.id) = h.history_id
          and lower(trim(coalesce(o.status, ''))) in (
            'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
          )
      ) desc,
      (
        select count(*)::bigint
        from public.live_reservation_requests r
        join public.live_items li_r on li_r.id = r.live_item_id
        where coalesce(li_r.logical_item_id, li_r.id) = h.history_id
          and r.status in ('pending', 'accepted')
      ) desc,
      h.used_at desc nulls last,
      h.history_id
  ),
  history_item_ids as (
    select h.history_id, array_agg(h.id) as item_ids
    from hist h
    group by h.history_id
  ),
  open_requests as (
    select
      hh.history_id,
      r.id::text as entry_id,
      'live_request'::text as kind,
      r.buyer_id::text as buyer_id,
      r.live_id::text as live_id,
      null::text as product_id,
      coalesce(nullif(trim(p.full_name), ''), 'Comprador') as buyer_name,
      r.status,
      greatest(coalesce(r.requested_qty, 1), 1) as quantity,
      r.created_at,
      public.batata_live_origin_label(r.live_id) as origin
    from history_heads hh
    join history_item_ids hii on hii.history_id = hh.history_id
    join public.live_reservation_requests r
      on r.live_item_id = any (hii.item_ids)
     and r.seller_id = p_seller_id
     and r.status in ('pending', 'accepted')
     and coalesce(lower(r.notes), '') not like '%bag_removed%'
     and coalesce(lower(r.notes), '') not like '%bag_cancelled%'
    left join public.profiles p on p.id = r.buyer_id
  ),
  open_orders as (
    select
      hh.history_id,
      o.id::text as entry_id,
      'order'::text as kind,
      o.buyer_id::text as buyer_id,
      o.live_id::text as live_id,
      o.product_id::text as product_id,
      coalesce(nullif(trim(p.full_name), ''), 'Comprador') as buyer_name,
      o.status,
      greatest(coalesce(o.quantity, 1), 1) as quantity,
      o.created_at,
      public.batata_live_origin_label(o.live_id) as origin
    from history_heads hh
    join history_item_ids hii on hii.history_id = hh.history_id
    join public.orders o
      on o.live_item_id = any (hii.item_ids)
     and coalesce(o.seller_id, p_seller_id) = p_seller_id
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
      hh.history_id,
      o.id::text as entry_id,
      'order'::text as kind,
      o.buyer_id::text as buyer_id,
      o.live_id::text as live_id,
      o.product_id::text as product_id,
      coalesce(nullif(trim(p.full_name), ''), 'Comprador') as buyer_name,
      greatest(coalesce(o.quantity, 1), 1) as quantity,
      o.price_total,
      o.created_at as completed_at,
      public.batata_live_origin_label(o.live_id) as origin,
      o.id::text as order_id
    from history_heads hh
    join history_item_ids hii on hii.history_id = hh.history_id
    join public.orders o
      on coalesce(o.seller_id, p_seller_id) = p_seller_id
     and lower(trim(coalesce(o.status, ''))) in (
       'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
     )
     and (
       o.live_item_id = any (hii.item_ids)
       or (
         o.product_id is not null
         and exists (
           select 1
           from public.live_items li3
           where li3.id = any (hii.item_ids)
             and coalesce(li3.checkout_product_id, li3.product_id) = o.product_id
         )
       )
     )
    left join public.profiles p on p.id = o.buyer_id
  ),
  completed_requests as (
    select
      hh.history_id,
      r.id::text as entry_id,
      'live_request'::text as kind,
      r.buyer_id::text as buyer_id,
      r.live_id::text as live_id,
      coalesce(li.checkout_product_id, li.product_id)::text as product_id,
      coalesce(nullif(trim(p.full_name), ''), 'Comprador') as buyer_name,
      greatest(coalesce(r.requested_qty, 1), 1) as quantity,
      coalesce(r.updated_at, r.created_at) as completed_at,
      public.batata_live_origin_label(r.live_id) as origin,
      coalesce(
        (
          select o.id::text
          from public.orders o
          where o.live_item_id = r.live_item_id
            and o.buyer_id = r.buyer_id
            and lower(trim(coalesce(o.status, ''))) in (
              'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
            )
          order by o.created_at desc
          limit 1
        ),
        nullif(
          regexp_replace(
            coalesce(r.notes, ''),
            '.*(?:stripe_paid|stripe_paid_direct|stripe_checkout):([0-9a-fA-F-]{36}).*',
            '\1'
          ),
          coalesce(r.notes, '')
        )
      ) as order_id
    from history_heads hh
    join history_item_ids hii on hii.history_id = hh.history_id
    join public.live_reservation_requests r
      on r.live_item_id = any (hii.item_ids)
     and r.seller_id = p_seller_id
     and r.status = 'converted'
     and not exists (
       select 1
       from public.orders o
       where o.live_item_id = r.live_item_id
         and o.buyer_id = r.buyer_id
         and lower(trim(coalesce(o.status, ''))) in (
           'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
         )
     )
    join public.live_items li on li.id = r.live_item_id
    left join public.profiles p on p.id = r.buyer_id
  ),
  history_stats as (
    select
      hh.history_id,
      hh.title,
      hh.photo_url,
      hh.price,
      hh.quantity,
      hh.used_at as last_used_at,
      hh.origin_label as last_origin,
      hh.live_id as last_live_id,
      coalesce(
        rh.status,
        (
          select rhc.status
          from public.ref_histories rhc
          where rhc.id = hh.history_id
          limit 1
        ),
        'active'
      ) as history_status,
      (select count(distinct h2.live_id)::int from hist h2 where h2.history_id = hh.history_id)
        as live_count,
      coalesce((select count(*)::int from open_requests o where o.history_id = hh.history_id), 0)
        + coalesce((select count(*)::int from open_orders oo where oo.history_id = hh.history_id), 0)
        as open_reservation_count,
      coalesce((select coalesce(sum(o.quantity), 0)::int from open_requests o where o.history_id = hh.history_id), 0)
        + coalesce((select coalesce(sum(oo.quantity), 0)::int from open_orders oo where oo.history_id = hh.history_id), 0)
        as open_reserved_units,
      coalesce((select count(*)::int from completed_orders c where c.history_id = hh.history_id), 0)
        + coalesce((select count(*)::int from completed_requests c where c.history_id = hh.history_id), 0)
        as completed_purchase_count,
      coalesce((select coalesce(sum(c.quantity), 0)::int from completed_orders c where c.history_id = hh.history_id), 0)
        + coalesce((select coalesce(sum(c.quantity), 0)::int from completed_requests c where c.history_id = hh.history_id), 0)
        as completed_units,
      coalesce((
        select coalesce(sum(c.price_total), 0)::numeric
        from completed_orders c where c.history_id = hh.history_id
      ), 0) as sales_value_eur
    from history_heads hh
    left join public.ref_histories rh on rh.id = hh.history_id
  ),
  history_payload as (
    select
      hs.*,
      (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'kind', x.kind, 'id', x.entry_id, 'buyer_id', x.buyer_id,
            'live_id', x.live_id, 'product_id', x.product_id,
            'buyer_name', x.buyer_name, 'status', x.status, 'quantity', x.quantity,
            'origin', x.origin, 'created_at', x.created_at
          ) order by x.created_at asc nulls last
        ), '[]'::jsonb)
        from (
          select * from open_requests o where o.history_id = hs.history_id
          union all
          select * from open_orders oo where oo.history_id = hs.history_id
        ) x
      ) as reservations_open,
      (
        select coalesce(jsonb_agg(t order by t.completed_at desc nulls last), '[]'::jsonb)
        from (
          select c.kind, c.entry_id as id, c.order_id, c.buyer_id, c.live_id,
            c.product_id, c.buyer_name, c.quantity, c.origin, c.completed_at
          from completed_orders c where c.history_id = hs.history_id
          union all
          select c.kind, c.entry_id as id, c.order_id, c.buyer_id, c.live_id,
            c.product_id, c.buyer_name, c.quantity, c.origin, c.completed_at
          from completed_requests c where c.history_id = hs.history_id
          order by completed_at desc nulls last
          limit 10
        ) t
      ) as purchases_completed,
      (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'live_id', h3.live_id,
            'used_at', h3.used_at,
            'origin', h3.origin_label,
            'title', h3.title
          ) order by h3.used_at desc nulls last
        ), '[]'::jsonb)
        from hist h3
        where h3.history_id = hs.history_id
      ) as lives_used
    from history_stats hs
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'logical_item_id', hp.history_id,
      'history_id', hp.history_id,
      'display_title', coalesce(nullif(trim(hp.title), ''), v_ref),
      'display_photo_url', hp.photo_url,
      'display_price', hp.price,
      'display_quantity', coalesce(
        public.batata_ref_history_pool_base_qty(p_seller_id, hp.history_id),
        hp.quantity
      ),
      'available_quantity', coalesce(
        public.batata_ref_history_remaining_qty(p_seller_id, hp.history_id),
        hp.quantity
      ),
      'last_used_at', hp.last_used_at,
      'last_origin', hp.last_origin,
      'last_live_id', hp.last_live_id,
      'history_status', hp.history_status,
      'live_count', hp.live_count,
      'open_reservation_count', hp.open_reservation_count,
      'open_reserved_units', hp.open_reserved_units,
      'completed_purchase_count', hp.completed_purchase_count,
      'completed_units', hp.completed_units,
      'sales_value_eur', hp.sales_value_eur,
      'reservations_open', hp.reservations_open,
      'purchases_completed', hp.purchases_completed,
      'lives_used', hp.lives_used,
      'can_continue', (hp.history_status = 'active')
    )
    order by
      case when hp.history_status = 'active' then 0 else 1 end,
      hp.open_reservation_count desc,
      hp.completed_purchase_count desc,
      hp.last_used_at desc nulls last
  ), '[]'::jsonb)
  into v_histories
  from history_payload hp;

  select jsonb_build_object(
    'history_count', jsonb_array_length(v_histories),
    'lineage_count', jsonb_array_length(v_histories),
    'open_reservation_count', coalesce((
      select sum((e->>'open_reservation_count')::int)::int from jsonb_array_elements(v_histories) e
    ), 0),
    'open_reserved_units', coalesce((
      select sum((e->>'open_reserved_units')::int)::int from jsonb_array_elements(v_histories) e
    ), 0),
    'completed_purchase_count', coalesce((
      select sum((e->>'completed_purchase_count')::int)::int from jsonb_array_elements(v_histories) e
    ), 0),
    'completed_units', coalesce((
      select sum((e->>'completed_units')::int)::int from jsonb_array_elements(v_histories) e
    ), 0),
    'sales_value_eur', coalesce((
      select sum((e->>'sales_value_eur')::numeric) from jsonb_array_elements(v_histories) e
    ), 0)
  )
  into v_summary;

  v_should_show := exists (
    select 1 from jsonb_array_elements(v_histories) e
    where (
      coalesce((e->>'open_reservation_count')::int, 0) > 0
      or coalesce((e->>'completed_purchase_count')::int, 0) > 0
      or (e->>'last_used_at')::timestamptz >= (now() - make_interval(months => v_usage_months))
    )
  );

  return jsonb_build_object(
    'ok', true,
    'ref_code', v_ref,
    'ref_normalized', v_norm,
    'usage_window_months', v_usage_months,
    'has_relevant_history', jsonb_array_length(v_histories) > 0,
    'should_show_sheet', v_should_show,
    'summary', v_summary,
    'lineages', v_histories,
    'histories', v_histories,
    'draft', jsonb_build_object(
      'live_item_id', v_draft_item_id,
      'logical_item_id', v_draft_logical_id,
      'needs_lineage_decision', v_draft_logical_id is null and v_should_show
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 3b) Qty restante do histórico (vendas + reservas abertas em todos os directos)
-- ---------------------------------------------------------------------------
create or replace function public.batata_ref_history_pool_base_qty(
  p_seller_id uuid,
  p_logical_item_id uuid
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_base integer := 1;
begin
  if p_seller_id is null or p_logical_item_id is null then
    return 1;
  end if;

  select greatest(coalesce(max(li.quantity), 1), 1) into v_base
  from public.live_items li
  join public.lives l on l.id = li.live_id
  where coalesce(li.logical_item_id, li.id) = p_logical_item_id
    and coalesce(l.seller_id, l.vendedor_id) = p_seller_id
    and l.status in ('live', 'ended', 'draft');

  return greatest(coalesce(v_base, 1), 1);
end;
$$;

revoke all on function public.batata_ref_history_pool_base_qty(uuid, uuid) from public;
grant execute on function public.batata_ref_history_pool_base_qty(uuid, uuid) to authenticated;

create or replace function public.batata_ref_history_remaining_qty(
  p_seller_id uuid,
  p_logical_item_id uuid
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_base integer := 1;
  v_sold integer := 0;
  v_open integer := 0;
begin
  if p_seller_id is null or p_logical_item_id is null then
    return 1;
  end if;

  v_base := public.batata_ref_history_pool_base_qty(p_seller_id, p_logical_item_id);

  select coalesce(sum(o.quantity), 0)::int into v_sold
  from public.orders o
  where coalesce(o.seller_id, p_seller_id) = p_seller_id
    and lower(trim(coalesce(o.status, ''))) in (
      'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
    )
    and (
      exists (
        select 1
        from public.live_items li2
        where coalesce(li2.logical_item_id, li2.id) = p_logical_item_id
          and o.live_item_id = li2.id
      )
      or (
        o.product_id is not null
        and exists (
          select 1
          from public.live_items li2
          where coalesce(li2.logical_item_id, li2.id) = p_logical_item_id
            and coalesce(li2.checkout_product_id, li2.product_id) = o.product_id
        )
      )
    );

  select coalesce(sum(r.requested_qty), 0)::int into v_open
  from public.live_reservation_requests r
  join public.live_items li2 on li2.id = r.live_item_id
  join public.lives l2 on l2.id = li2.live_id
  where coalesce(li2.logical_item_id, li2.id) = p_logical_item_id
    and coalesce(l2.seller_id, l2.vendedor_id) = p_seller_id
    and r.status in ('pending', 'accepted');

  return greatest(
    v_base - coalesce(v_sold, 0) - coalesce(v_open, 0),
    0
  );
end;
$$;

revoke all on function public.batata_ref_history_remaining_qty(uuid, uuid) from public;
grant execute on function public.batata_ref_history_remaining_qty(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Upsert live_only — Z5 herança qty/título/foto/tamanho no modo inherit
-- ---------------------------------------------------------------------------
create or replace function public.batata_upsert_live_only_item(
  p_seller_id uuid,
  p_ref_code text,
  p_title text default null,
  p_price numeric default null,
  p_quantity integer default null,
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
  v_hist_title text;
  v_hist_qty int;
  v_hist_photo text;
  v_hist_size text;
  v_hist_gender text;
  v_final_title text;
  v_final_qty int;
  v_final_photo text;
  v_final_size text;
  v_final_gender text;
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

  if p_logical_item_id is not null then
    select
      li.title, li.quantity, li.photo_url, li.clothing_size, li.gender, li.price
    into
      v_hist_title, v_hist_qty, v_hist_photo, v_hist_size, v_hist_gender, v_resolved_price
    from public.live_items li
    join public.lives l on l.id = li.live_id
    where coalesce(li.logical_item_id, li.id) = p_logical_item_id
    order by
      case l.status when 'ended' then 0 when 'live' then 1 when 'draft' then 2 else 3 end,
      case
        when nullif(trim(li.clothing_size), '') is not null
          or nullif(trim(li.gender), '') is not null
          or nullif(trim(li.photo_url), '') is not null then 0
        else 1
      end,
      li.updated_at desc nulls last,
      li.created_at desc
    limit 1;

    select
      coalesce(nullif(trim(rh.display_title), ''), v_hist_title),
      coalesce(nullif(trim(rh.display_photo_url), ''), v_hist_photo)
    into v_hist_title, v_hist_photo
    from public.ref_histories rh
    where rh.id = p_logical_item_id
      and rh.seller_id = p_seller_id
    limit 1;
  end if;

  if p_price is not null and p_price > 0 then
    v_resolved_price := p_price;
  elsif v_resolved_price is null or v_resolved_price <= 0 then
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
      where coalesce(li.logical_item_id, li.id) = p_logical_item_id
        and li.price is not null
        and li.price > 0
      order by li.updated_at desc nulls last
      limit 1;
    end if;
  end if;

  v_final_title := coalesce(nullif(trim(p_title), ''), nullif(trim(v_hist_title), ''), v_ref);
  if v_mode = 'inherit' and p_logical_item_id is not null then
    v_final_qty := greatest(
      coalesce(
        p_quantity,
        public.batata_ref_history_pool_base_qty(p_seller_id, p_logical_item_id)
      ),
      1
    );
  else
    v_final_qty := greatest(
      coalesce(p_quantity, v_hist_qty, 1),
      1
    );
  end if;
  v_final_photo := coalesce(nullif(trim(p_photo_url), ''), nullif(trim(v_hist_photo), ''));
  v_final_size := coalesce(nullif(trim(p_clothing_size), ''), nullif(trim(v_hist_size), ''));
  v_final_gender := coalesce(nullif(trim(p_gender), ''), nullif(trim(v_hist_gender), ''));

  select li.id, li.logical_item_id
  into v_item_id, v_existing_logical
  from public.live_items li
  where li.live_id = v_live_id
    and li.item_kind = 'live_only'
    and public.batata_normalize_ref(li.ref_code) = v_norm
  limit 1;

  if v_item_id is not null then
    if v_mode = 'inherit' then
      if p_logical_item_id is null then
        raise exception 'logical_item_id_required';
      end if;
      if exists (
        select 1
        from public.ref_histories rh
        where rh.id = p_logical_item_id
          and rh.seller_id = p_seller_id
          and rh.status not in ('active')
      ) then
        raise exception 'history_not_active';
      end if;
      if not exists (
        select 1
        from public.live_items li
        join public.lives l on l.id = li.live_id
        where (
          coalesce(li.logical_item_id, li.id) = p_logical_item_id
          or li.id = p_logical_item_id
        )
          and coalesce(l.seller_id, l.vendedor_id) = p_seller_id
          and li.item_kind = 'live_only'
      )
      and not exists (
        select 1
        from public.ref_histories rh
        where rh.id = p_logical_item_id
          and rh.seller_id = p_seller_id
      ) then
        raise exception 'lineage_not_found';
      end if;
      v_new_logical := p_logical_item_id;

      update public.live_items
      set
        ref_code = v_ref,
        title = v_final_title,
        price = coalesce(nullif(p_price, 0), v_resolved_price),
        quantity = v_final_qty,
        clothing_size = nullif(v_final_size, ''),
        gender = nullif(v_final_gender, ''),
        photo_url = nullif(v_final_photo, ''),
        logical_item_id = v_new_logical,
        updated_at = now()
      where id = v_item_id;

      perform public.batata_ensure_ref_history(
        p_seller_id, v_new_logical, v_ref, v_final_title, v_final_photo, 'history_continued'
      );

      return jsonb_build_object(
        'ok', true,
        'live_item_id', v_item_id,
        'logical_item_id', v_new_logical,
        'lineage_mode', 'inherit'
      );
    elsif v_mode = 'new' then
      v_new_logical := gen_random_uuid();

      update public.live_items
      set
        ref_code = v_ref,
        title = v_final_title,
        price = coalesce(nullif(p_price, 0), v_resolved_price),
        quantity = v_final_qty,
        clothing_size = nullif(v_final_size, ''),
        gender = nullif(v_final_gender, ''),
        photo_url = nullif(v_final_photo, ''),
        logical_item_id = v_new_logical,
        updated_at = now()
      where id = v_item_id;

      perform public.batata_ensure_ref_history(
        p_seller_id, v_new_logical, v_ref, v_final_title, v_final_photo, 'history_started'
      );

      return jsonb_build_object(
        'ok', true,
        'live_item_id', v_item_id,
        'logical_item_id', v_new_logical,
        'lineage_mode', 'new'
      );
    elsif v_existing_logical is not null then
      update public.live_items
      set
        ref_code = v_ref,
        title = coalesce(
          nullif(trim(p_title), ''),
          nullif(trim(v_hist_title), ''),
          title
        ),
        price = coalesce(
          nullif(p_price, 0),
          case
            when coalesce(price, 0) <= 0 then nullif(v_resolved_price, 0)
            else price
          end
        ),
        quantity = case
          when p_quantity is not null then greatest(p_quantity, 1)
          else greatest(coalesce(v_hist_qty, quantity, 1), 1)
        end,
        clothing_size = coalesce(
          nullif(trim(p_clothing_size), ''),
          nullif(trim(v_hist_size), ''),
          clothing_size
        ),
        gender = coalesce(
          nullif(trim(p_gender), ''),
          nullif(trim(v_hist_gender), ''),
          gender
        ),
        photo_url = coalesce(
          nullif(trim(p_photo_url), ''),
          nullif(trim(v_hist_photo), ''),
          photo_url
        ),
        updated_at = now()
      where id = v_item_id;

      return jsonb_build_object(
        'ok', true,
        'live_item_id', v_item_id,
        'logical_item_id', v_existing_logical,
        'lineage_mode', 'keep'
      );
    end if;
  end if;

  if v_mode = 'inherit' then
    if p_logical_item_id is null then
      raise exception 'logical_item_id_required';
    end if;
    if exists (
      select 1
      from public.ref_histories rh
      where rh.id = p_logical_item_id
        and rh.seller_id = p_seller_id
        and rh.status not in ('active')
    ) then
      raise exception 'history_not_active';
    end if;
    if not exists (
      select 1
      from public.live_items li
      join public.lives l on l.id = li.live_id
      where (
        coalesce(li.logical_item_id, li.id) = p_logical_item_id
        or li.id = p_logical_item_id
      )
        and coalesce(l.seller_id, l.vendedor_id) = p_seller_id
        and li.item_kind = 'live_only'
    )
    and not exists (
      select 1
      from public.ref_histories rh
      where rh.id = p_logical_item_id
        and rh.seller_id = p_seller_id
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
    v_final_title,
    v_resolved_price,
    nullif(v_final_photo, ''),
    v_final_qty,
    nullif(v_final_size, ''),
    nullif(v_final_gender, ''),
    false,
    'available',
    v_new_logical,
    now()
  )
  returning id into v_item_id;

  perform public.batata_ensure_ref_history(
    p_seller_id,
    v_new_logical,
    v_ref,
    v_final_title,
    v_final_photo,
    case when v_mode = 'inherit' then 'history_continued' else 'history_started' end
  );

  return jsonb_build_object(
    'ok', true,
    'live_item_id', v_item_id,
    'logical_item_id', v_new_logical,
    'lineage_mode', v_mode
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5) Detalhe de um histórico
-- ---------------------------------------------------------------------------
create or replace function public.batata_ref_history_detail(
  p_seller_id uuid,
  p_history_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ref text;
  v_preview jsonb;
  v_entry jsonb;
begin
  if p_seller_id is null or p_history_id is null then
    return jsonb_build_object('ok', false, 'error', 'params_required');
  end if;

  if not (
    auth.uid() = p_seller_id
    or public.batata_staff_has_permission(p_seller_id, 'can_manage_reservations')
    or public.batata_staff_has_permission(p_seller_id, 'can_view_live_dashboard')
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  select coalesce(rh.ref_code_display, li.ref_code)
  into v_ref
  from public.ref_histories rh
  left join public.live_items li on li.logical_item_id = rh.id
  where rh.id = p_history_id and rh.seller_id = p_seller_id
  limit 1;

  if v_ref is null then
    select li.ref_code into v_ref
    from public.live_items li
    join public.lives l on l.id = li.live_id
    where coalesce(li.logical_item_id, li.id) = p_history_id
      and coalesce(l.seller_id, l.vendedor_id) = p_seller_id
    order by li.updated_at desc
    limit 1;
  end if;

  if v_ref is null then
    return jsonb_build_object('ok', false, 'error', 'history_not_found');
  end if;

  v_preview := public.batata_live_ref_open_reservations_preview(
    p_seller_id, v_ref, null
  );

  select e into v_entry
  from jsonb_array_elements(coalesce(v_preview->'histories', '[]'::jsonb)) e
  where (e->>'history_id')::uuid = p_history_id
     or (e->>'logical_item_id')::uuid = p_history_id
  limit 1;

  if v_entry is null then
    return jsonb_build_object('ok', false, 'error', 'history_not_found');
  end if;

  return jsonb_build_object(
    'ok', true,
    'history', v_entry || jsonb_build_object(
      'ref_code', v_ref,
      'can_close', coalesce(v_entry->>'history_status', 'active') = 'active',
      'can_merge', coalesce(v_entry->>'history_status', 'active') = 'active'
        and coalesce((v_entry->>'open_reservation_count')::int, 0) = 0
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 6) Encerrar histórico
-- ---------------------------------------------------------------------------
create or replace function public.batata_ref_history_close_preview(
  p_seller_id uuid,
  p_history_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_item_ids uuid[];
  v_pending int := 0;
  v_accepted int := 0;
  v_unpaid int := 0;
  v_status text;
begin
  if p_seller_id is null or p_history_id is null then
    return jsonb_build_object('ok', false, 'error', 'params_required');
  end if;

  if auth.uid() is distinct from p_seller_id
     and not public.batata_staff_has_permission(p_seller_id, 'can_manage_reservations') then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  select rh.status into v_status
  from public.ref_histories rh
  where rh.id = p_history_id and rh.seller_id = p_seller_id;

  if v_status is null then
    if not exists (
      select 1 from public.live_items li
      join public.lives l on l.id = li.live_id
      where coalesce(li.logical_item_id, li.id) = p_history_id
        and coalesce(l.seller_id, l.vendedor_id) = p_seller_id
    ) then
      return jsonb_build_object('ok', false, 'error', 'history_not_found');
    end if;
    v_status := 'active';
  end if;

  if v_status <> 'active' then
    return jsonb_build_object('ok', false, 'error', 'history_not_active');
  end if;

  v_item_ids := public.batata_ref_history_item_ids(p_history_id);

  select count(*)::int into v_pending
  from public.live_reservation_requests r
  where r.live_item_id = any (v_item_ids)
    and r.seller_id = p_seller_id
    and r.status = 'pending';

  select count(*)::int into v_accepted
  from public.live_reservation_requests r
  where r.live_item_id = any (v_item_ids)
    and r.seller_id = p_seller_id
    and r.status = 'accepted';

  select count(*)::int into v_unpaid
  from public.orders o
  where o.live_item_id = any (v_item_ids)
    and o.seller_id = p_seller_id
    and lower(trim(coalesce(o.status, ''))) in (
      'reserva_pendente', 'reservado', 'aguarda_confirmacao', 'pendente'
    )
    and lower(trim(coalesce(o.status, ''))) not in (
      'cancelado', 'cancelada', 'cancelled', 'canceled', 'anulado', 'anulada'
    );

  return jsonb_build_object(
    'ok', true,
    'history_id', p_history_id,
    'pending_requests', v_pending,
    'accepted_requests', v_accepted,
    'unpaid_orders', v_unpaid,
    'will_cancel_total', v_pending + v_accepted + v_unpaid,
    'paid_orders_preserved', true
  );
end;
$$;

create or replace function public.batata_ref_history_close(
  p_seller_id uuid,
  p_history_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_ids uuid[];
  v_preview jsonb;
  v_cancelled int := 0;
  v_rows int := 0;
begin
  if p_seller_id is null or p_history_id is null then
    return jsonb_build_object('ok', false, 'error', 'params_required');
  end if;

  if auth.uid() is distinct from p_seller_id
     and not public.batata_staff_has_permission(p_seller_id, 'can_manage_reservations') then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  v_preview := public.batata_ref_history_close_preview(p_seller_id, p_history_id);
  if coalesce(v_preview->>'ok', 'false') <> 'true' then
    return v_preview;
  end if;

  v_item_ids := public.batata_ref_history_item_ids(p_history_id);

  update public.live_reservation_requests
  set
    status = 'rejected',
    notes = trim(both ' |' from coalesce(notes, '') || ' | history_closed'),
    updated_at = now()
  where live_item_id = any (v_item_ids)
    and seller_id = p_seller_id
    and status in ('pending', 'accepted');

  get diagnostics v_cancelled = row_count;

  update public.orders
  set status = 'cancelado'
  where live_item_id = any (v_item_ids)
    and seller_id = p_seller_id
    and lower(trim(coalesce(status, ''))) in (
      'reserva_pendente', 'reservado', 'aguarda_confirmacao', 'pendente'
    )
    and lower(trim(coalesce(status, ''))) not in (
      'cancelado', 'cancelada', 'cancelled', 'canceled', 'anulado', 'anulada'
    );

  get diagnostics v_rows = row_count;
  v_cancelled := v_cancelled + v_rows;

  insert into public.ref_histories (
    id, seller_id, ref_code_normalized, ref_code_display,
    display_title, display_photo_url, status, closed_at, closed_by, updated_at
  )
  select
    p_history_id,
    p_seller_id,
    coalesce(
      nullif(public.batata_normalize_ref(coalesce(rh.ref_code_display, li.ref_code)), ''),
      'ref'
    ),
    coalesce(rh.ref_code_display, li.ref_code, 'ref'),
    coalesce(rh.display_title, li.title),
    coalesce(rh.display_photo_url, li.photo_url),
    'closed',
    now(),
    auth.uid(),
    now()
  from (select 1) x
  left join public.ref_histories rh on rh.id = p_history_id
  left join lateral (
    select li2.ref_code, li2.title, li2.photo_url
    from public.live_items li2
    where coalesce(li2.logical_item_id, li2.id) = p_history_id
    order by li2.updated_at desc
    limit 1
  ) li on true
  on conflict (id) do update
  set
    status = 'closed',
    closed_at = now(),
    closed_by = auth.uid(),
    updated_at = now();

  perform public.batata_ref_history_audit(
    p_history_id, p_seller_id, 'history_closed', p_reason,
    jsonb_build_object(
      'cancelled_total', v_cancelled,
      'preview', v_preview
    )
  );

  return jsonb_build_object(
    'ok', true,
    'history_id', p_history_id,
    'cancelled_total', v_cancelled
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 7) Lista — Gestão de referências
-- ---------------------------------------------------------------------------
create or replace function public.batata_ref_histories_list(
  p_seller_id uuid,
  p_filter text default 'all',
  p_search text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rows jsonb;
  v_total int;
  v_filter text;
  v_search text;
begin
  if p_seller_id is null then
    return jsonb_build_object('ok', false, 'error', 'seller_required');
  end if;

  if not (
    auth.uid() = p_seller_id
    or public.batata_staff_has_permission(p_seller_id, 'can_view_live_dashboard')
    or public.batata_staff_has_permission(p_seller_id, 'can_manage_reservations')
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  v_filter := lower(trim(coalesce(p_filter, 'all')));
  v_search := lower(trim(coalesce(p_search, '')));

  with grouped as (
    select
      coalesce(li.logical_item_id, li.id) as history_id,
      max(coalesce(rh.ref_code_display, li.ref_code)) as ref_code,
      max(coalesce(
        rh.ref_code_normalized,
        public.batata_normalize_ref(li.ref_code)
      )) as ref_normalized,
      max(coalesce(rh.updated_at, li.updated_at)) as updated_at,
      max(coalesce(rh.created_at, li.created_at)) as created_at,
      count(distinct li.live_id) as live_count,
      max(coalesce(l.ended_at, l.created_at, li.updated_at)) as last_used_at
    from public.live_items li
    join public.lives l on l.id = li.live_id
    left join public.ref_histories rh
      on rh.id = coalesce(li.logical_item_id, li.id)
    where li.item_kind = 'live_only'
      and coalesce(l.seller_id, l.vendedor_id) = p_seller_id
    group by coalesce(li.logical_item_id, li.id)
  ),
  base as (
    select
      g.history_id,
      g.ref_code,
      g.ref_normalized,
      (
        select li2.title
        from public.live_items li2
        where coalesce(li2.logical_item_id, li2.id) = g.history_id
        order by li2.updated_at desc nulls last, li2.created_at desc
        limit 1
      ) as display_title,
      (
        select li2.photo_url
        from public.live_items li2
        where coalesce(li2.logical_item_id, li2.id) = g.history_id
        order by li2.updated_at desc nulls last, li2.created_at desc
        limit 1
      ) as display_photo_url,
      g.updated_at,
      g.created_at,
      g.live_count,
      g.last_used_at
    from grouped g
  ),
  with_stats as (
    select
      b.history_id,
      b.ref_code,
      b.ref_normalized,
      b.display_title,
      b.display_photo_url,
      coalesce(
        (select rh2.status from public.ref_histories rh2
         where rh2.id = b.history_id limit 1),
        'active'
      ) as history_status,
      b.updated_at,
      b.created_at,
      b.live_count,
      b.last_used_at,
      coalesce((
        select count(*)::int
        from public.live_reservation_requests r
        join public.live_items li2 on li2.id = r.live_item_id
        where coalesce(li2.logical_item_id, li2.id) = b.history_id
          and coalesce(r.seller_id, p_seller_id) = p_seller_id
          and r.status in ('pending', 'accepted')
      ), 0) + coalesce((
        select count(distinct o.id)::int
        from public.orders o
        join public.live_items li2 on li2.id = o.live_item_id
        where coalesce(li2.logical_item_id, li2.id) = b.history_id
          and coalesce(o.seller_id, p_seller_id) = p_seller_id
          and lower(trim(coalesce(o.status, ''))) in (
            'reserva_pendente', 'reservado', 'aguarda_confirmacao', 'pendente'
          )
          and lower(trim(coalesce(o.status, ''))) not in (
            'cancelado', 'cancelada', 'cancelled', 'canceled', 'anulado', 'anulada'
          )
      ), 0) as open_reservation_count,
      coalesce((
        select count(distinct o.id)::int
        from public.orders o
        where coalesce(o.seller_id, p_seller_id) = p_seller_id
          and lower(trim(coalesce(o.status, ''))) in (
            'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
          )
          and (
            exists (
              select 1
              from public.live_items li2
              where coalesce(li2.logical_item_id, li2.id) = b.history_id
                and o.live_item_id = li2.id
            )
            or (
              o.product_id is not null
              and exists (
                select 1
                from public.live_items li2
                where coalesce(li2.logical_item_id, li2.id) = b.history_id
                  and coalesce(li2.checkout_product_id, li2.product_id) = o.product_id
              )
            )
          )
      ), 0) + coalesce((
        select count(distinct r.id)::int
        from public.live_reservation_requests r
        join public.live_items li2 on li2.id = r.live_item_id
        where coalesce(li2.logical_item_id, li2.id) = b.history_id
          and coalesce(r.seller_id, p_seller_id) = p_seller_id
          and r.status = 'converted'
          and not exists (
            select 1
            from public.orders o2
            where o2.live_item_id = r.live_item_id
              and o2.buyer_id = r.buyer_id
              and coalesce(o2.seller_id, p_seller_id) = p_seller_id
              and lower(trim(coalesce(o2.status, ''))) in (
                'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
              )
          )
      ), 0) as completed_purchase_count,
      coalesce((
        select coalesce(sum(o.price_total), 0)::numeric
        from public.orders o
        where coalesce(o.seller_id, p_seller_id) = p_seller_id
          and lower(trim(coalesce(o.status, ''))) in (
            'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
          )
          and (
            exists (
              select 1
              from public.live_items li2
              where coalesce(li2.logical_item_id, li2.id) = b.history_id
                and o.live_item_id = li2.id
            )
            or (
              o.product_id is not null
              and exists (
                select 1
                from public.live_items li2
                where coalesce(li2.logical_item_id, li2.id) = b.history_id
                  and coalesce(li2.checkout_product_id, li2.product_id) = o.product_id
              )
            )
          )
      ), 0) as sales_value_eur
    from base b
  ),
  filtered as (
    select *
    from with_stats ws
    where (
      v_search = ''
      or lower(ws.ref_code) like '%' || v_search || '%'
      or lower(coalesce(ws.display_title, '')) like '%' || v_search || '%'
      or lower(ws.ref_normalized) like '%' || v_search || '%'
    )
    and (
      v_filter = 'all'
      or (v_filter = 'active' and ws.history_status = 'active')
      or (v_filter = 'closed' and ws.history_status = 'closed')
      or (v_filter = 'merged' and ws.history_status = 'merged')
      or (v_filter = 'pending' and ws.open_reservation_count > 0)
      or (v_filter = 'popular' and ws.completed_purchase_count >= 3)
    )
  )
  select
    (select count(*)::int from filtered),
    (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'history_id', f.history_id::text,
          'ref_code', f.ref_code,
          'ref_normalized', f.ref_normalized,
          'display_title', f.display_title,
          'display_photo_url', f.display_photo_url,
          'history_status', f.history_status,
          'live_count', f.live_count,
          'open_reservation_count', f.open_reservation_count,
          'completed_purchase_count', f.completed_purchase_count,
          'sales_value_eur', f.sales_value_eur,
          'last_used_at', f.last_used_at
        ) order by f.last_used_at desc nulls last
      ), '[]'::jsonb)
      from (
        select *
        from filtered
        order by last_used_at desc nulls last
        limit greatest(coalesce(p_limit, 50), 1)
        offset greatest(coalesce(p_offset, 0), 0)
      ) f
    )
  into v_total, v_rows;

  return jsonb_build_object(
    'ok', true,
    'total', v_total,
    'histories', v_rows
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 8) Juntar históricos (merge V1 conservador)
-- ---------------------------------------------------------------------------
create or replace function public.batata_ref_histories_merge_preview(
  p_seller_id uuid,
  p_target_history_id uuid,
  p_source_history_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_target_ref text;
  v_source_ref text;
  v_target_status text;
  v_source_status text;
  v_source_open int := 0;
begin
  if p_seller_id is null or p_target_history_id is null or p_source_history_id is null then
    return jsonb_build_object('ok', false, 'error', 'params_required');
  end if;

  if p_target_history_id = p_source_history_id then
    return jsonb_build_object('ok', false, 'error', 'same_history');
  end if;

  if auth.uid() is distinct from p_seller_id
     and not public.batata_staff_has_permission(p_seller_id, 'can_manage_reservations') then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  select coalesce(rh.ref_code_display, li.ref_code), coalesce(rh.status, 'active')
  into v_target_ref, v_target_status
  from (select 1) x
  left join public.ref_histories rh
    on rh.id = p_target_history_id and rh.seller_id = p_seller_id
  left join lateral (
    select li2.ref_code
    from public.live_items li2
    join public.lives l2 on l2.id = li2.live_id
    where coalesce(li2.logical_item_id, li2.id) = p_target_history_id
      and coalesce(l2.seller_id, l2.vendedor_id) = p_seller_id
    order by li2.updated_at desc
    limit 1
  ) li on true;

  select coalesce(rh.ref_code_display, li.ref_code), coalesce(rh.status, 'active')
  into v_source_ref, v_source_status
  from (select 1) x
  left join public.ref_histories rh
    on rh.id = p_source_history_id and rh.seller_id = p_seller_id
  left join lateral (
    select li2.ref_code
    from public.live_items li2
    join public.lives l2 on l2.id = li2.live_id
    where coalesce(li2.logical_item_id, li2.id) = p_source_history_id
      and coalesce(l2.seller_id, l2.vendedor_id) = p_seller_id
    order by li2.updated_at desc
    limit 1
  ) li on true;

  if v_target_ref is null or v_source_ref is null then
    return jsonb_build_object('ok', false, 'error', 'history_not_found');
  end if;

  if public.batata_normalize_ref(v_target_ref) <> public.batata_normalize_ref(v_source_ref) then
    return jsonb_build_object('ok', false, 'error', 'ref_mismatch');
  end if;

  if coalesce(v_target_status, 'active') <> 'active'
     or coalesce(v_source_status, 'active') <> 'active' then
    return jsonb_build_object('ok', false, 'error', 'history_not_active');
  end if;

  select count(*)::int into v_source_open
  from public.live_reservation_requests r
  where r.live_item_id = any (public.batata_ref_history_item_ids(p_source_history_id))
    and r.seller_id = p_seller_id
    and r.status in ('pending', 'accepted');

  if v_source_open > 0 then
    return jsonb_build_object('ok', false, 'error', 'source_has_open_reservations');
  end if;

  if exists (
    select 1 from public.orders o
    where o.live_item_id = any (public.batata_ref_history_item_ids(p_source_history_id))
      and o.seller_id = p_seller_id
      and lower(trim(coalesce(o.status, ''))) in (
        'reserva_pendente', 'reservado', 'aguarda_confirmacao', 'pendente'
      )
      and lower(trim(coalesce(o.status, ''))) not in (
        'cancelado', 'cancelada', 'cancelled', 'canceled', 'anulado', 'anulada'
      )
  ) then
    return jsonb_build_object('ok', false, 'error', 'source_has_unpaid_orders');
  end if;

  return jsonb_build_object(
    'ok', true,
    'target_history_id', p_target_history_id,
    'source_history_id', p_source_history_id,
    'ref_code', v_target_ref,
    'items_to_repoint', (
      select count(*)::int
      from public.live_items li
      where coalesce(li.logical_item_id, li.id) = p_source_history_id
    ),
    'reservations_preserved', true,
    'orders_preserved', true
  );
end;
$$;

create or replace function public.batata_ref_histories_merge(
  p_seller_id uuid,
  p_target_history_id uuid,
  p_source_history_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_preview jsonb;
  v_moved int := 0;
begin
  v_preview := public.batata_ref_histories_merge_preview(
    p_seller_id, p_target_history_id, p_source_history_id
  );
  if coalesce(v_preview->>'ok', 'false') <> 'true' then
    return v_preview;
  end if;

  update public.live_items
  set
    logical_item_id = p_target_history_id,
    updated_at = now()
  where coalesce(logical_item_id, id) = p_source_history_id;

  get diagnostics v_moved = row_count;

  insert into public.ref_histories (
    id, seller_id, ref_code_normalized, ref_code_display, status,
    merged_into_id, updated_at
  )
  select
    p_source_history_id,
    p_seller_id,
    public.batata_normalize_ref(rh.ref_code_display),
    rh.ref_code_display,
    'merged',
    p_target_history_id,
    now()
  from public.ref_histories rh
  where rh.id = p_source_history_id
  on conflict (id) do update
  set
    status = 'merged',
    merged_into_id = p_target_history_id,
    updated_at = now();

  insert into public.ref_history_merges (
    seller_id, target_history_id, source_history_id, merged_by, payload
  )
  values (
    p_seller_id,
    p_target_history_id,
    p_source_history_id,
    auth.uid(),
    jsonb_build_object('moved_items', v_moved, 'preview', v_preview)
  );

  perform public.batata_ref_history_audit(
    p_target_history_id, p_seller_id, 'histories_merged', p_reason,
    jsonb_build_object(
      'source_history_id', p_source_history_id,
      'moved_items', v_moved
    )
  );

  perform public.batata_ref_history_audit(
    p_source_history_id, p_seller_id, 'history_merged_into', p_reason,
    jsonb_build_object('target_history_id', p_target_history_id)
  );

  return jsonb_build_object(
    'ok', true,
    'target_history_id', p_target_history_id,
    'source_history_id', p_source_history_id,
    'moved_items', v_moved
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 9) Grants + PostgREST
-- ---------------------------------------------------------------------------
revoke all on function public.batata_live_ref_open_reservations_preview(uuid, text, uuid) from public;
grant execute on function public.batata_live_ref_open_reservations_preview(uuid, text, uuid) to authenticated;

revoke all on function public.batata_upsert_live_only_item(
  uuid, text, text, numeric, integer, text, text, text, uuid, text, uuid
) from public;
grant execute on function public.batata_upsert_live_only_item(
  uuid, text, text, numeric, integer, text, text, text, uuid, text, uuid
) to authenticated;

revoke all on function public.batata_ref_history_detail(uuid, uuid) from public;
grant execute on function public.batata_ref_history_detail(uuid, uuid) to authenticated;

revoke all on function public.batata_ref_history_close_preview(uuid, uuid) from public;
grant execute on function public.batata_ref_history_close_preview(uuid, uuid) to authenticated;

revoke all on function public.batata_ref_history_close(uuid, uuid, text) from public;
grant execute on function public.batata_ref_history_close(uuid, uuid, text) to authenticated;

revoke all on function public.batata_ref_histories_list(uuid, text, text, integer, integer) from public;
grant execute on function public.batata_ref_histories_list(uuid, text, text, integer, integer) to authenticated;

revoke all on function public.batata_ref_histories_merge_preview(uuid, uuid, uuid) from public;
grant execute on function public.batata_ref_histories_merge_preview(uuid, uuid, uuid) to authenticated;

revoke all on function public.batata_ref_histories_merge(uuid, uuid, uuid, text) from public;
grant execute on function public.batata_ref_histories_merge(uuid, uuid, uuid, text) to authenticated;

notify pgrst, 'reload schema';
