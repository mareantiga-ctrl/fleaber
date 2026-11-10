-- =============================================================================
-- BATATA 2026-10-06 — Phase 4 guest correction: PGRST overload fix + security
-- PRODUCTION CHANGED = NO (staging apply only)
-- =============================================================================

-- 1) Drop ambiguous overloads (PostgREST PGRST203 when p_guest_token omitted)
drop function if exists public.batata_commerce_checkout_begin(
  jsonb, text, text, jsonb, uuid, text, boolean
);
drop function if exists public.batata_commerce_checkout_revalidate(
  jsonb, text, uuid
);
drop function if exists public.batata_commerce_checkout_release(
  uuid, text
);

-- Keep single begin with optional guest token (default null)
-- Already present as 8-arg; re-grant after drops.
grant execute on function public.batata_commerce_checkout_begin(
  jsonb, text, text, jsonb, uuid, text, boolean, text
) to anon, authenticated, service_role;

grant execute on function public.batata_commerce_checkout_revalidate(
  jsonb, text, uuid, text
) to anon, authenticated, service_role;

grant execute on function public.batata_commerce_checkout_release(
  uuid, text, text
) to anon, authenticated, service_role;

-- 2) Ownership: when guest_token provided, ALWAYS verify (no service_role bypass)
create or replace function public.batata_commerce_actor_owns_attempt(
  p_attempt public.commerce_checkout_attempts,
  p_guest_token text default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_actor jsonb;
begin
  -- Admin path: service_role without a guest token may operate (webhooks).
  -- If a guest token is supplied, ownership MUST match that session.
  if coalesce(auth.role(), '') = 'service_role'
     and coalesce(trim(p_guest_token), '') = '' then
    return true;
  end if;

  v_actor := public.batata_commerce_resolve_checkout_actor(p_guest_token);
  if coalesce((v_actor->>'ok')::boolean, false) is not true then
    return false;
  end if;
  if v_actor->>'mode' = 'authenticated' then
    return p_attempt.buyer_id is not null
      and p_attempt.buyer_id = (v_actor->>'buyer_id')::uuid;
  end if;
  return p_attempt.guest_session_id is not null
    and p_attempt.guest_session_id = (v_actor->>'guest_session_id')::uuid;
end;
$$;

-- 3) Delivery snapshot immutable once stamped (profile ≠ checkout ≠ order snap)
create or replace function public.batata_orders_freeze_delivery_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if old.delivery_snapshot_at is not null then
    if new.delivery_recipient_name is distinct from old.delivery_recipient_name
      or new.delivery_line1 is distinct from old.delivery_line1
      or new.delivery_line2 is distinct from old.delivery_line2
      or new.delivery_postal_code is distinct from old.delivery_postal_code
      or new.delivery_city is distinct from old.delivery_city
      or new.delivery_country is distinct from old.delivery_country
      or new.delivery_phone is distinct from old.delivery_phone
      or new.delivery_point_ref is distinct from old.delivery_point_ref
      or new.delivery_point_provider is distinct from old.delivery_point_provider
      or new.delivery_point_label is distinct from old.delivery_point_label
      or new.delivery_snapshot_at is distinct from old.delivery_snapshot_at
    then
      -- Allow explicit commerce confirm GUC only (payment/fulfillment internals)
      if coalesce(current_setting('batata.commerce_confirm', true), '') = '1' then
        return new;
      end if;
      raise exception 'order_delivery_snapshot_frozen' using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

notify pgrst, 'reload schema';
