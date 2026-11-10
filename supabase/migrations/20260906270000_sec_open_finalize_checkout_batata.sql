-- OPEN: 1 winner Session por buyer+pedido após create (anti bag∥single dual)
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
begin
  if p_buyer_id is null or length(v_keep) < 3 then
    return jsonb_build_object('ok', false, 'error', 'invalid_args');
  end if;

  select coalesce(array_agg(x order by x), array[]::uuid[]) into v_ids
  from (select distinct unnest(coalesce(p_order_ids, array[]::uuid[])) as x) s
  where x is not null;

  perform pg_advisory_xact_lock(
    ('x' || substr(md5('batata_bag_claim:' || p_buyer_id::text), 1, 16))::bit(64)::bigint
  );

  -- Winner = cs_ com mais lines do pedido; empate → p_keep_sid
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

  -- Empate de contagem: preferir keep
  if exists (
    select 1 from public.orders
    where buyer_id = p_buyer_id
      and id = any (v_ids)
      and trim(stripe_checkout_session_id) = v_keep
  ) then
    select count(*)::int into v_best_n
    from public.orders
    where buyer_id = p_buyer_id
      and id = any (v_ids)
      and trim(stripe_checkout_session_id) = v_winner;
    if (
      select count(*)::int
      from public.orders
      where buyer_id = p_buyer_id
        and id = any (v_ids)
        and trim(stripe_checkout_session_id) = v_keep
    ) >= v_best_n then
      v_winner := v_keep;
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

  if cardinality(v_expire) > 0 then
    update public.orders
    set stripe_checkout_session_id = null
    where buyer_id = p_buyer_id
      and trim(coalesce(stripe_checkout_session_id, '')) = any (v_expire);
  end if;

  if cardinality(v_ids) > 0 then
    update public.orders
    set stripe_checkout_session_id = v_winner
    where id = any (v_ids)
      and status in (
        'reserva_pendente', 'reservado',
        'aguarda_confirmacao', 'aguarda_pagamento', 'premio_rifa'
      );
  end if;

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

notify pgrst, 'reload schema';
