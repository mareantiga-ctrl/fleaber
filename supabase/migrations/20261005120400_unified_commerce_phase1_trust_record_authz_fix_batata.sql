-- Harden record_* : only service_role JWT (SECURITY DEFINER must not trust current_user)
create or replace function public.batata_buyer_trust_record_fulfillment(
  p_buyer_id uuid,
  p_source_type text,
  p_source_id text,
  p_meta jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inserted boolean := false;
begin
  if coalesce(auth.role(), '') is distinct from 'service_role' then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  if p_buyer_id is null or coalesce(trim(p_source_id), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;
  if p_source_type not in (
    'checkout_attempt', 'stripe_checkout_session', 'stripe_payment_intent', 'order'
  ) then
    return jsonb_build_object('ok', false, 'error', 'invalid_source_type');
  end if;

  begin
    insert into public.buyer_trust_events (
      buyer_id, kind, source_type, source_id, meta, occurred_at
    ) values (
      p_buyer_id, 'fulfillment', p_source_type, trim(p_source_id),
      coalesce(p_meta, '{}'::jsonb), timezone('utc', now())
    );
    v_inserted := true;
  exception when unique_violation then
    v_inserted := false;
  end;

  return public.batata_buyer_trust_recompute(p_buyer_id)
    || jsonb_build_object('inserted', v_inserted);
end;
$$;

create or replace function public.batata_buyer_trust_record_failure(
  p_buyer_id uuid,
  p_source_type text,
  p_source_id text,
  p_failure_reason text,
  p_meta jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inserted boolean := false;
  v_reason text := lower(trim(coalesce(p_failure_reason, '')));
begin
  if coalesce(auth.role(), '') is distinct from 'service_role' then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  if p_buyer_id is null or coalesce(trim(p_source_id), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;
  if v_reason not in ('guaranteed_hold_expired_unpaid', 'buyer_abandonment') then
    return jsonb_build_object(
      'ok', true,
      'inserted', false,
      'skipped', true,
      'reason', 'non_reputational_failure'
    );
  end if;
  if p_source_type not in ('order', 'live_reservation_request') then
    return jsonb_build_object('ok', false, 'error', 'invalid_source_type');
  end if;

  begin
    insert into public.buyer_trust_events (
      buyer_id, kind, source_type, source_id, failure_reason, meta, occurred_at
    ) values (
      p_buyer_id, 'failure', p_source_type, trim(p_source_id), v_reason,
      coalesce(p_meta, '{}'::jsonb), timezone('utc', now())
    );
    v_inserted := true;
  exception when unique_violation then
    v_inserted := false;
  end;

  return public.batata_buyer_trust_recompute(p_buyer_id)
    || jsonb_build_object('inserted', v_inserted);
end;
$$;

revoke all on function public.batata_buyer_trust_record_fulfillment(uuid, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.batata_buyer_trust_record_failure(uuid, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.batata_buyer_trust_record_fulfillment(uuid, text, text, jsonb) to service_role;
grant execute on function public.batata_buyer_trust_record_failure(uuid, text, text, text, jsonb) to service_role;

notify pgrst, 'reload schema';
