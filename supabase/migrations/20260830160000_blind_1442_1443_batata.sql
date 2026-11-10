-- =============================================================================
-- BATATA — Indep 1443 P0 proposta + Blind B 1442 P1/P2
-- Staging. Sem produção / Fase 4.
-- REGRESSÃO: sec_blind_p2_p3_fecho reescreveu seal_contract e reabriu
-- payment_method ILIKE '%proposta%' sem oferta aceite — fechar de novo.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- RTI-P0-001 + RTI-P2-001 — selo contrato (base RTB-B-1755) + display JWT
-- JWT: limpa contract_* do cliente; preço só catálogo ou oferta aceite.
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_seal_contract()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_jwt boolean := (v_role = 'authenticated' and v_uid is not null);
  v_unit_cents int := 0;
  v_li numeric;
  v_prod numeric;
  v_offer public.product_offers%rowtype;
  v_auth_qty int;
  v_res_qty int := 0;
  v_client_offer_id uuid;
  v_min_total numeric;
begin
  v_client_offer_id := NEW.product_offer_id;

  -- JWT nunca manda contract_* (RTI-P2-001)
  if v_jwt then
    NEW.contract_unit_cents := null;
    NEW.contract_qty := null;
  elsif NEW.contract_unit_cents is not null and NEW.contract_unit_cents > 0 then
    if NEW.contract_qty is null or NEW.contract_qty < 1 then
      NEW.contract_qty := greatest(coalesce(NEW.quantity, 1), 1);
    end if;
    NEW.quantity := NEW.contract_qty;
    return NEW;
  end if;

  if NEW.live_raffle_id is not null
     and lower(trim(coalesce(NEW.status, ''))) = 'premio_rifa' then
    NEW.contract_unit_cents := 0;
    NEW.contract_qty := 1;
    NEW.quantity := 1;
    return NEW;
  end if;

  v_auth_qty := greatest(coalesce(NEW.quantity, 1), 1);
  if v_auth_qty > 99 then
    raise exception 'invalid_order_quantity' using errcode = '23514';
  end if;

  if v_jwt
     and NEW.live_item_id is not null
     and NEW.buyer_id is not null then
    select coalesce(sum(r.requested_qty), 0)::int into v_res_qty
    from public.live_reservation_requests r
    where r.live_item_id = NEW.live_item_id
      and r.buyer_id = NEW.buyer_id
      and r.status in ('accepted', 'converted');
    if v_res_qty > 0 and v_auth_qty > v_res_qty then
      raise exception 'order_quantity_exceeds_reservation'
        using errcode = '23514';
    end if;
  end if;

  if NEW.live_item_id is not null then
    select li.price into v_li
    from public.live_items li
    where li.id = NEW.live_item_id;
    if v_li is not null and v_li > 0 then
      v_unit_cents := greatest(1, round(v_li * 100)::int);
    end if;
  end if;

  if v_unit_cents <= 0 and NEW.product_id is not null then
    select p.price into v_prod
    from public.products p
    where p.id = NEW.product_id;
    if v_prod is not null and v_prod > 0 then
      v_unit_cents := greatest(1, round(v_prod * 100)::int);
    end if;
  end if;

  -- Proposta: SÓ oferta aceite (nunca payment_method LIKE '%proposta%')
  v_offer := null;
  if NEW.product_offer_id is not null then
    select * into v_offer
    from public.product_offers po
    where po.id = NEW.product_offer_id;
  elsif NEW.product_id is not null and NEW.buyer_id is not null then
    select * into v_offer
    from public.product_offers po
    where po.product_id = NEW.product_id
      and po.buyer_id = NEW.buyer_id
      and (NEW.seller_id is null or po.seller_id = NEW.seller_id)
      and lower(trim(coalesce(po.status, ''))) = 'accepted'
      and (po.expires_at is null or po.expires_at > now())
      and not public.batata_product_offer_is_consumed(po.id, NEW.id)
    order by coalesce(po.responded_at, po.created_at) desc
    limit 1;
  end if;

  if v_offer.id is not null then
    if lower(trim(coalesce(v_offer.status, ''))) is distinct from 'accepted'
       or v_offer.product_id is distinct from NEW.product_id
       or v_offer.buyer_id is distinct from NEW.buyer_id
       or (NEW.seller_id is not null and v_offer.seller_id is distinct from NEW.seller_id)
       or (v_offer.expires_at is not null and v_offer.expires_at <= now())
       or coalesce(v_offer.amount, 0) <= 0
       or v_offer.responded_at is null then
      NEW.product_offer_id := null;
    elsif public.batata_product_offer_is_consumed(v_offer.id, NEW.id) then
      if v_client_offer_id is not null then
        raise exception 'offer_already_consumed' using errcode = '23514';
      end if;
      NEW.product_offer_id := null;
    else
      NEW.product_offer_id := v_offer.id;
      v_unit_cents := greatest(1, round(v_offer.amount * 100)::int);
    end if;
  else
    if v_client_offer_id is not null
       and public.batata_product_offer_is_consumed(v_client_offer_id, NEW.id) then
      raise exception 'offer_already_consumed' using errcode = '23514';
    end if;
    NEW.product_offer_id := null;
  end if;

  if v_unit_cents <= 0 then
    raise exception 'order_contract_price_missing' using errcode = '23514';
  end if;

  NEW.contract_unit_cents := v_unit_cents;
  NEW.contract_qty := v_auth_qty;
  NEW.quantity := v_auth_qty;

  -- Display JWT = contrato (não 999€; não 0.50€ sem oferta)
  if v_jwt then
    v_min_total := (v_unit_cents::numeric * v_auth_qty::numeric) / 100.0;
    NEW.price_total := round(v_min_total, 2);
    -- String "proposta" sem oferta → método neutro (não mente na UI)
    if NEW.product_offer_id is null
       and lower(coalesce(NEW.payment_method, '')) like '%proposta%' then
      NEW.payment_method := 'Pagamento na app';
    end if;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_seal_contract on public.orders;
