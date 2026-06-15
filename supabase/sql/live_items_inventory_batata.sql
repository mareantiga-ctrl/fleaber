-- Fleaber BATATA: inventário unificado live_items (TYPE A marketplace / TYPE B live-only).
-- Executar após: live_items_batata.sql, products_orders_quantity_batata.sql,
-- seller_helpers_staff_batata.sql, live_reservation_requests_batata.sql

-- ---------------------------------------------------------------------------
-- 1) lives.status inclui draft (catálogo prep antes de Mux)
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from pg_constraint
    where conrelid = 'public.lives'::regclass and conname = 'lives_status_check'
  ) then
    alter table public.lives drop constraint lives_status_check;
  end if;
end $$;

alter table public.lives
  add constraint lives_status_check
  check (status in ('scheduled', 'draft', 'live', 'ended', 'error'));

-- ---------------------------------------------------------------------------
-- 2) live_items — colunas inventário
-- ---------------------------------------------------------------------------
alter table public.live_items
  add column if not exists item_kind text not null default 'live_only',
  add column if not exists product_id uuid references public.products (id) on delete set null,
  add column if not exists checkout_product_id uuid references public.products (id) on delete set null,
  add column if not exists quantity integer,
  add column if not exists clothing_size text,
  add column if not exists gender text,
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'live_items_item_kind_chk'
      and conrelid = 'public.live_items'::regclass
  ) then
    alter table public.live_items
      add constraint live_items_item_kind_chk
      check (item_kind in ('marketplace_product', 'live_only'));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'live_items_kind_stock_chk'
      and conrelid = 'public.live_items'::regclass
  ) then
    alter table public.live_items
      add constraint live_items_kind_stock_chk
      check (
        (item_kind = 'marketplace_product' and product_id is not null and quantity is null)
        or
        (item_kind = 'live_only' and product_id is null and quantity is not null and quantity >= 1)
      );
  end if;
exception
  when others then
    raise notice 'live_items_kind_stock_chk skipped (backfill pending): %', sqlerrm;
end $$;

create unique index if not exists live_items_live_product_uidx
  on public.live_items (live_id, product_id)
  where product_id is not null;

create index if not exists live_items_product_id_idx
  on public.live_items (product_id)
  where product_id is not null;

-- ---------------------------------------------------------------------------
-- 3) Helpers ref + stock
-- ---------------------------------------------------------------------------
create or replace function public.batata_normalize_ref(p_raw text)
returns text
language sql
immutable
as $$
  select upper(
    regexp_replace(
      case when left(trim(coalesce(p_raw, '')), 1) = '#'
        then substring(trim(p_raw) from 2)
        else trim(coalesce(p_raw, ''))
      end,
      '[^A-Z0-9]', '', 'g'
    )
  );
$$;

revoke all on function public.batata_normalize_ref(text) from public;
grant execute on function public.batata_normalize_ref(text) to authenticated;

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
  v_seller uuid;
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

  if v_li.item_kind = 'live_only' then
    select coalesce(l.seller_id, l.vendedor_id) into v_seller
    from public.lives l
    where l.id = v_li.live_id;
    if v_seller is not null then
      return public.batata_ref_history_pool_base_qty(
        v_seller,
        coalesce(v_li.logical_item_id, v_li.id)
      );
    end if;
  end if;

  return greatest(coalesce(v_li.quantity, 1), 1);
end;
$$;

revoke all on function public.batata_live_item_total_qty(uuid) from public;
grant execute on function public.batata_live_item_total_qty(uuid) to authenticated;

-- Mesmo pool de stock entre directos/gravados (ref, linhagem ou produto marketplace).
-- Não usar checkout_product_id: cada live_item tem shadow próprio.
create or replace function public.batata_live_items_same_stock_pool(
  p_li public.live_items,
  p_other public.live_items
)
returns boolean
language sql
stable
as $$
  select
    p_li.id is distinct from p_other.id
    and (
      (
        p_li.product_id is not null
        and p_other.product_id = p_li.product_id
      )
      or (
        public.batata_normalize_ref(p_li.ref_code) <> ''
        and public.batata_normalize_ref(p_other.ref_code)
          = public.batata_normalize_ref(p_li.ref_code)
      )
      or (
        coalesce(p_li.logical_item_id, p_li.id)
          = coalesce(p_other.logical_item_id, p_other.id)
      )
    );
