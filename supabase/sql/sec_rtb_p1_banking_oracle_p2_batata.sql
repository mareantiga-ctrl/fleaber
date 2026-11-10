-- =============================================================================
-- Red Team Cego B — FAIL_P1 fixes (staging only)
-- RTB-P1-BANKING-ORACLE + P2 email / reviews verified / storage chat enum
-- PRODUÇÃO NÃO. FASE 4 NÃO.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- P1) batata_seller_direct_payment_details — autoridade NÃO fabricável
-- Relação autoritativa = order off-platform com produto do seller
--   OU order ligada a bundle accepted/purchased.
-- Bundle pending (mesmo com produtos reais) NÃO autoriza.
-- ---------------------------------------------------------------------------
create or replace function public.batata_seller_direct_payment_details(p_seller_id uuid)
returns table (mb_way text, iban text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer uuid := auth.uid();
  v_ok boolean := false;
begin
  if v_buyer is null then
    raise exception 'Não autenticado.';
  end if;
  if p_seller_id is null then
    return;
  end if;

  if p_seller_id = v_buyer then
    v_ok := true;
  else
    select exists (
      select 1
      from public.orders o
      where o.seller_id = p_seller_id
        and o.buyer_id = v_buyer
        and public.batata_is_off_platform_payment(o.payment_method)
        and lower(trim(coalesce(o.status, ''))) not in (
          'cancelado', 'cancelled', 'refunded', 'reembolsado'
        )
        and (
          (
            o.product_id is not null
            and exists (
              select 1
              from public.products p
              where p.id = o.product_id
                and p.seller_id = p_seller_id
            )
          )
          or (
            o.bundle_id is not null
            and exists (
              select 1
              from public.product_bundles b
              where b.id = o.bundle_id
                and b.seller_id = p_seller_id
                and b.buyer_id = v_buyer
                and lower(trim(coalesce(b.status, ''))) in (
                  'accepted', 'purchased'
                )
            )
          )
        )
    ) into v_ok;
  end if;

  if not v_ok then
    return;
  end if;

  return query
  select p.mb_way::text, p.iban::text
  from public.profiles p
  where p.id = p_seller_id
    and coalesce(p.external_payments_enabled, false) = true;
end;
$$;

comment on function public.batata_seller_direct_payment_details(uuid) is
  'RTB-P1: IBAN/MB WAY só com order off-platform + produto do seller OU bundle aceite; pending NÃO autoriza.';

revoke all on function public.batata_seller_direct_payment_details(uuid) from public, anon;
grant execute on function public.batata_seller_direct_payment_details(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- P1b) product_bundles — INSERT coerente (produtos do seller; parties)
-- ---------------------------------------------------------------------------
create or replace function public.batata_product_bundles_guard_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_bad int := 0;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    if NEW.seller_id is not null and NEW.seller_id = v_uid then
      NEW.seller_id := v_uid;
      if NEW.buyer_id is null or NEW.buyer_id = v_uid then
        raise exception 'bundle_invalid_buyer' using errcode = '23514';
      end if;
    elsif NEW.buyer_id is null or NEW.buyer_id = v_uid then
      NEW.buyer_id := v_uid;
      if NEW.seller_id is null or NEW.seller_id = v_uid then
        raise exception 'bundle_invalid_seller' using errcode = '23514';
      end if;
      NEW.status := 'pending';
    else
      raise exception 'bundle_party_mismatch' using errcode = '42501';
    end if;

    if NEW.buyer_id = NEW.seller_id then
      raise exception 'bundle_same_party' using errcode = '23514';
    end if;

    if NEW.product_ids is null or coalesce(array_length(NEW.product_ids, 1), 0) < 1 then
      raise exception 'bundle_products_required' using errcode = '23514';
    end if;

    select count(*)::int into v_bad
    from unnest(NEW.product_ids) as pid
    where not exists (
      select 1 from public.products p
      where p.id = pid and p.seller_id = NEW.seller_id
    );
    if v_bad > 0 then
      raise exception 'bundle_product_seller_mismatch' using errcode = '23514';
    end if;
  end if;

  if TG_OP = 'UPDATE' then
    NEW.buyer_id := OLD.buyer_id;
    NEW.seller_id := OLD.seller_id;
    NEW.product_ids := OLD.product_ids;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_product_bundles_guard_write on public.product_bundles;
create trigger trg_batata_product_bundles_guard_write
  before insert or update on public.product_bundles
  for each row
  execute function public.batata_product_bundles_guard_write();

comment on function public.batata_product_bundles_guard_write() is
  'RTB-P1: parties + produtos do seller; buyer INSERT só pending; parties/product_ids imutáveis no UPDATE.';

-- ---------------------------------------------------------------------------
-- P2) email → UUID: só sellers (convites helper) — preserva SellerStaffService
-- ---------------------------------------------------------------------------
create or replace function public.batata_find_user_id_by_email(p_email text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(coalesce(p_email, '')));
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
  v_found uuid;
  v_is_seller boolean := false;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if v_email = '' or position('@' in v_email) = 0 or char_length(v_email) > 320 then
    return null;
  end if;

  select exists (
    select 1 from public.profiles p
    where p.id = v_uid
      and lower(trim(coalesce(p.user_type, ''))) in ('vendedor', 'seller')
  ) into v_is_seller;

  if not v_is_seller then
    return null;
  end if;

  insert into public.batata_rpc_rate_limits (uid, rpc, window_start, hits)
  values (v_uid, 'batata_find_user_id_by_email', v_window, 1)
  on conflict (uid, rpc, window_start)
  do update set hits = public.batata_rpc_rate_limits.hits + 1
  returning hits into v_hits;

  if v_hits > 30 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  select u.id
  into v_found
  from auth.users u
  where lower(trim(u.email)) = v_email
  limit 1;

  return v_found;
