-- =============================================================================
-- NOVA AUDITORIA CEGA 2026-08-27 — P1/P2 hardenings (staging only)
-- Idempotente. NÃO é Fase 4.
-- Corrige: order↔ product seller · chat parties · wallet GRANT drift ·
-- requested_qty · batata_is_admin higiene · pin de privileges.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- P2-01 / P2-02 / P1-03 — REVOKE explícito de authenticated (antes falhava)
-- ---------------------------------------------------------------------------
revoke all on function public.batata_debit_wallet_once(uuid, uuid, numeric, text)
  from public, anon, authenticated;
grant execute on function public.batata_debit_wallet_once(uuid, uuid, numeric, text)
  to service_role;

revoke all on function public.batata_clawback_seller_wallet_for_order(uuid)
  from public, anon, authenticated;
grant execute on function public.batata_clawback_seller_wallet_for_order(uuid)
  to service_role;

revoke all on function public.batata_credit_wallet_once(uuid, uuid, numeric, text, text)
  from public, anon, authenticated;
grant execute on function public.batata_credit_wallet_once(uuid, uuid, numeric, text, text)
  to service_role;

-- ensure_wallet: JWT não deve criar wallet alheia via RPC directa.
revoke all on function public.batata_ensure_wallet(uuid)
  from public, anon, authenticated;
