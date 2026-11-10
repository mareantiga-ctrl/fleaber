-- =============================================================================
-- BATATA — fecho K/L/M 2026-08-31 (decisões 1A–5A)
-- K: recibo Seguro só com captura; bloquear texto legado forjado
-- L: reviews sem DELETE JWT; TTL hold congelado p/ buyer; job expira holds
-- M: resolve_handle 2A; negar list chat_media; (mux/CORS nas Edges)
-- production_touched: false · fase4: false
-- TTL hold = reservation_expires_at (app = +5 dias no aceite; NÃO 48h)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- K — chat: needs_paid apertado + bloqueio texto legado Seguro
-- ---------------------------------------------------------------------------
create or replace function public.batata_chat_messages_assert_json_card(
  p_chat_id uuid,
  p_sender_id uuid,
  p_text text
)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_raw text := coalesce(p_text, '');
  v_json jsonb;
  v_kind text;
  v_oid uuid;
  v_order_seller uuid;
  v_order_buyer uuid;
  v_order_status text;
  v_paid_cents int;
  v_pi text;
  v_chat_a uuid;
  v_chat_b uuid;
  v_needs_order boolean;
  v_needs_paid boolean;
  v_captured boolean;
begin
  if v_raw not like 'FLEABER_JSON_V1:%' then
    return;
  end if;

  begin
    v_json := substring(v_raw from length('FLEABER_JSON_V1:') + 1)::jsonb;
  exception when others then
    raise exception 'chat_system_card_invalid_json' using errcode = '23514';
  end;

  v_kind := lower(trim(coalesce(v_json->>'kind', '')));
  if v_kind = '' then
    raise exception 'chat_system_card_kind_required' using errcode = '23514';
  end if;

  if v_kind in (
    'marketplace_bag_paid',
    'auto_feedback_generated',
    'raffle_prize',
    'premio_rifa',
    'order_paid'
  ) then
    raise exception 'chat_system_card_server_only' using errcode = '42501';
  end if;

  select c.user_a, c.user_b into v_chat_a, v_chat_b
  from public.chats c
  where c.id = p_chat_id;

  if not found then
    raise exception 'chat_system_card_chat_missing' using errcode = '23514';
  end if;

  if p_sender_id is distinct from v_chat_a and p_sender_id is distinct from v_chat_b then
    raise exception 'chat_system_card_not_participant' using errcode = '42501';
  end if;

  v_needs_order := v_kind in (
    'reservation_seller_confirmed_receipt',
    'reservation_cancelled_by_seller',
    'bundle_reservation_cancelled_by_seller',
    'reservation_order_shipped',
    'reservation_accepted',
    'reservation_request_outcome',
    'price_offer_outcome',
    'cancel_request_outcome',
    'bundle_direct_payment_details',
    'order_direct_payment_details',
    'bundle_buyer_confirmed_receipt',
    'reservation_payment_submitted',
    'reservation_request',
    'reservation_order_completed',
    'cancel_request',
    'order_review_submitted',
    'seguro_fleaber_paid',
    'price_offer',
    'order_dispute_opened'
  );

  v_needs_paid := v_kind in (
    'seguro_fleaber_paid',
    'reservation_order_shipped',
    'reservation_order_completed',
    'reservation_seller_confirmed_receipt',
    'bundle_buyer_confirmed_receipt'
  );

  begin
    v_oid := nullif(trim(coalesce(v_json->>'order_id', '')), '')::uuid;
  exception when others then
    v_oid := null;
  end;

  if v_needs_order and v_oid is null then
    raise exception 'chat_system_card_order_id_required' using errcode = '23514';
  end if;

  if v_oid is not null then
    select o.seller_id, o.buyer_id, o.status,
           coalesce(o.amount_paid_cents, 0),
           coalesce(o.stripe_payment_intent_id, '')
      into v_order_seller, v_order_buyer, v_order_status, v_paid_cents, v_pi
    from public.orders o
    where o.id = v_oid;

    if not found then
      raise exception 'chat_system_card_order_missing' using errcode = '23514';
    end if;

    if not (
      (v_order_seller is not distinct from v_chat_a and v_order_buyer is not distinct from v_chat_b)
      or (v_order_seller is not distinct from v_chat_b and v_order_buyer is not distinct from v_chat_a)
    ) then
      raise exception 'chat_system_card_order_chat_mismatch' using errcode = '23514';
    end if;

    v_captured := v_paid_cents > 0 or nullif(trim(v_pi), '') is not null;

    if v_needs_paid then
      if v_kind = 'seguro_fleaber_paid' then
        -- K-P1-001: recibo Seguro = pagamento plataforma (captura), não só status pago MB WAY
        if not v_captured then
          raise exception 'chat_system_card_order_not_paid' using errcode = '23514';
        end if;
      else
        -- Cards operacionais: captura OU estado pós-pago (off-platform honesto)
        if not (
          v_captured
          or lower(trim(coalesce(v_order_status, ''))) in (
            'pago', 'enviado', 'entregue', 'concluido',
            'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
            'disputa_devolucao_vendedor', 'devolvida'
          )
        ) then
          raise exception 'chat_system_card_order_not_paid' using errcode = '23514';
        end if;
      end if;
    end if;

    if v_kind in (
      'reservation_seller_confirmed_receipt',
      'reservation_cancelled_by_seller',
      'bundle_reservation_cancelled_by_seller',
      'reservation_order_shipped',
      'reservation_accepted',
      'reservation_request_outcome',
      'price_offer_outcome',
      'cancel_request_outcome',
      'bundle_direct_payment_details',
      'order_direct_payment_details'
    ) then
      if p_sender_id is distinct from v_order_seller then
        raise exception 'chat_system_card_seller_only' using errcode = '42501';
      end if;
    end if;

    if v_kind in (
      'bundle_buyer_confirmed_receipt',
      'reservation_payment_submitted',
      'reservation_request',
      'reservation_order_completed',
      'cancel_request',
      'order_review_submitted',
      'seguro_fleaber_paid',
      'price_offer'
    ) then
      if p_sender_id is distinct from v_order_buyer then
        raise exception 'chat_system_card_buyer_only' using errcode = '42501';
      end if;
    end if;

    if v_kind in ('order_dispute_opened') then
      if p_sender_id is distinct from v_order_buyer
         and p_sender_id is distinct from v_order_seller then
        raise exception 'chat_system_card_party_only' using errcode = '42501';
      end if;
    end if;
  end if;

  if v_kind not in (
    'chat_image',
    'bundle_proposal',
    'bundle_direct_payment_details',
    'order_direct_payment_details',
    'price_offer',
    'price_offer_outcome',
    'reservation_accepted',
    'reservation_request',
    'reservation_request_outcome',
    'bundle_buyer_confirmed_receipt',
    'cancel_request',
    'cancel_request_outcome',
    'order_dispute_opened',
    'order_review_submitted',
    'reservation_cancelled_by_seller',
    'bundle_reservation_cancelled_by_seller',
    'reservation_order_completed',
    'reservation_order_shipped',
    'reservation_payment_submitted',
    'reservation_seller_confirmed_receipt',
    'seguro_fleaber_paid'
  ) then
    raise exception 'chat_system_card_kind_denied' using errcode = '42501';
  end if;