end;
$$;

comment on function public.batata_find_user_id_by_email(text) is
  'RTB-P2: email→UUID só para contas vendedor (convites staff); rate limit 30/h.';

revoke all on function public.batata_find_user_id_by_email(text) from public, anon;
grant execute on function public.batata_find_user_id_by_email(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- P2) reviews — purchase_verified distingue plataforma vs off-platform
-- Classificação: comportamento intencional com risco excessivo.
-- Mantém review off-platform possível; marca purchase_verified=false.
-- ---------------------------------------------------------------------------
alter table public.reviews
  add column if not exists purchase_verified boolean not null default false;

comment on column public.reviews.purchase_verified is
  'true = pagamento verificado na plataforma (captura Fleaber/Stripe); false = off-platform/outro.';

create or replace function public.batata_reviews_guard_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_order public.orders%rowtype;
  v_verified boolean := false;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    NEW.author_role := public.batata_review_author_role_canonical(NEW.author_role);
    if NEW.order_id is not null then
      select * into v_order from public.orders where id = NEW.order_id;
      if found then
        v_verified :=
          not public.batata_is_off_platform_payment(v_order.payment_method)
          and (
            coalesce(v_order.amount_paid_cents, 0) > 0
            or nullif(trim(coalesce(v_order.stripe_payment_intent_id, '')), '') is not null
          );
      end if;
    end if;
    NEW.purchase_verified := v_verified;
    return NEW;
  end if;

  NEW.buyer_id := v_uid;
  NEW.is_automatic := false;
  NEW.author_role := 'comprador';

  if NEW.order_id is null then
    raise exception 'review_order_required' using errcode = '23514';
  end if;

  select * into v_order from public.orders where id = NEW.order_id;
  if not found or v_order.buyer_id is distinct from v_uid then
    raise exception 'review_order_not_yours' using errcode = '42501';
  end if;

  if lower(coalesce(v_order.status, '')) not in ('concluido', 'entregue') then
    raise exception 'review_order_invalid_status' using errcode = '23514';
  end if;

  if not public.batata_order_payment_confirmed(
       v_order.payment_method,
       v_order.status,
       v_order.amount_paid_cents,
       v_order.stripe_payment_intent_id
     ) then
    raise exception 'review_order_unpaid' using errcode = '23514';
  end if;

  if public.batata_is_off_platform_payment(v_order.payment_method)
     and coalesce(v_order.stock_units_applied, 0) <= 0
     and coalesce(v_order.amount_paid_cents, 0) <= 0 then
    raise exception 'review_order_unpaid' using errcode = '23514';
  end if;

  NEW.target_id := v_order.seller_id;

  v_verified :=
    not public.batata_is_off_platform_payment(v_order.payment_method)
    and (
      coalesce(v_order.amount_paid_cents, 0) > 0
      or nullif(trim(coalesce(v_order.stripe_payment_intent_id, '')), '') is not null
    );
  NEW.purchase_verified := v_verified;

  if exists (
    select 1 from public.reviews r
    where r.order_id = NEW.order_id
      and r.buyer_id = v_uid
      and public.batata_review_author_role_canonical(r.author_role) = 'comprador'
  ) then
    raise exception 'review_duplicate' using errcode = '23505';
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_reviews_guard_insert on public.reviews;
create trigger trg_batata_reviews_guard_insert
  before insert on public.reviews
  for each row
  execute function public.batata_reviews_guard_insert();