grant execute on function public.batata_ensure_wallet(uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- P1-01 — order.product deve pertencer a order.seller (INSERT + UPDATE)
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_product_seller()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_product_seller uuid;
begin
  if NEW.product_id is null then
    return NEW;
  end if;

  select p.seller_id into v_product_seller
  from public.products p
  where p.id = NEW.product_id;

  if not found then
    raise exception 'order_product_not_found'
      using errcode = '23514';
  end if;

  if NEW.seller_id is null then
    -- Preenche seller a partir do produto (evita orders órfãs).
    NEW.seller_id := v_product_seller;
  elsif NEW.seller_id is distinct from v_product_seller then
    raise exception 'order_product_seller_mismatch'
      using errcode = '23514',
            hint = 'order.seller_id must equal products.seller_id for product_id';
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_product_seller on public.orders;
create trigger trg_batata_orders_guard_product_seller
  before insert or update of product_id, seller_id
  on public.orders
  for each row
  execute function public.batata_orders_guard_product_seller();

comment on function public.batata_orders_guard_product_seller() is
  'AUD 2026-08-27: impede order.seller ≠ product.seller (stock/wallet hijack).';

-- Stock trigger: só consome produto do seller da order
create or replace function public.batata_mark_product_sold_on_paid_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_units int;
  v_before int;
  v_remaining int;
  v_claimed int;
  v_stock_rows int;
  v_product_seller uuid;
begin
  if new.product_id is null then
    return new;
  end if;

  if lower(coalesce(new.status, '')) <> 'pago' then
    return new;
  end if;

  if new.stock_units_applied is not null then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and lower(coalesce(old.status, '')) is not distinct from lower(coalesce(new.status, '')) then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and lower(coalesce(old.status, '')) = 'premio_rifa' then
    return new;
  end if;

  select p.seller_id into v_product_seller
  from public.products p
  where p.id = new.product_id
  for update;

  if v_product_seller is distinct from new.seller_id then
    raise exception 'batata_stock_seller_mismatch'
      using errcode = 'P0001',
            hint = 'order=' || new.id::text || ' product=' || new.product_id::text;
  end if;

  v_units := greatest(coalesce(new.quantity, 1), 1);

  update public.orders
     set stock_units_applied = v_units
   where id = new.id
     and stock_units_applied is null;
  get diagnostics v_claimed = row_count;
  if v_claimed = 0 then
    return new;
  end if;

  select quantity into v_before
  from public.products
  where id = new.product_id;

  update public.products
     set quantity = quantity - v_units
   where id = new.product_id
     and seller_id = new.seller_id
     and coalesce(quantity, 0) >= v_units
   returning quantity into v_remaining;
  get diagnostics v_stock_rows = row_count;

  if v_stock_rows = 0 then
    raise exception 'batata_stock_insufficient'
      using errcode = 'P0001',
            hint = 'order=' || new.id::text || ' product=' || new.product_id::text ||
                   ' units=' || v_units::text || ' qty_before=' || coalesce(v_before::text, 'null');
  end if;

  raise log 'BATATA_STOCK order=% product=% units=% qty_before=% qty_after=%',
    new.id, new.product_id, v_units, v_before, v_remaining;

  if v_remaining is not null and v_remaining <= 0 then
    update public.products
       set is_sold = true,
           list_on_marketplace = false
     where id = new.product_id;
  elsif v_remaining is not null and v_remaining > 0 then
    update public.products
       set is_sold = false
     where id = new.product_id
       and is_sold = true;
  end if;

  return new;
end;
$$;

-- JWT: product_id também congelado pré-pago (não trocar para produto alheio)
create or replace function public.batata_orders_guard_money_cols()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_old_status text;
  v_frozen boolean := false;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    if lower(trim(coalesce(NEW.status, ''))) in (
      'pago', 'enviado', 'entregue', 'concluido', 'devolvida'
    ) then
      NEW.status := 'reserva_pendente';
    end if;
    NEW.stripe_checkout_session_id := null;
    NEW.stripe_payment_intent_id := null;
    NEW.stripe_refund_id := null;
    NEW.amount_paid_cents := null;
    return NEW;
  end if;

  if NEW.buyer_id is distinct from OLD.buyer_id then
    NEW.buyer_id := OLD.buyer_id;
  end if;
  if NEW.seller_id is distinct from OLD.seller_id then
    NEW.seller_id := OLD.seller_id;
  end if;
  -- Sempre: cliente não troca product_id (só service_role / SQL interno).
  if NEW.product_id is distinct from OLD.product_id then
    NEW.product_id := OLD.product_id;
  end if;
  if NEW.stripe_checkout_session_id is distinct from OLD.stripe_checkout_session_id then
    NEW.stripe_checkout_session_id := OLD.stripe_checkout_session_id;
  end if;
  if NEW.stripe_payment_intent_id is distinct from OLD.stripe_payment_intent_id then
    NEW.stripe_payment_intent_id := OLD.stripe_payment_intent_id;
  end if;
  if NEW.stripe_refund_id is distinct from OLD.stripe_refund_id then
    NEW.stripe_refund_id := OLD.stripe_refund_id;
  end if;
  if NEW.amount_paid_cents is distinct from OLD.amount_paid_cents then
    NEW.amount_paid_cents := OLD.amount_paid_cents;
  end if;

  v_old_status := lower(trim(coalesce(OLD.status, '')));
  v_frozen :=
    v_old_status in (
      'pago', 'enviado', 'entregue', 'concluido', 'devolvida',
      'em_devolucao', 'devolucao_entregue', 'disputa_devolucao_vendedor'
    )
    or coalesce(OLD.stripe_payment_intent_id, '') <> ''
    or coalesce(OLD.stripe_checkout_session_id, '') <> ''
    or coalesce(OLD.amount_paid_cents, 0) > 0;

  if v_frozen then
    if NEW.price_total is distinct from OLD.price_total then
      NEW.price_total := OLD.price_total;
    end if;
    if NEW.quantity is distinct from OLD.quantity then
      NEW.quantity := OLD.quantity;
    end if;
    if NEW.payment_method is distinct from OLD.payment_method then
      NEW.payment_method := OLD.payment_method;
    end if;
  end if;

  return NEW;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- P1-02 — congelar user_a / user_b em UPDATE JWT
-- ---------------------------------------------------------------------------
create or replace function public.batata_chats_guard_parties()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;

  -- service_role / SQL: sem restrição (nuke, admin).
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  NEW.user_a := OLD.user_a;
  NEW.user_b := OLD.user_b;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_chats_guard_parties on public.chats;
create trigger trg_batata_chats_guard_parties
  before update on public.chats
  for each row
  execute function public.batata_chats_guard_parties();

comment on function public.batata_chats_guard_parties() is
  'AUD 2026-08-27: participantes de chat imutáveis via JWT.';

-- RLS with check mais estrito (party columns iguais)
drop policy if exists "chats_update_participants" on public.chats;
create policy "chats_update_participants"
  on public.chats for update
  using (auth.uid() = user_a or auth.uid() = user_b)
  with check (
    (auth.uid() = user_a or auth.uid() = user_b)
    and user_a is not null
    and user_b is not null
    and user_a is distinct from user_b
  );

-- P2-08: assign_queue NÃO pode coerir 0/−1 → 1 (corria ANTES do qty_cap).
create or replace function public.batata_live_reservation_assign_queue()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if TG_OP = 'INSERT' then
    -- Fail-closed: qty inválida rejeitada (não coerir).
    if NEW.requested_qty is null or NEW.requested_qty < 1 or NEW.requested_qty > 99 then
      raise exception 'invalid_requested_qty'
        using errcode = '23514';
    end if;

    if new.source = 'facebook_manual' and new.ingest_channel is null then
      new.ingest_channel := 'manual';
    end if;

    if new.source = 'helper_manual' and new.ingest_channel is null then
      new.ingest_channel := 'helper';
    end if;

    if new.source = 'fleaber_live' and new.ingest_channel is null then
      new.ingest_channel := null;
    end if;

    if new.effective_at is null then
      new.effective_at := public.batata_reservation_effective_at(
        new.source,
        new.ingest_channel,
        coalesce(new.created_at, now()),
        new.detected_at,
        new.seller_id
      );
    end if;

    if new.source = 'facebook_manual'
      and new.ingest_channel = 'ocr'
      and new.ingest_status is null then
      if coalesce(new.ingest_confidence, 0) >= 0.85 then
        new.ingest_status := 'auto';
      else
        new.ingest_status := 'needs_review';
      end if;
    end if;

    if new.source = 'facebook_manual'
      and new.ingest_channel = 'manual'
      and new.ingest_status is null then
      new.ingest_status := 'seller_confirmed';
    end if;

    new.queue_position := null;
  end if;

  if new.status = 'pending' and new.expires_at is null then
    new.expires_at := now() + interval '45 minutes';
  end if;

  new.updated_at := now();
  return new;
end;
$function$;

create or replace function public.batata_live_reservation_qty_cap()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if NEW.requested_qty is null or NEW.requested_qty < 1 or NEW.requested_qty > 99 then
    raise exception 'invalid_requested_qty'
      using errcode = '23514';
  end if;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_live_reservation_qty_cap on public.live_reservation_requests;
create trigger trg_batata_live_reservation_qty_cap
  before insert or update of requested_qty
  on public.live_reservation_requests
  for each row
  execute function public.batata_live_reservation_qty_cap();

alter table public.live_reservation_requests
  drop constraint if exists live_reservation_requests_requested_qty_check;

alter table public.live_reservation_requests
  add constraint live_reservation_requests_requested_qty_check
  check (requested_qty >= 1 and requested_qty <= 99);

-- ---------------------------------------------------------------------------
-- P3-04 — higiene admim: manter alias legado + documentar; normalizar se tipado
-- ---------------------------------------------------------------------------
create or replace function public.batata_is_admin()
returns boolean
language sql
security definer
set search_path = public
as $batata_admin$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.user_type, '')) in (
        'admin',
        'administrador',
        'administracao',
        -- legado tipográfico (SEC-001 impede JWT promover-se a isto)
        'admim'
      )
  );
$batata_admin$;

comment on function public.batata_is_admin() is
  'Admin allowlist. Alias legado admim mantido; promoção JWT bloqueada em sec_001.';

-- ---------------------------------------------------------------------------
-- P1-03 — pin de privileges (assert): funções económicas internas
-- ---------------------------------------------------------------------------
create or replace function public.batata_assert_wallet_rpc_grants()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bad text[] := array[]::text[];
  r record;
begin
  for r in
    select p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'batata_debit_wallet_once',
        'batata_clawback_seller_wallet_for_order',
        'batata_credit_wallet_once'
      )
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  loop
    v_bad := array_append(v_bad, r.proname);
  end loop;

  return jsonb_build_object(
    'ok', coalesce(array_length(v_bad, 1), 0) = 0,
    'leaked_to_authenticated', to_jsonb(coalesce(v_bad, array[]::text[]))
  );
end;
$$;

revoke all on function public.batata_assert_wallet_rpc_grants() from public, anon, authenticated;
grant execute on function public.batata_assert_wallet_rpc_grants() to service_role;

notify pgrst, 'reload schema';