create trigger trg_batata_orders_seal_contract
  before insert on public.orders
  for each row
  execute function public.batata_orders_seal_contract();

comment on function public.batata_orders_seal_contract() is
  'RTI-P0-001: contrato só catálogo ou product_offers accepted; JWT limpa contract_*.';

-- ---------------------------------------------------------------------------
-- RTB3-1442-S6-04 — disputes: comprador NÃO lê pasta do seller
-- Path app: order_disputes/{uploader_uid}/…
-- Seller lê provas do buyer com quem tem order; buyer só a própria pasta.
-- ---------------------------------------------------------------------------
drop policy if exists fleaber_private_select_order_counterparty on storage.objects;
create policy fleaber_private_select_order_counterparty
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and (
      (
        name like 'order_proofs/%'
        and exists (
          select 1
          from public.orders o
          where o.seller_id = auth.uid()
            and o.buyer_id is not null
            and name like (
              'order_proofs/' || o.buyer_id::text || '/' || o.id::text || '/%'
            )
        )
      )
      or (
        name like 'order_disputes/%'
        and exists (
          select 1
          from public.orders o
          where o.seller_id = auth.uid()
            and o.buyer_id is not null
            and name like ('order_disputes/' || o.buyer_id::text || '/%')
        )
      )
    )
  );

-- ---------------------------------------------------------------------------
-- RTB3-1442-S7 — device tokens: created_by + válido só com staff activo
-- ---------------------------------------------------------------------------
alter table public.seller_device_tokens
  add column if not exists created_by uuid references public.profiles (id);

