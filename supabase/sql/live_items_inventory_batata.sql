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
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return 0;
  end if;

  if coalesce(v_li.status, '') = 'sold' then
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

  v_available := v_total - v_blocked;
  if coalesce(v_li.status, '') = 'sold' then
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

create or replace function public.batata_upsert_live_only_item(
  p_seller_id uuid,
  p_ref_code text,
  p_title text default null,
  p_price numeric default null,
  p_quantity integer default 1,
  p_clothing_size text default null,
  p_gender text default null,
  p_photo_url text default null,
  p_live_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_live_id uuid;
  v_item_id uuid;
  v_ref text;
  v_norm text;
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

  select li.id into v_item_id
  from public.live_items li
  where li.live_id = v_live_id
    and li.item_kind = 'live_only'
    and public.batata_normalize_ref(li.ref_code) = v_norm
  limit 1;

  if v_item_id is not null then
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
  else
    insert into public.live_items (
      live_id, item_kind, product_id, ref_code, title, price, photo_url,
      quantity, clothing_size, gender, is_active, status, updated_at
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
      now()
    )
    returning id into v_item_id;
  end if;

  return v_item_id;
end;
$$;

revoke all on function public.batata_upsert_live_only_item(uuid, text, text, numeric, integer, text, text, text, uuid) from public;
grant execute on function public.batata_upsert_live_only_item(uuid, text, text, numeric, integer, text, text, text, uuid) to authenticated;

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
  v_img jsonb;
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    raise exception 'live_item_not_found';
  end if;

  if v_li.checkout_product_id is not null then
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

  v_img := case
    when v_li.photo_url is not null and trim(v_li.photo_url) <> ''
    then jsonb_build_array(v_li.photo_url)
    else '[]'::jsonb
  end;

  insert into public.products (
    seller_id, title, price, image_urls, ref_code,
    list_on_marketplace, available_for_live, quantity, is_sold
  )
  values (
    v_seller,
    coalesce(nullif(trim(v_li.title), ''), 'Artigo live'),
    coalesce(v_li.price, 0),
    v_img,
    coalesce(nullif(trim(v_li.ref_code), ''), 'LIVE-' || left(v_li.id::text, 8)),
    false,
    false,
    greatest(coalesce(v_li.quantity, 1), 1),
    false
  )
  returning id into v_pid;

  update public.live_items
  set checkout_product_id = v_pid, updated_at = now()
  where id = v_li.id;

  return v_pid;
end;
$$;

revoke all on function public.batata_ensure_checkout_product(uuid) from public;
grant execute on function public.batata_ensure_checkout_product(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5) Update live item (seller / helper)
-- ---------------------------------------------------------------------------
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
    -- ref_code intentionally NOT updated for TYPE A
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

  return public.batata_live_item_stock(v_li.id);
end;
$$;

revoke all on function public.batata_update_live_item(uuid, integer, numeric, text, text, text, text) from public;
grant execute on function public.batata_update_live_item(uuid, integer, numeric, text, text, text, text) to authenticated;

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