$$;

revoke all on function public.batata_live_items_same_stock_pool(public.live_items, public.live_items) from public;
grant execute on function public.batata_live_items_same_stock_pool(public.live_items, public.live_items) to authenticated;

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

  if v_li.product_id is not null then
    select coalesce(sum(o.quantity), 0)::int into v_blocked_orders
    from public.orders o
    where o.product_id = v_li.product_id
      and coalesce(o.status, '') not in ('cancelado', 'cancelled', 'rejected', 'expired')
      and lower(trim(coalesce(o.status, ''))) in (
        'reservado', 'aguarda_confirmacao',
        'pendente', 'pedido_devolucao', 'em_devolucao'
      )
      and not exists (
        select 1
        from public.live_reservation_requests r
        where r.live_item_id = v_li.id
          and r.buyer_id = o.buyer_id
          and r.status in ('pending', 'accepted')
          and lower(trim(coalesce(o.status, ''))) in (
            'reservado', 'aguarda_confirmacao', 'pendente'
          )
      );
  end if;

  if v_seller is not null then
    select coalesce(sum(r.requested_qty), 0)::int into v_blocked_cross_res
    from public.live_reservation_requests r
    join public.live_items li2 on li2.id = r.live_item_id
    join public.lives l2 on l2.id = li2.live_id
    where r.status in ('pending', 'accepted')
      and public.batata_live_items_same_stock_pool(v_li, li2)
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
      where o.live_item_id = v_li.id
        and o.buyer_id = r.buyer_id
        and lower(trim(coalesce(o.status, ''))) in (
          'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
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
      where o.live_item_id = v_li.id
        and o.buyer_id = r.buyer_id
        and lower(trim(coalesce(o.status, ''))) in (
          'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
        )
    );

  if v_seller is not null then
    -- Z82: vendidos = encomendas pagas (distinct por order) + converted órfão.
    -- Gravado/VOD pode ter order só com product_id; converted não deve duplicar.
    select coalesce(sum(t.qty), 0)::int into v_sold_converted
    from (
      select distinct on (o.id)
        greatest(coalesce(o.quantity, 1), 1) as qty
      from public.orders o
      left join public.live_items li_o on li_o.id = o.live_item_id
      left join public.lives l_o on l_o.id = li_o.live_id
      where lower(trim(coalesce(o.status, ''))) in (
          'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
        )
        and coalesce(o.seller_id, v_seller) = v_seller
        and (
          (
            o.live_item_id is not null
            and li_o.id is not null
            and coalesce(l_o.seller_id, l_o.vendedor_id) = v_seller
            and public.batata_live_items_same_stock_pool(v_li, li_o)
          )
          or (
            v_li.product_id is not null
            and o.product_id = v_li.product_id
          )
          or (
            v_li.checkout_product_id is not null
            and o.product_id = v_li.checkout_product_id
          )
        )
      order by o.id
    ) t;

    select v_sold_converted + coalesce(sum(greatest(coalesce(r.requested_qty, 1), 1)), 0)::int
      into v_sold_converted
    from public.live_reservation_requests r
    join public.live_items li_r on li_r.id = r.live_item_id
    join public.lives l_r on l_r.id = li_r.live_id
    where coalesce(l_r.seller_id, l_r.vendedor_id) = v_seller
      and public.batata_live_items_same_stock_pool(v_li, li_r)
      and r.status = 'converted'
      and not exists (
        select 1
        from public.orders o2
        left join public.live_items li_o2 on li_o2.id = o2.live_item_id
        left join public.lives l_o2 on l_o2.id = li_o2.live_id
        where o2.buyer_id = r.buyer_id
          and lower(trim(coalesce(o2.status, ''))) in (
            'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
          )
          and coalesce(o2.seller_id, v_seller) = v_seller
          and (
            (
              o2.live_item_id is not null
              and li_o2.id is not null
              and coalesce(l_o2.seller_id, l_o2.vendedor_id) = v_seller
              and public.batata_live_items_same_stock_pool(v_li, li_o2)
            )
            or (
              v_li.product_id is not null
              and o2.product_id = v_li.product_id
            )
            or (
              v_li.checkout_product_id is not null
              and o2.product_id = v_li.checkout_product_id
            )
          )
      );
  end if;

  v_available := greatest(
    v_total - v_blocked - v_reserved_accepted - v_pending_bag - v_sold_converted,
    0
  );
  if v_sold_converted >= greatest(v_total, 1) then
    v_available := 0;
  elsif coalesce(v_li.status, '') = 'sold' then
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
    'cross_reserved_qty', v_blocked_cross_res,
    'live_status', v_live.status,
    'price', v_unit_price
  );
