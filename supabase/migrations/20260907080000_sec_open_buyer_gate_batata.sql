-- OPEN 2026-09-07 — gate definitivo bag∥single
-- Problema: 2× sessions.create + 2× HTTP 200 (reused=false); finalize parcial
--   só via order_ids do pedido → ambos "ganham"; mutex libertado cedo demais.
-- Solução: (1) claim mais duro (2) finalize em TODOS os pending do buyer
--   (3) RPC may_create / publish result. Staging only. BATATA.

-- ---------------------------------------------------------------------------
-- Finalize GLOBAL: todas as encomendas pending do buyer, não só p_order_ids
-- ---------------------------------------------------------------------------
create or replace function public.batata_buyer_finalize_checkout(
  p_buyer_id uuid,
  p_keep_sid text,
  p_order_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids uuid[];
  v_keep text := trim(coalesce(p_keep_sid, ''));
  v_winner text;
  v_expire text[] := array[]::text[];
  r record;
  v_best_n int := -1;
  v_pending uuid[];
begin
  if p_buyer_id is null or length(v_keep) < 3 then
    return jsonb_build_object('ok', false, 'error', 'invalid_args');
  end if;

  perform pg_advisory_xact_lock(
    ('x' || substr(md5('batata_bag_claim:' || p_buyer_id::text), 1, 16))::bit(64)::bigint
  );

  -- Universo = pending do buyer ∪ ids pedidos (cobre bag∥single)
  select coalesce(array_agg(distinct o.id), array[]::uuid[]) into v_pending
  from public.orders o
  where o.buyer_id = p_buyer_id
    and o.status in (
      'reserva_pendente', 'reservado',
      'aguarda_confirmacao', 'aguarda_pagamento', 'premio_rifa'
    );

  select coalesce(array_agg(x order by x), array[]::uuid[]) into v_ids
  from (
    select unnest(coalesce(p_order_ids, array[]::uuid[])) as x
    union
    select unnest(coalesce(v_pending, array[]::uuid[]))
  ) s
  where x is not null;

  -- Winner = cs_ com mais linhas pending; empate → p_keep se empatar em count
  for r in
    select trim(stripe_checkout_session_id) as sid, count(*)::int as n
    from public.orders
    where buyer_id = p_buyer_id
      and id = any (v_ids)
      and stripe_checkout_session_id like 'cs_%'
    group by trim(stripe_checkout_session_id)
  loop
    if r.n > v_best_n
       or (r.n = v_best_n and r.sid = v_keep)
       or (r.n = v_best_n and v_winner is null) then
      v_best_n := r.n;
      v_winner := r.sid;
    end if;
  end loop;

  if v_winner is null then
    v_winner := v_keep;
  end if;

  -- Preferir keep se empatar em nº de linhas
  if v_keep like 'cs_%' then
    if (
      select count(*)::int from public.orders
      where buyer_id = p_buyer_id and id = any (v_ids)
        and trim(stripe_checkout_session_id) = v_keep
    ) >= (
      select count(*)::int from public.orders
      where buyer_id = p_buyer_id and id = any (v_ids)
        and trim(stripe_checkout_session_id) = v_winner
    ) then
      -- só se keep ainda está no ledger OU keep ainda não escrito (n=0) e winner=keep
      if exists (
        select 1 from public.orders
        where buyer_id = p_buyer_id and id = any (v_ids)
          and trim(stripe_checkout_session_id) = v_keep
      ) or v_winner = v_keep then
        if (
          select count(*)::int from public.orders
          where buyer_id = p_buyer_id and id = any (v_ids)
            and trim(stripe_checkout_session_id) = v_keep
        ) = (
          select count(*)::int from public.orders
          where buyer_id = p_buyer_id and id = any (v_ids)
            and trim(stripe_checkout_session_id) = v_winner
        ) then
          v_winner := v_keep;
        end if;
      end if;
    end if;
  end if;

  for r in
    select distinct trim(stripe_checkout_session_id) as sid
    from public.orders
    where buyer_id = p_buyer_id
      and id = any (v_ids)
      and stripe_checkout_session_id like 'cs_%'
      and trim(stripe_checkout_session_id) is distinct from v_winner
  loop
    v_expire := array_append(v_expire, r.sid);
  end loop;

  -- Também expirar keep se perdeu (órfã nunca escrita no ledger)
  if v_keep like 'cs_%' and v_keep is distinct from v_winner then
    if not (v_keep = any (v_expire)) then
      v_expire := array_append(v_expire, v_keep);
    end if;
  end if;

  if cardinality(v_expire) > 0 then
    update public.orders
    set stripe_checkout_session_id = null
    where buyer_id = p_buyer_id
      and trim(coalesce(stripe_checkout_session_id, '')) = any (v_expire);
  end if;

  -- Gravar winner em todas as lines do keep (pedido actual) se ganhámos
  if v_winner = v_keep and cardinality(coalesce(p_order_ids, array[]::uuid[])) > 0 then
    update public.orders
    set stripe_checkout_session_id = v_winner
    where id = any (p_order_ids)
      and status in (
        'reserva_pendente', 'reservado',
        'aguarda_confirmacao', 'aguarda_pagamento', 'premio_rifa'
      );
  end if;

  -- Publicar resultado no mutex para waiters (antes de apagar)
  update public.batata_checkout_mutex
  set claim_token = coalesce(claim_token, ''),
      expires_at = now() + interval '30 seconds'
  where buyer_id = p_buyer_id;

  -- Libertar mutex do buyer (outro checkout legítimo mais tarde)
  delete from public.batata_checkout_mutex where buyer_id = p_buyer_id;

  return jsonb_build_object(
    'ok', true,
    'winner_sid', v_winner,
    'expire_sids', to_jsonb(coalesce(v_expire, array[]::text[])),
    'we_won', (v_winner = v_keep)
  );
end;
$$;

revoke all on function public.batata_buyer_finalize_checkout(uuid, text, uuid[])
  from public, anon, authenticated;
grant execute on function public.batata_buyer_finalize_checkout(uuid, text, uuid[])
  to service_role;

-- ---------------------------------------------------------------------------
-- may_create: ainda somos o dono do mutex? Senão → não chamar Stripe
-- ---------------------------------------------------------------------------
create or replace function public.batata_buyer_may_create_session(
  p_buyer_id uuid,
  p_claim_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tok text;
  v_exp timestamptz;
  v_any_cs text := null;
  r record;
begin
  if p_buyer_id is null or length(trim(coalesce(p_claim_token, ''))) < 12 then
    return jsonb_build_object('ok', false, 'action', 'deny');
  end if;

  perform pg_advisory_xact_lock(
    ('x' || substr(md5('batata_bag_claim:' || p_buyer_id::text), 1, 16))::bit(64)::bigint
  );

  delete from public.batata_checkout_mutex
  where buyer_id = p_buyer_id and expires_at < now();

  -- Já há cs_ em pending? Reutilizar (bag∥single a meio)
  for r in
    select trim(stripe_checkout_session_id) as sid
    from public.orders
    where buyer_id = p_buyer_id
      and status in (
        'reserva_pendente', 'reservado',
        'aguarda_confirmacao', 'aguarda_pagamento', 'premio_rifa'
      )
      and stripe_checkout_session_id like 'cs_%'
    order by id
  loop
    v_any_cs := r.sid;
    exit;
  end loop;

  if v_any_cs is not null then
    return jsonb_build_object(
      'ok', true, 'action', 'reuse', 'session_id', v_any_cs
    );
  end if;

  select claim_token, expires_at into v_tok, v_exp
  from public.batata_checkout_mutex
  where buyer_id = p_buyer_id
  for update;

  if v_tok is null then
    -- Sem mutex: se ainda temos claiming nas rows, repor mutex e allow create
    if exists (
      select 1 from public.orders o
      where o.buyer_id = p_buyer_id
        and o.stripe_checkout_session_id = trim(p_claim_token)
    ) and not exists (
      select 1 from public.orders o
      where o.buyer_id = p_buyer_id
        and o.status in (
          'reserva_pendente', 'reservado',
          'aguarda_confirmacao', 'aguarda_pagamento', 'premio_rifa'
        )
        and o.stripe_checkout_session_id like 'claiming:%'
        and o.stripe_checkout_session_id is distinct from trim(p_claim_token)
    ) then
      insert into public.batata_checkout_mutex (buyer_id, claim_token, order_ids, expires_at)
      values (
        p_buyer_id,
        trim(p_claim_token),
        array(
          select o.id from public.orders o
          where o.buyer_id = p_buyer_id
            and o.stripe_checkout_session_id = trim(p_claim_token)
        ),
        now() + interval '120 seconds'
      )
      on conflict (buyer_id) do update
        set claim_token = excluded.claim_token,
            order_ids = excluded.order_ids,
            expires_at = excluded.expires_at;
      return jsonb_build_object('ok', true, 'action', 'create');
    end if;
    return jsonb_build_object('ok', true, 'action', 'deny');
  end if;

  if v_tok is distinct from trim(p_claim_token) then
    return jsonb_build_object('ok', true, 'action', 'wait');
  end if;

  if v_exp is not null and v_exp < now() then
    delete from public.batata_checkout_mutex where buyer_id = p_buyer_id;
    return jsonb_build_object('ok', true, 'action', 'deny');
  end if;

  return jsonb_build_object('ok', true, 'action', 'create');
end;
$$;

revoke all on function public.batata_buyer_may_create_session(uuid, text)
  from public, anon, authenticated;
grant execute on function public.batata_buyer_may_create_session(uuid, text)
  to service_role;

-- Claim: em wait, devolver cs_ buyer-wide se já existir (não só nas lines)
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

  -- Qualquer cs_ pending do buyer (não só p_order_ids) → reuse
  for r in
    select trim(o.stripe_checkout_session_id) as sid
    from public.orders o
    where o.buyer_id = v_buyer
      and o.status in (
        'reserva_pendente', 'reservado',
        'aguarda_confirmacao', 'aguarda_pagamento', 'premio_rifa'
      )
      and o.stripe_checkout_session_id like 'cs_%'
    order by
      case when o.id = any (v_ids) then 0 else 1 end,
      o.id
  loop
    v_any_cs := r.sid;
    exit;
  end loop;

  if v_any_cs is not null then
    delete from public.batata_checkout_mutex where buyer_id = v_buyer;
    return jsonb_build_object(
      'ok', true, 'action', 'reuse', 'session_id', v_any_cs
    );
  end if;

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
