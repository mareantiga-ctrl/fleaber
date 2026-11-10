-- =============================================================================
-- BATATA — Indep 1605/1606 P2/P3 (staging)
-- P0/P1: zero nestes freezes. Fechar endurecimento.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- RT1605-P2-01 — JWT não INSERT em stripe_checkout_events
-- (refund_created forjado bloqueava release seller — DoS carteira)
-- ---------------------------------------------------------------------------
drop policy if exists stripe_checkout_events_insert_buyer on public.stripe_checkout_events;

revoke insert on table public.stripe_checkout_events from authenticated, anon, public;
grant insert on table public.stripe_checkout_events to service_role;
grant select on table public.stripe_checkout_events to authenticated, service_role;

comment on table public.stripe_checkout_events is
  'RT1605-P2-01: INSERT só service_role/Edge; buyer SELECT próprio.';

-- ---------------------------------------------------------------------------
-- RTI1606-P3-01 — email→UUID: seller com loja (products) + rate 2/h
-- Helper fresco sem produtos → null (mesmo que user_type=vendedor por engano)
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
  v_ok boolean := false;
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
  )
  and exists (
    select 1 from public.products pr where pr.seller_id = v_uid limit 1
  )
  into v_ok;

  if not coalesce(v_ok, false) then
    return null;
  end if;

  insert into public.batata_rpc_rate_limits (uid, rpc, window_start, hits)
  values (v_uid, 'batata_find_user_id_by_email', v_window, 1)
  on conflict (uid, rpc, window_start)
  do update set hits = public.batata_rpc_rate_limits.hits + 1
  returning hits into v_hits;

  if v_hits > 2 then
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
  'P3: só vendedor com produtos; rate 2/h; convites staff.';

revoke all on function public.batata_find_user_id_by_email(text) from public, anon;
grant execute on function public.batata_find_user_id_by_email(text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- RTI1606-P3-02 — PATCH money/Stripe: 403 em vez de 200 falso
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

  return NEW;
end;
$fn$;

comment on function public.batata_orders_guard_money_cols() is
  'RTI1606-P3-02: JWT não muda money/Stripe/contrato — exception (não 200 falso).';

-- ---------------------------------------------------------------------------
-- RTI1606-P2-01 — claim atómico de slot Checkout (anti-race 2 Sessions)
-- ---------------------------------------------------------------------------
create or replace function public.batata_claim_checkout_session_slot(
  p_order_id uuid,
  p_claim_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sid text;
  v_status text;
  v_claimed text;
begin
  if p_order_id is null or length(trim(coalesce(p_claim_token, ''))) < 12 then
    return jsonb_build_object('ok', false, 'error', 'invalid_args');
  end if;

  select stripe_checkout_session_id, status
  into v_sid, v_status
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  v_sid := nullif(trim(coalesce(v_sid, '')), '');

  -- Já tem Session Stripe real
  if v_sid is not null and v_sid like 'cs_%' then
    return jsonb_build_object(
      'ok', true,
      'action', 'reuse',
      'session_id', v_sid,
      'status', v_status
    );
  end if;

  -- Outro worker a criar (claiming:…)
  if v_sid is not null and v_sid like 'claiming:%' then
    return jsonb_build_object(
      'ok', true,
      'action', 'wait',
      'session_id', v_sid,
      'status', v_status
    );
  end if;

  -- Slot livre → claim
  update public.orders
  set stripe_checkout_session_id = trim(p_claim_token)
  where id = p_order_id
    and (
      stripe_checkout_session_id is null
      or nullif(trim(stripe_checkout_session_id), '') is null
    )
  returning stripe_checkout_session_id into v_claimed;

  if v_claimed is null then
    -- Perdeu a race — ler de novo
    select stripe_checkout_session_id into v_sid
    from public.orders where id = p_order_id;
    return jsonb_build_object(
      'ok', true,
      'action', case
        when coalesce(v_sid, '') like 'cs_%' then 'reuse'
        else 'wait'
      end,
      'session_id', v_sid
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'action', 'create',
    'session_id', v_claimed,
    'status', v_status
  );
end;
$$;

revoke all on function public.batata_claim_checkout_session_slot(uuid, text)
  from public, anon, authenticated;
grant execute on function public.batata_claim_checkout_session_slot(uuid, text)
  to service_role;

comment on function public.batata_claim_checkout_session_slot(uuid, text) is
  'RTI1606-P2-01: FOR UPDATE + claim claiming:token — 1 Session create por order.';

notify pgrst, 'reload schema';