end;
$fn$;

revoke all on function public.batata_chat_messages_assert_json_card(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.batata_chat_messages_assert_json_card(uuid, uuid, text)
  to service_role;

create or replace function public.batata_chat_is_forged_seguro_plain(p_text text)
returns boolean
language sql
immutable
as $$
  select coalesce(p_text, '') ~* '^\s*Compra( em conjunto)? paga através do Seguro Fleaber';
$$;

revoke all on function public.batata_chat_is_forged_seguro_plain(text)
  from public, anon, authenticated;
grant execute on function public.batata_chat_is_forged_seguro_plain(text)
  to service_role;

create or replace function public.batata_chat_messages_guard_insert()
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

  NEW.sender_id := v_uid;

  -- K-P1-002: JWT não forja texto legado que a app pinta como recibo
  if public.batata_chat_is_forged_seguro_plain(NEW.text) then
    raise exception 'chat_seguro_legacy_plain_forbidden' using errcode = '42501';
  end if;

  perform public.batata_chat_messages_assert_json_card(
    NEW.chat_id, NEW.sender_id, NEW.text
  );
  return NEW;
end;
$fn$;

create or replace function public.batata_chat_messages_guard_update()
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

  NEW.sender_id := OLD.sender_id;
  NEW.chat_id := OLD.chat_id;

  if OLD.sender_id is distinct from v_uid then
    NEW.text := OLD.text;
    return NEW;
  end if;

  if coalesce(OLD.text, '') like 'FLEABER_JSON_V1:%'
     and NEW.text is distinct from OLD.text then
    raise exception 'chat_system_card_immutable' using errcode = '42501';
  end if;

  if public.batata_chat_is_forged_seguro_plain(NEW.text)
     and NEW.text is distinct from OLD.text then
    raise exception 'chat_seguro_legacy_plain_forbidden' using errcode = '42501';
  end if;

  if coalesce(OLD.text, '') not like 'FLEABER_JSON_V1:%'
     and coalesce(NEW.text, '') like 'FLEABER_JSON_V1:%' then
    perform public.batata_chat_messages_assert_json_card(
      NEW.chat_id, NEW.sender_id, NEW.text
    );
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_chat_messages_guard_insert on public.chat_messages;
create trigger trg_batata_chat_messages_guard_insert
  before insert on public.chat_messages
  for each row
  execute function public.batata_chat_messages_guard_insert();

drop trigger if exists trg_batata_chat_messages_guard_update on public.chat_messages;
create trigger trg_batata_chat_messages_guard_update
  before update on public.chat_messages
  for each row
  execute function public.batata_chat_messages_guard_update();

-- ---------------------------------------------------------------------------
-- L — money_cols: congelar reservation_expires_at (buyer; seller só no aceite)
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_money_cols()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_old_st text;
  v_paid boolean;
  v_internal boolean := false;
  v_allow_ttl boolean := false;
begin
  v_internal :=
    coalesce(current_setting('batata.allow_internal_order_cols', true), '') = '1'
    or coalesce(current_setting('batata.wallet_internal', true), '') = '1';

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
    NEW.wallet_release_processed_at := null;
    NEW.auto_feedback_processed_at := null;
    -- L: JWT não inventa TTL longo/passado — máx 5 dias (produto actual)
    if NEW.reservation_expires_at is not null then
      NEW.reservation_expires_at := now() + interval '5 days';
    end if;
    return NEW;
  end if;

  if NEW.buyer_id is distinct from OLD.buyer_id
     or NEW.seller_id is distinct from OLD.seller_id
     or NEW.product_id is distinct from OLD.product_id
     or NEW.stripe_checkout_session_id is distinct from OLD.stripe_checkout_session_id
     or NEW.stripe_payment_intent_id is distinct from OLD.stripe_payment_intent_id
     or NEW.stripe_refund_id is distinct from OLD.stripe_refund_id
     or NEW.amount_paid_cents is distinct from OLD.amount_paid_cents
     or NEW.price_total is distinct from OLD.price_total
     or NEW.contract_unit_cents is distinct from OLD.contract_unit_cents
     or NEW.contract_qty is distinct from OLD.contract_qty
     or NEW.quantity is distinct from OLD.quantity
     or NEW.payment_method is distinct from OLD.payment_method
  then
    raise exception 'order_money_fields_immutable' using errcode = '42501';
  end if;

  if not v_internal then
    if NEW.wallet_release_processed_at is distinct from OLD.wallet_release_processed_at then
      raise exception 'order_wallet_release_flag_immutable' using errcode = '42501';
    end if;
    if NEW.auto_feedback_processed_at is distinct from OLD.auto_feedback_processed_at then
      raise exception 'order_auto_feedback_flag_immutable' using errcode = '42501';
    end if;
    if NEW.wallet_refund_processed_at is distinct from OLD.wallet_refund_processed_at then
      NEW.wallet_refund_processed_at := OLD.wallet_refund_processed_at;
    end if;
    if NEW.stock_units_applied is distinct from OLD.stock_units_applied then
      NEW.stock_units_applied := OLD.stock_units_applied;
    end if;
  end if;

  if NEW.returned_at is distinct from OLD.returned_at then
    NEW.returned_at := OLD.returned_at;
  end if;

  -- L-P1: TTL — aceitar reserva / proposta; nunca ressuscitar hold caducado; cap 5d
  if NEW.reservation_expires_at is distinct from OLD.reservation_expires_at then
    if NEW.reservation_expires_at is not null
       and NEW.reservation_expires_at > now() + interval '5 days' + interval '1 hour' then
      NEW.reservation_expires_at := now() + interval '5 days';
    end if;

    if OLD.reservation_expires_at is not null
       and OLD.reservation_expires_at < now() then
      NEW.reservation_expires_at := OLD.reservation_expires_at;
    elsif OLD.reservation_expires_at is not null then
      v_allow_ttl :=
        (
          lower(trim(coalesce(OLD.status, ''))) = 'reserva_pendente'
          and lower(trim(coalesce(NEW.status, ''))) = 'reservado'
        )
        or (NEW.product_offer_id is distinct from OLD.product_offer_id);
      if not v_allow_ttl then
        NEW.reservation_expires_at := OLD.reservation_expires_at;
      end if;
    end if;
  end if;

  v_old_st := lower(trim(coalesce(OLD.status, '')));
  v_paid := v_old_st in (
    'pago', 'enviado', 'entregue', 'concluido', 'premio_rifa',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor', 'devolvida'
  ) or coalesce(OLD.amount_paid_cents, 0) > 0
    or coalesce(OLD.stripe_payment_intent_id, '') <> '';

  if v_paid and NEW.bundle_id is distinct from OLD.bundle_id then
    raise exception 'order_bundle_id_frozen_after_payment' using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

comment on function public.batata_orders_guard_money_cols() is
  'KLM: money flags + reservation_expires_at freeze (buyer; seller só aceite).';

-- ---------------------------------------------------------------------------
-- L — reviews: sem DELETE JWT (impede 1★→apagar→cron 5★ e apagar auto)
-- ---------------------------------------------------------------------------
drop policy if exists "reviews_delete_own" on public.reviews;
drop policy if exists reviews_delete_own_attempt on public.reviews;

-- Policy tem de permitir o attempt (senão PostgREST devolve 200 vazio sem trigger).
-- O trigger recusa sempre para JWT autenticado.
create policy reviews_delete_own_attempt
  on public.reviews
  for delete
  to authenticated
  using (
    buyer_id = auth.uid()
    or target_id = auth.uid()
    or public.batata_is_admin()
  );

create or replace function public.batata_reviews_guard_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if v_role = 'authenticated' and v_uid is not null then
    raise exception 'review_delete_forbidden' using errcode = '42501';
  end if;
  return OLD;
end;
$fn$;

drop trigger if exists trg_batata_reviews_guard_delete on public.reviews;
create trigger trg_batata_reviews_guard_delete
  before delete on public.reviews
  for each row
  execute function public.batata_reviews_guard_delete();

-- ---------------------------------------------------------------------------
-- L — 1A: job cancela holds com reservation_expires_at no passado
-- ---------------------------------------------------------------------------
create or replace function public.batata_expire_reservation_holds(
  p_now timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare
  r record;
  v_count integer := 0;
begin
  for r in
    select o.id
    from public.orders o
    where lower(trim(coalesce(o.status, ''))) in ('reserva_pendente', 'reservado')
      and o.reservation_expires_at is not null
      and o.reservation_expires_at < p_now
    for update skip locked
  loop
    perform set_config('batata.allow_internal_order_cols', '1', true);
    update public.orders
    set status = 'cancelado'
    where id = r.id
      and lower(trim(coalesce(status, ''))) in ('reserva_pendente', 'reservado');
    if found then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$fn$;

comment on function public.batata_expire_reservation_holds(timestamptz) is
  'KLM-1A: cancela reserva_pendente/reservado com reservation_expires_at < now (TTL app = 5d).';

revoke all on function public.batata_expire_reservation_holds(timestamptz)
  from public, anon, authenticated;
grant execute on function public.batata_expire_reservation_holds(timestamptz)
  to service_role;

do $cron_unschedule_holds$
begin
  perform cron.unschedule('batata-reservation-holds-expire');
exception
  when others then
    null;
end;
$cron_unschedule_holds$;

select cron.schedule(
  'batata-reservation-holds-expire',
  '*/15 * * * *',
  $$ select public.batata_expire_reservation_holds(); $$
);

-- ---------------------------------------------------------------------------
-- M — 2A: resolve_handle — sem Hub publicado e sem directo activo = not_found
-- ---------------------------------------------------------------------------
create or replace function public.batata_resolve_handle(p_handle text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_in text := public.batata_normalize_handle(p_handle);
  v_profile_id uuid;
  v_handle text;
  v_published boolean;
  v_redirect text;
  v_live boolean := false;
begin
  if v_in = '' then
    return jsonb_build_object(
      'found', false,
      'error', 'not_found',
      'http_status', 404
    );
  end if;

  select p.id, p.handle, p.hub_published
  into v_profile_id, v_handle, v_published
  from public.profiles p
  where p.handle = v_in
  limit 1;

  if v_profile_id is null then
    select
      p.id,
      public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name),
      p.hub_published
    into v_profile_id, v_handle, v_published
    from public.profiles p
    where public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name) = v_in
    limit 1;
  end if;

  if v_profile_id is null then
    select r.new_handle into v_redirect
    from public.profile_handle_redirects r
    where r.old_handle = v_in
      and (r.redirect_until is null or r.redirect_until > now())
    limit 1;

    if v_redirect is not null then
      select p.id, p.handle, p.hub_published
      into v_profile_id, v_handle, v_published
      from public.profiles p
      where p.handle = v_redirect
      limit 1;

      if v_profile_id is not null then
        select exists (
          select 1
          from public.lives l
          where coalesce(l.seller_id, l.vendedor_id) = v_profile_id
            and (
              (
                lower(trim(coalesce(l.status, ''))) = 'live'
                and coalesce(l.is_active, false) = true
              )
              or (
                coalesce(l.is_active, false) = true
                and lower(trim(coalesce(l.status, ''))) in ('live', 'ao_vivo', 'active')
              )
            )
        ) into v_live;

        if coalesce(v_published, false) or v_live then
          return jsonb_build_object(
            'found', true,
            'profile_id', v_profile_id,
            'handle', v_handle,
            'redirect_to', v_redirect,
            'hub_published', coalesce(v_published, false),
            'http_status', 301
          );
        end if;
      end if;
    end if;

    return jsonb_build_object(
      'found', false,
      'error', 'not_found',
      'http_status', 404
    );
  end if;

  if coalesce(v_published, false) then
    return jsonb_build_object(
      'found', true,
      'profile_id', v_profile_id,
      'handle', v_handle,
      'hub_published', true,
      'redirect_to', null,
      'http_status', 200
    );
  end if;

  -- 2A: loja desligada só resolve se houver directo real a decorrer
  select exists (
    select 1
    from public.lives l
    where coalesce(l.seller_id, l.vendedor_id) = v_profile_id
      and (
        (
          lower(trim(coalesce(l.status, ''))) = 'live'
          and coalesce(l.is_active, false) = true
        )
        or (
          coalesce(l.is_active, false) = true
          and lower(trim(coalesce(l.status, ''))) in ('live', 'ao_vivo', 'active')
        )
      )
  ) into v_live;

  if v_live then
    return jsonb_build_object(
      'found', true,
      'profile_id', v_profile_id,
      'handle', v_handle,
      'hub_published', false,
      'redirect_to', null,
      'http_status', 200
    );
  end if;

  return jsonb_build_object(
    'found', false,
    'error', 'not_found',
    'http_status', 404
  );
end;
$$;

comment on function public.batata_resolve_handle(text) is
  'KLM-2A: found só se hub_published OU directo activo real.';

revoke all on function public.batata_resolve_handle(text) from public;
grant execute on function public.batata_resolve_handle(text)
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- M — negar listagem chat_media (GET /object/public/ mantém-se no bucket público)
-- ---------------------------------------------------------------------------
drop policy if exists chat_media_public_catalog_select on storage.objects;

-- Owner autenticado continua a ver os seus paths (upload/gestão); anon não lista
create policy chat_media_owner_catalog_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'chat_media'
    and auth.uid() is not null
    and (
      name like ('product_photos/' || auth.uid()::text || '/%')
      or name like ('profile_photos/' || auth.uid()::text || '/%')
      or name like ('live_item_photos/' || auth.uid()::text || '/%')
      or name like ('live_raffle_prize/' || auth.uid()::text || '/%')
    )
  );

notify pgrst, 'reload schema';
