-- OPEN bag∥single cold race — buyer-wide claiming → wait
-- Staging only. NÃO produção / Fase 4 até reteste P0–P2=0.

create or replace function public.batata_bag_checkout_claim(
  p_order_ids uuid[],
  p_claim_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids uuid[];
  r record;
  v_sid text;
  v_any_cs text := null;
  v_any_other_claim boolean := false;
  v_buyer_busy boolean := false;
  v_expired boolean;
  v_ms bigint;
  v_now_ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_ttl_ms bigint := 120000;
  v_skew_ms bigint := 60000;
  v_updated int := 0;
  v_buyer uuid;
  v_mutex_token text;
  v_mutex_exp timestamptz;
begin
  if p_order_ids is null or cardinality(p_order_ids) < 1
     or length(trim(coalesce(p_claim_token, ''))) < 12 then
    return jsonb_build_object('ok', false, 'error', 'invalid_args');
  end if;

  select array_agg(x order by x) into v_ids
  from (select distinct unnest(p_order_ids) as x) s
  where x is not null;

  if v_ids is null or cardinality(v_ids) < 1 then
    return jsonb_build_object('ok', false, 'error', 'invalid_args');
  end if;

  select buyer_id into v_buyer from public.orders where id = v_ids[1];
  if v_buyer is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_args');
  end if;

  perform pg_advisory_xact_lock(
    ('x' || substr(md5('batata_bag_claim:' || v_buyer::text), 1, 16))::bit(64)::bigint
  );

  delete from public.batata_checkout_mutex
  where buyer_id = v_buyer and expires_at < now();

  select claim_token, expires_at into v_mutex_token, v_mutex_exp
  from public.batata_checkout_mutex
  where buyer_id = v_buyer
  for update;

  if v_mutex_token is not null
     and v_mutex_token is distinct from trim(p_claim_token)
     and v_mutex_exp > now() then
    return jsonb_build_object(
      'ok', true, 'action', 'wait', 'session_id', null
    );
  end if;

  -- Qualquer cs_/claiming nestas lines
  for r in
    select id, stripe_checkout_session_id
    from public.orders
    where id = any(v_ids)
    order by id
    for update
  loop
    v_sid := nullif(trim(coalesce(r.stripe_checkout_session_id, '')), '');
    if v_sid is not null and v_sid like 'cs_%' then
      v_any_cs := v_sid;
    elsif v_sid is not null and v_sid like 'claiming:%'
          and v_sid is distinct from trim(p_claim_token) then
      v_expired := false;
      if v_sid ~ '^claiming:[0-9]{10,13}:' then
        begin
          v_ms := substring(v_sid from '^claiming:([0-9]{10,13}):')::bigint;
          if v_ms > v_now_ms + v_skew_ms then
            v_expired := true;
          elsif v_now_ms - v_ms > v_ttl_ms then
            v_expired := true;
          else
            v_any_other_claim := true;
          end if;
        exception when others then
          v_expired := true;
        end;
      else
        v_expired := true;
      end if;
      if v_expired then
        update public.orders
        set stripe_checkout_session_id = null
        where id = r.id
          and stripe_checkout_session_id = v_sid;
      end if;
    end if;
  end loop;

  if v_any_cs is not null then
    delete from public.batata_checkout_mutex where buyer_id = v_buyer;
    return jsonb_build_object(
      'ok', true, 'action', 'reuse', 'session_id', v_any_cs
    );
  end if;

  if v_any_other_claim then
    return jsonb_build_object(
      'ok', true, 'action', 'wait', 'session_id', null
    );
  end if;

  -- OPEN: claiming activo noutro pedido do MESMO buyer (bag∥single a frio)
  -- → wait mesmo que os UUID sets ainda não se tenham cruzado na row
  select exists (
    select 1
    from public.orders o
    where o.buyer_id = v_buyer
      and o.status in (
        'reserva_pendente', 'reservado',
        'aguarda_confirmacao', 'aguarda_pagamento', 'premio_rifa'
      )
      and o.stripe_checkout_session_id like 'claiming:%'
      and o.stripe_checkout_session_id is distinct from trim(p_claim_token)
      and (
        o.stripe_checkout_session_id !~ '^claiming:[0-9]{10,13}:'
        or (
          (extract(epoch from clock_timestamp()) * 1000)::bigint
            - substring(o.stripe_checkout_session_id from '^claiming:([0-9]{10,13}):')::bigint
        ) <= 120000
      )
  ) into v_buyer_busy;

  if v_buyer_busy then
    return jsonb_build_object(
      'ok', true, 'action', 'wait', 'session_id', null
    );
  end if;

  update public.orders
  set stripe_checkout_session_id = trim(p_claim_token)
  where id = any(v_ids)
    and (
      stripe_checkout_session_id is null
      or nullif(trim(stripe_checkout_session_id), '') is null
      or stripe_checkout_session_id = trim(p_claim_token)
    );
  get diagnostics v_updated = row_count;

  if v_updated < cardinality(v_ids) then
    for r in
      select stripe_checkout_session_id as sid
      from public.orders
      where id = any(v_ids)
        and stripe_checkout_session_id is not null
        and stripe_checkout_session_id is distinct from trim(p_claim_token)
    loop
      if trim(r.sid) like 'cs_%' then
        return jsonb_build_object(
          'ok', true, 'action', 'reuse', 'session_id', trim(r.sid)
        );
      end if;
    end loop;
    return jsonb_build_object(
      'ok', true, 'action', 'wait', 'session_id', null
    );
  end if;

  insert into public.batata_checkout_mutex (buyer_id, claim_token, order_ids, expires_at)
  values (v_buyer, trim(p_claim_token), v_ids, now() + interval '120 seconds')
  on conflict (buyer_id) do update
    set claim_token = excluded.claim_token,
        order_ids = excluded.order_ids,
        expires_at = excluded.expires_at
  where public.batata_checkout_mutex.claim_token = trim(p_claim_token)
     or public.batata_checkout_mutex.expires_at < now();

  if not exists (
    select 1 from public.batata_checkout_mutex
    where buyer_id = v_buyer
      and claim_token = trim(p_claim_token)
  ) then
    return jsonb_build_object(
      'ok', true, 'action', 'wait', 'session_id', null
    );
  end if;

  return jsonb_build_object(
    'ok', true, 'action', 'create', 'session_id', null
  );
end;
$$;

notify pgrst, 'reload schema';