comment on function public.batata_reviews_guard_insert() is
  'C1+RTB-P2: JWT comprador; purchase_verified só com captura plataforma.';

create or replace function public.batata_reviews_guard_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  NEW.stars := OLD.stars;
  NEW.comment := OLD.comment;
  NEW.is_automatic := OLD.is_automatic;
  NEW.order_id := OLD.order_id;
  NEW.buyer_id := OLD.buyer_id;
  NEW.target_id := OLD.target_id;
  NEW.author_role := OLD.author_role;
  NEW.purchase_verified := OLD.purchase_verified;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_reviews_guard_update on public.reviews;
create trigger trg_batata_reviews_guard_update
  before update on public.reviews
  for each row
  execute function public.batata_reviews_guard_update();

drop trigger if exists trg_batata_reviews_guard_update_verified on public.reviews;

-- Backfill: reviews já existentes com captura plataforma
update public.reviews r
set purchase_verified = true
from public.orders o
where r.order_id = o.id
  and coalesce(r.purchase_verified, false) = false
  and not public.batata_is_off_platform_payment(o.payment_method)
  and (
    coalesce(o.amount_paid_cents, 0) > 0
    or nullif(trim(coalesce(o.stripe_payment_intent_id, '')), '') is not null
  );

create or replace view public.reviews_public_ratings
as
select
  id,
  created_at,
  target_id,
  stars,
  comment,
  is_automatic,
  target_type,
  author_role,
  purchase_verified
from public.reviews;

alter view public.reviews_public_ratings set (security_invoker = false);
revoke all on public.reviews_public_ratings from public;
grant select on public.reviews_public_ratings to anon, authenticated, service_role;

comment on view public.reviews_public_ratings is
  'Reputação pública; purchase_verified distingue compra plataforma vs off-platform.';

-- ---------------------------------------------------------------------------
-- P2) storage chat_media — sem listar/ler chat_uploads de terceiros via API
-- Bucket continua public=true (CDN conhecido residual — ver relatório).
-- Não enfraquece order_proofs / order_disputes.
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select policyname
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'chat_media_public_select',
        'chat_media_public_catalog_select',
        'chat_media_chat_uploads_own_select'
      )
  loop
    execute format('drop policy if exists %I on storage.objects', r.policyname);
  end loop;
end $$;

create policy chat_media_public_catalog_select
  on storage.objects
  for select
  using (
    bucket_id = 'chat_media'
    and (
      name like 'product_photos/%'
      or name like 'profile_photos/%'
      or name like 'live_item_photos/%'
      or name like 'live_raffle_prize/%'
    )
  );

create policy chat_media_chat_uploads_own_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'chat_media'
    and auth.uid() is not null
    and name like ('chat_uploads/' || auth.uid()::text || '/%')
  );

drop policy if exists chat_media_proofs_owner_select on storage.objects;
create policy chat_media_proofs_owner_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'chat_media'
    and (
      name like 'order_proofs/%'
      or name like 'order_disputes/%'
    )
    and auth.uid() is not null
    and position(auth.uid()::text in name) > 0
  );

notify pgrst, 'reload schema';
