-- Hotfix: ingest_channel check allows only ocr|manual|graph|helper
create or replace function public.batata_commerce_seller_manual_reserve_with_policy(
  p_live_id uuid,
  p_live_item_id uuid,
  p_buyer_id uuid,
  p_qty integer default 1,
  p_source text default 'facebook_manual',
  p_notes text default null,
  p_external_display_name text default null,
  p_client_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_live public.lives%rowtype;
  v_seller uuid;
  v_src text := lower(trim(coalesce(p_source, 'facebook_manual')));
  v_qty integer := greatest(coalesce(p_qty, 1), 1);
  v_reserve jsonb;
  v_rid uuid;
  v_idem text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;
  if p_live_id is null or p_live_item_id is null or p_buyer_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;
  if v_qty > 99 then
    return jsonb_build_object('ok', false, 'error', 'invalid_qty');
  end if;
  if v_src not in ('facebook_manual', 'helper_manual') then
    return jsonb_build_object('ok', false, 'error', 'invalid_source');
  end if;

  select * into v_live from public.lives where id = p_live_id;
  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);
  if v_seller is null or (
    v_seller is distinct from v_uid
    and not public.batata_staff_has_permission(v_seller, 'can_manage_reservations')
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  v_idem := nullif(trim(coalesce(p_client_idempotency_key, '')), '');
  if v_idem is not null then
    select r.id into v_rid
    from public.live_reservation_requests r
    where r.idempotency_key = v_idem
    limit 1;
    if v_rid is not null then
      return jsonb_build_object('ok', true, 'duplicate', true, 'request_id', v_rid);
    end if;
  end if;

  v_reserve := public.batata_reserve_with_policy(
    v_seller,
    p_buyer_id,
    p_live_id,
    p_live_item_id,
    v_qty,
    v_src,
    null,
    true,
    coalesce(nullif(trim(p_notes), ''), 'seller:manual:' || v_src),
    'seller_for_buyer'
  );

  if coalesce((v_reserve->>'ok')::boolean, false) = false then
    return v_reserve;
  end if;
  if (v_reserve->>'outcome') = 'UNAVAILABLE' then
    return v_reserve || jsonb_build_object('action', 'unavailable');
  end if;

  v_rid := nullif(v_reserve->>'request_id', '')::uuid;
  if v_rid is not null then
    update public.live_reservation_requests r
    set
      external_display_name = coalesce(
        nullif(trim(coalesce(p_external_display_name, '')), ''),
        r.external_display_name
      ),
      idempotency_key = coalesce(v_idem, r.idempotency_key),
      ingest_channel = coalesce(r.ingest_channel, 'manual'),
      updated_at = timezone('utc', now())
    where r.id = v_rid;
  end if;

  return v_reserve || jsonb_build_object('action', 'created', 'duplicate', false);
end;
$$;

notify pgrst, 'reload schema';