end;
$$;

revoke all on function public.batata_live_item_stock(uuid) from public;
grant execute on function public.batata_live_item_stock(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Draft live + prep upsert
-- ---------------------------------------------------------------------------
create or replace function public.batata_ensure_draft_live(p_seller_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_seller_id is null or auth.uid() is distinct from p_seller_id then
    raise exception 'not_allowed';
  end if;

  select l.id into v_id
  from public.lives l
  where coalesce(l.seller_id, l.vendedor_id) = p_seller_id
    and l.status = 'draft'
    and l.is_active = false
  order by l.created_at desc
  limit 1;

  if v_id is not null then
    return v_id;
  end if;

  insert into public.lives (title, status, seller_id, vendedor_id, is_active)
  values ('Directo (preparação)', 'draft', p_seller_id, p_seller_id, false)
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.batata_ensure_draft_live(uuid) from public;
grant execute on function public.batata_ensure_draft_live(uuid) to authenticated;

-- Primeira foto de products.image_urls (text[] ou jsonb legado).
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

create or replace function public.batata_remove_marketplace_live_item(
  p_seller_id uuid,
  p_product_id uuid,
  p_live_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_live_id uuid;
begin
  if p_seller_id is null or auth.uid() is distinct from p_seller_id then
    raise exception 'not_allowed';
  end if;

  v_live_id := coalesce(
    p_live_id,
    (
      select l.id from public.lives l
      where coalesce(l.seller_id, l.vendedor_id) = p_seller_id
        and l.status = 'draft'
        and l.is_active = false
      order by l.created_at desc
      limit 1
    )
  );

  if v_live_id is null then
    return false;
  end if;

  delete from public.live_items
  where live_id = v_live_id and product_id = p_product_id;

  return true;
end;
$$;

revoke all on function public.batata_remove_marketplace_live_item(uuid, uuid, uuid) from public;
grant execute on function public.batata_remove_marketplace_live_item(uuid, uuid, uuid) to authenticated;

-- batata_upsert_live_only_item — canónico em ref_histories_batata.sql (Z10 inherit + remaining_qty).
-- Não duplicar aqui: um deploy deste ficheiro após ref_histories não deve sobrescrever o upsert.

create or replace function public.batata_migrate_live_catalog(
  p_from_live_id uuid,
  p_to_live_id uuid,
  p_seller_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n integer := 0;
begin
  if p_seller_id is null or auth.uid() is distinct from p_seller_id then
    raise exception 'not_allowed';
  end if;

  update public.live_items
  set live_id = p_to_live_id, updated_at = now()
  where live_id = p_from_live_id;

  get diagnostics v_n = row_count;

  delete from public.lives
  where id = p_from_live_id and status = 'draft';

  return v_n;
end;
$$;

revoke all on function public.batata_migrate_live_catalog(uuid, uuid, uuid) from public;
grant execute on function public.batata_migrate_live_catalog(uuid, uuid, uuid) to authenticated;

-- Colunas usadas pelo shadow live (se ainda não existirem).
alter table public.products add column if not exists quantity integer default 1;
alter table public.products add column if not exists is_sold boolean default false;

-- TYPE B checkout shadow product (B1)
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

-- Checkout comprador: shadow `list_on_marketplace=false` não é legível via RLS em `products`.
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
    'item_kind', v_li.item_kind,
    'description', coalesce(nullif(trim(v_p.description), ''), ''),
    'clothing_size', coalesce(
      nullif(trim(v_li.clothing_size), ''),
      nullif(trim(v_p.clothing_size), '')
    ),
    'gender', coalesce(
      nullif(trim(v_li.gender), ''),
      nullif(trim(v_p.gender), '')
    )
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

-- ---------------------------------------------------------------------------
-- 5) Update live item (seller / helper) — V1 price pending
-- ---------------------------------------------------------------------------
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

drop function if exists public.batata_update_live_item(uuid, integer, numeric, text, text, text, text, text);

create or replace function public.batata_update_live_item(
  p_live_item_id uuid,
  p_quantity integer default null,
  p_price numeric default null,
  p_title text default null,
  p_clothing_size text default null,
  p_gender text default null,
  p_ref_code text default null,
  p_photo_url text default null,
  p_description text default null,
  p_list_on_marketplace boolean default null
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
  v_pid uuid;
  v_eff_title text;
  v_eff_price numeric;
  v_eff_desc text;
  v_eff_photo text;
  v_eff_size text;
  v_eff_gender text;
  v_images text[];
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

  if coalesce(p_list_on_marketplace, false) is true then
    v_eff_title := coalesce(nullif(trim(p_title), ''), v_li.title);
    v_eff_price := coalesce(p_price, v_li.price);
    v_eff_photo := coalesce(nullif(trim(p_photo_url), ''), v_li.photo_url);
    v_eff_size := coalesce(nullif(trim(p_clothing_size), ''), v_li.clothing_size);
    v_eff_gender := coalesce(nullif(trim(p_gender), ''), v_li.gender);
    v_eff_desc := null;
    v_images := null;

    if v_li.product_id is not null then
      select
        coalesce(nullif(trim(p_description), ''), p.description),
        p.image_urls
      into v_eff_desc, v_images
      from public.products p
      where p.id = v_li.product_id;
    elsif v_li.checkout_product_id is not null then
      select
        coalesce(nullif(trim(p_description), ''), p.description),
        p.image_urls
      into v_eff_desc, v_images
      from public.products p
      where p.id = v_li.checkout_product_id;
    end if;

    if p_description is not null then
      v_eff_desc := nullif(trim(p_description), '');
    end if;

    if (v_eff_photo is null or trim(v_eff_photo) = '')
       and v_images is not null
       and coalesce(array_length(v_images, 1), 0) > 0 then
      v_eff_photo := nullif(trim(v_images[1]), '');
    end if;

    if v_eff_title is null or trim(v_eff_title) = '' then
      return jsonb_build_object('ok', false, 'error', 'marketplace_missing_title');
    end if;
    if v_eff_price is null or v_eff_price < 1 then
      return jsonb_build_object('ok', false, 'error', 'marketplace_missing_price');
    end if;
    if v_eff_desc is null or trim(v_eff_desc) = '' then
      return jsonb_build_object('ok', false, 'error', 'marketplace_missing_description');
    end if;
    if v_eff_photo is null or trim(v_eff_photo) = '' then
      return jsonb_build_object('ok', false, 'error', 'marketplace_missing_photo');
    end if;
    if coalesce(nullif(trim(v_eff_size), ''), nullif(trim(v_eff_gender), '')) is not null then
      if v_eff_size is null or trim(v_eff_size) = '' then
        return jsonb_build_object('ok', false, 'error', 'marketplace_missing_size');
      end if;
      if v_eff_gender is null or trim(v_eff_gender) = '' then
        return jsonb_build_object('ok', false, 'error', 'marketplace_missing_color');
      end if;
    end if;
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
      description = case when p_description is not null then nullif(trim(p_description), '') else description end,
      clothing_size = case when p_clothing_size is not null then nullif(trim(p_clothing_size), '') else clothing_size end,
      gender = case when p_gender is not null then nullif(trim(p_gender), '') else gender end,
      list_on_marketplace = case
        when p_list_on_marketplace is not null then p_list_on_marketplace
        else list_on_marketplace
      end
    where id = v_li.product_id;

    update public.live_items
    set
      title = coalesce(nullif(trim(p_title), ''), title),
      price = coalesce(p_price, price),
      clothing_size = case when p_clothing_size is not null then nullif(trim(p_clothing_size), '') else clothing_size end,
      gender = case when p_gender is not null then nullif(trim(p_gender), '') else gender end,
      photo_url = case
        when p_photo_url is not null then nullif(trim(p_photo_url), '')
        else photo_url
      end,
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
      photo_url = case
        when p_photo_url is not null then nullif(trim(p_photo_url), '')
        else photo_url
      end,
      updated_at = now()
    where id = v_li.id;

    if coalesce(v_li.logical_item_id, v_li.id) is not null then
      perform public.batata_ensure_ref_history(
        v_seller,
        coalesce(v_li.logical_item_id, v_li.id),
        coalesce(
          (select ref_code from public.live_items where id = v_li.id),
          v_li.ref_code,
          ''
        ),
        (select title from public.live_items where id = v_li.id),
        (select photo_url from public.live_items where id = v_li.id),
        'history_updated'
      );
    end if;

    if v_li.checkout_product_id is not null then
      update public.products
      set
        quantity = case when p_quantity is not null then v_qty else quantity end,
        price = case when p_price is not null then p_price else price end,
        title = coalesce(nullif(trim(p_title), ''), title),
        description = case when p_description is not null then nullif(trim(p_description), '') else description end,
        clothing_size = case when p_clothing_size is not null then nullif(trim(p_clothing_size), '') else clothing_size end,
        gender = case when p_gender is not null then nullif(trim(p_gender), '') else gender end,
        list_on_marketplace = case
          when p_list_on_marketplace is not null then p_list_on_marketplace
          else list_on_marketplace
        end
      where id = v_li.checkout_product_id;
    elsif p_list_on_marketplace is true then
      v_pid := public.batata_ensure_checkout_product(v_li.id);
      update public.products
      set
        quantity = case when p_quantity is not null then v_qty else quantity end,
        price = case when p_price is not null then p_price else price end,
        title = coalesce(nullif(trim(p_title), ''), title),
        description = case when p_description is not null then nullif(trim(p_description), '') else description end,
        clothing_size = case when p_clothing_size is not null then nullif(trim(p_clothing_size), '') else clothing_size end,
        gender = case when p_gender is not null then nullif(trim(p_gender), '') else gender end,
        list_on_marketplace = true,
        is_sold = false
      where id = v_pid;
    end if;
  end if;

  perform public.batata_recompute_live_item_status(v_li.id);

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

revoke all on function public.batata_update_live_item(uuid, integer, numeric, text, text, text, text, text, text, boolean) from public;
grant execute on function public.batata_update_live_item(uuid, integer, numeric, text, text, text, text, text, text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 6) FIX reservation RPC — stock via batata_live_item_total_qty
-- ---------------------------------------------------------------------------
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

  update public.live_items
  set status = v_next_status, updated_at = now()
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

-- ---------------------------------------------------------------------------
-- 7) Backfill existente (best-effort)
-- ---------------------------------------------------------------------------
update public.live_items li
set
  item_kind = 'marketplace_product',
  product_id = p.id,
  quantity = null,
  updated_at = now()
from public.lives l
join public.products p
  on p.seller_id = coalesce(l.seller_id, l.vendedor_id)
where li.live_id = l.id
  and li.product_id is null
  and public.batata_normalize_ref(li.ref_code) <> ''
  and public.batata_normalize_ref(p.ref_code) = public.batata_normalize_ref(li.ref_code);

update public.live_items
set
  item_kind = 'live_only',
  quantity = greatest(coalesce(quantity, 1), 1),
  updated_at = now()
where product_id is null
  and item_kind = 'live_only'
  and quantity is null;

-- ---------------------------------------------------------------------------
-- 8) RLS — draft lives visíveis ao vendedor/colaborador
-- ---------------------------------------------------------------------------
drop policy if exists "live_items_select_for_live" on public.live_items;
create policy "live_items_select_for_live"
  on public.live_items
  for select
  using (
    exists (
      select 1
      from public.lives l
      where l.id = live_id
        and (
          l.status in ('live', 'ended', 'draft')
          or l.is_active = true
          or auth.uid() = l.seller_id
          or auth.uid() = l.vendedor_id
          or public.batata_staff_has_permission(
            coalesce(l.seller_id, l.vendedor_id),
            'can_view_live_dashboard'
          )
        )
    )
  );

-- ---------------------------------------------------------------------------
-- 7) Marcar item vendido (TYPE A → products; TYPE B → live_items.quantity)
-- ---------------------------------------------------------------------------
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

revoke all on function public.batata_mark_live_item_sold(uuid) from public;
grant execute on function public.batata_mark_live_item_sold(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 9) Realtime — vitrine/stock no comprador (Z21/Z9.1)
-- ---------------------------------------------------------------------------
do $$
begin
  alter publication supabase_realtime add table public.live_items;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.live_item_show_events;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.orders;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.live_reservation_requests;
exception
  when duplicate_object then null;
end $$;