create or replace function public.batata_ps_create_pairing(
  p_live_id uuid,
  p_device_id_hint text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_seller_id uuid;
  v_live public.lives%rowtype;
  v_code text;
  v_token text;
  v_hash text;
  v_device text := coalesce(nullif(trim(p_device_id_hint), ''), 'ps-reader-pc');
  v_attempt int := 0;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  select * into v_live from public.lives where id = p_live_id;
  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  v_seller_id := coalesce(v_live.seller_id, v_live.vendedor_id);

  if v_seller_id is distinct from v_uid
     and not public.batata_staff_has_permission(v_seller_id, 'can_manage_reservations') then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  loop
    v_attempt := v_attempt + 1;
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (
      select 1 from public.ps_pairing_sessions s
      where s.code = v_code and s.claimed_at is null and s.expires_at > now()
    );
    exit when v_attempt > 20;
  end loop;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

  insert into public.seller_device_tokens (
    seller_id, device_id, token_hash, label, created_by
  ) values (
    v_seller_id,
    v_device,
    v_hash,
    'PS Reader ' || to_char(now(), 'YYYY-MM-DD HH24:MI'),
    v_uid
  )
  on conflict (seller_id, device_id) do update
  set
    token_hash = excluded.token_hash,
    label = excluded.label,
    created_by = excluded.created_by,
    revoked_at = null,
    created_at = now();

  insert into public.ps_pairing_sessions (
    seller_id, live_id, code, device_token_plain, device_id_hint, expires_at
  ) values (
    v_seller_id,
    p_live_id,
    v_code,
    v_token,
    v_device,
    now() + interval '10 minutes'
  );

  return jsonb_build_object(
    'ok', true,
    'code', v_code,
    'expires_at', (now() + interval '10 minutes'),
    'live_id', p_live_id,
    'live_title', coalesce(v_live.title, 'Live'),
    'device_id', v_device
  );
end;
$$;

revoke all on function public.batata_ps_create_pairing(uuid, text) from public, anon;
grant execute on function public.batata_ps_create_pairing(uuid, text)
  to authenticated, service_role;

create or replace function public.batata_validate_seller_device_token(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_hash text;
  v_row public.seller_device_tokens%rowtype;
  v_staff_ok boolean := false;
begin
  if trim(coalesce(p_token, '')) = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_token');
  end if;

  v_hash := encode(extensions.digest(trim(p_token), 'sha256'), 'hex');

  select * into v_row
  from public.seller_device_tokens t
  where t.token_hash = v_hash
    and t.revoked_at is null
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_token');
  end if;

  -- Token criado por helper: só válido enquanto staff activo com reservas
  if v_row.created_by is not null
     and v_row.created_by is distinct from v_row.seller_id then
    select exists (
      select 1
      from public.seller_helpers h
      where h.seller_id = v_row.seller_id
        and h.helper_user_id = v_row.created_by
        and coalesce(h.active, false) = true
        and lower(trim(coalesce(h.invitation_status, ''))) = 'accepted'
        and coalesce((h.permissions ->> 'can_manage_reservations')::boolean, false)
    ) into v_staff_ok;
    if not v_staff_ok then
      return jsonb_build_object('ok', false, 'error', 'token_staff_revoked');
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'seller_id', v_row.seller_id,
    'device_id', v_row.device_id
  );
end;
$$;

revoke all on function public.batata_validate_seller_device_token(text)
  from public, anon, authenticated;
grant execute on function public.batata_validate_seller_device_token(text)
  to service_role;

create or replace function public.batata_seller_helpers_revoke_device_tokens()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_helper uuid;
  v_seller uuid;
  v_gone boolean := false;
begin
  v_helper := coalesce(OLD.helper_user_id, NEW.helper_user_id);
  v_seller := coalesce(OLD.seller_id, NEW.seller_id);

  if TG_OP = 'DELETE' then
    v_gone := true;
  elsif TG_OP = 'UPDATE' then
    if coalesce(NEW.active, false) is not true
       or lower(trim(coalesce(NEW.invitation_status, ''))) is distinct from 'accepted'
    then
      v_gone := true;
    end if;
  end if;

  if v_gone and v_helper is not null and v_seller is not null then
    update public.seller_device_tokens
    set revoked_at = now()
    where seller_id = v_seller
      and created_by = v_helper
      and revoked_at is null;
  end if;

  if TG_OP = 'DELETE' then
    return OLD;
  end if;
  return NEW;
end;
$$;

drop trigger if exists batata_seller_helpers_revoke_devices_tg on public.seller_helpers;
create trigger batata_seller_helpers_revoke_devices_tg
  after update or delete on public.seller_helpers
  for each row
  execute function public.batata_seller_helpers_revoke_device_tokens();

-- ---------------------------------------------------------------------------
-- RTB3-1442-S1-08 — INSERT manual/FB JWT força pending (accept via RPC)
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_reservation_force_pending_manual()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.role(), '') = 'authenticated'
     and NEW.source in ('facebook_manual', 'helper_manual')
     and lower(trim(coalesce(NEW.status, ''))) is distinct from 'pending' then
    NEW.status := 'pending';
  end if;
  return NEW;
end;
$$;

drop trigger if exists batata_live_reservation_force_pending_manual_tg
  on public.live_reservation_requests;
create trigger batata_live_reservation_force_pending_manual_tg
  before insert on public.live_reservation_requests
  for each row
  execute function public.batata_live_reservation_force_pending_manual();

notify pgrst, 'reload schema';
