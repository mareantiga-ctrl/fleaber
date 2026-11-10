-- =============================================================================
-- C2-P2-01 + C2-P2-02 (staging only). NÃO Fase 4. PRODUÇÃO NÃO.
-- 01: coerência orders LIVE (live_id ↔ live_item ↔ product ↔ seller)
-- 02: banking details só após aceitação (não reserva_pendente)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Helper reutilizável (INSERT / UPDATE / Edge via mesma regra mental)
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_assert_live_coherence(
  p_live_id uuid,
  p_live_item_id uuid,
  p_product_id uuid,
  p_seller_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_li public.live_items%rowtype;
  v_live_seller uuid;
  v_prod_seller uuid;
begin
  -- Marketplace / sem contexto LIVE: não inventar dependência.
  if p_live_item_id is null and p_live_id is null then
    return;
  end if;

  -- live_id sem live_item: live tem de existir; seller alinhado à live.
  if p_live_item_id is null and p_live_id is not null then
    select l.seller_id into v_live_seller
    from public.lives l
    where l.id = p_live_id;
    if not found then
      raise exception 'order_live_not_found' using errcode = '23514';
    end if;
    if p_seller_id is not null
       and v_live_seller is not null
       and p_seller_id is distinct from v_live_seller then
      raise exception 'order_live_seller_mismatch' using errcode = '23514';
    end if;
    return;
  end if;

  select * into v_li
  from public.live_items li
  where li.id = p_live_item_id;
  if not found then
    raise exception 'order_live_item_not_found' using errcode = '23514';
  end if;

  if p_live_id is not null and p_live_id is distinct from v_li.live_id then
    raise exception 'order_live_item_live_mismatch' using errcode = '23514';
  end if;

  if p_product_id is not null then
    if coalesce(v_li.product_id, v_li.checkout_product_id) is null then
      raise exception 'order_live_item_product_missing' using errcode = '23514';
    end if;
    if p_product_id is distinct from v_li.product_id
       and p_product_id is distinct from v_li.checkout_product_id then
      raise exception 'order_live_item_product_mismatch' using errcode = '23514';
    end if;
  end if;

  if p_seller_id is not null then
    if v_li.seller_id is not null
       and p_seller_id is distinct from v_li.seller_id then
      raise exception 'order_live_item_seller_mismatch' using errcode = '23514';
    end if;
    if p_product_id is not null then
      select p.seller_id into v_prod_seller
      from public.products p
      where p.id = p_product_id;
      if not found then
        raise exception 'order_product_not_found' using errcode = '23514';
      end if;
      if p_seller_id is distinct from v_prod_seller then
        raise exception 'order_product_seller_mismatch' using errcode = '23514';
      end if;
    end if;
  end if;
end;
$fn$;

revoke all on function public.batata_orders_assert_live_coherence(uuid, uuid, uuid, uuid)
  from public, anon;
grant execute on function public.batata_orders_assert_live_coherence(uuid, uuid, uuid, uuid)
  to authenticated, service_role;

comment on function public.batata_orders_assert_live_coherence(uuid, uuid, uuid, uuid) is
  'C2-P2-01: live_id/live_item/product/seller coerentes; sem LIVE = no-op.';

-- ---------------------------------------------------------------------------
-- Trigger: coerência + imutabilidade de contexto LIVE / product / seller
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_live_coherence()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_jwt boolean := (v_role = 'authenticated' and v_uid is not null);
begin
  if TG_OP = 'UPDATE' and v_jwt then
    -- Buyer/seller JWT não reescrevem a relação comercial.
    NEW.live_id := OLD.live_id;
    NEW.live_item_id := OLD.live_item_id;
    NEW.product_id := OLD.product_id;
    NEW.seller_id := OLD.seller_id;
  end if;

  -- Derivar live_id do item quando em falta (evita orphan item sem live).
  if NEW.live_item_id is not null and NEW.live_id is null then
    select li.live_id into NEW.live_id
    from public.live_items li
    where li.id = NEW.live_item_id;
  end if;

  perform public.batata_orders_assert_live_coherence(
    NEW.live_id,
    NEW.live_item_id,
    NEW.product_id,
    NEW.seller_id
  );

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_live_coherence on public.orders;
drop trigger if exists trg_batata_orders_guard_live_coherence_ins on public.orders;
create trigger trg_batata_orders_guard_live_coherence
  before insert or update on public.orders
  for each row
  execute function public.batata_orders_guard_live_coherence();

comment on function public.batata_orders_guard_live_coherence() is
  'C2-P2-01: assert LIVE + congela live/product/seller no UPDATE JWT.';

-- ---------------------------------------------------------------------------
-- C2-P2-02: banking só em estados pós-aceitação (comprador a pagar)
-- Produto: MB WAY cria reserva_pendente; após seller accept → reservado + dados.
-- ---------------------------------------------------------------------------
create or replace function public.batata_order_status_allows_direct_payment_reveal(
  p_status text
)
returns boolean
language sql
immutable
as $$
  select lower(trim(coalesce(p_status, ''))) in (
    'reservado',
    'aguarda_confirmacao',
    'aguarda_pagamento'
  );
$$;

revoke all on function public.batata_order_status_allows_direct_payment_reveal(text)
  from public, anon;
grant execute on function public.batata_order_status_allows_direct_payment_reveal(text)
  to authenticated, service_role;

comment on function public.batata_order_status_allows_direct_payment_reveal(text) is
  'C2-P2-02: estados em que o comprador precisa de IBAN/MB WAY (pós-aceitação).';

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

  -- Próprio perfil (edição / preview)
  if p_seller_id = v_buyer then
    v_ok := true;
  else
    -- Relação autoritativa: order off-platform + parties + estado pós-aceitação
    -- + produto do seller OU bundle accepted/purchased.
    -- reserva_pendente / waitlist / Stripe NÃO autorizam.
    select exists (
      select 1
      from public.orders o
      where o.seller_id = p_seller_id
        and o.buyer_id = v_buyer
        and public.batata_is_off_platform_payment(o.payment_method)
        and public.batata_order_status_allows_direct_payment_reveal(o.status)
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
  'C2-P2-02: IBAN/MB WAY só off-platform + status reservado/aguarda_* (não reserva_pendente).';

revoke all on function public.batata_seller_direct_payment_details(uuid) from public, anon;
grant execute on function public.batata_seller_direct_payment_details(uuid) to authenticated;

notify pgrst, 'reload schema';
