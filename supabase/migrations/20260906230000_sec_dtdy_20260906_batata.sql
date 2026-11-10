-- POS_DNDS DT–DY fecho 2026-09-06 BATATA
-- CONTAGEM pack: P0:0 P1:3 P2:3 TOTAL:6 (únicos)
-- DT bag race · DU live_item seal · DV revoke RLS+proof_ok · DW release∥disputa
-- production_touched:false · fase4:false

-- ===========================================================================
-- DU P2 — selar live_item sold+inactivo; recompute não reabre «available»
-- ===========================================================================
create or replace function public.batata_recompute_live_item_status(p_live_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_stock jsonb;
  v_total int;
  v_available int;
  v_blocked int;
  v_reserved int;
  v_converted int;
  v_next_status text;
  v_raffle_drawn boolean := false;
begin
  if not public.batata_can_ops_live_item(p_live_item_id) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  select * into v_li
  from public.live_items
  where id = p_live_item_id
  for update;

  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  -- Já sold (selo rifa / mark sold) — não reabrir para available
  if lower(trim(coalesce(v_li.status, ''))) = 'sold' then
    if coalesce(v_li.is_active, false) then
      update public.live_items
         set is_active = false, updated_at = now()
       where id = v_li.id;
    end if;
    return jsonb_build_object(
      'ok', true,
      'live_item_id', v_li.id,
      'item_status', 'sold',
      'sealed', true
    );
  end if;

  select exists (
    select 1
    from public.live_raffles rf
    where rf.live_item_id = v_li.id
      and lower(trim(coalesce(rf.status, ''))) = 'drawn'
  ) into v_raffle_drawn;

  if v_raffle_drawn then
    perform set_config('batata.mark_sold_internal', '1', true);
    update public.live_items
       set status = 'sold', is_active = false, updated_at = now()
     where id = v_li.id;
    perform set_config('batata.mark_sold_internal', '', true);
    return jsonb_build_object(
      'ok', true,
      'live_item_id', v_li.id,
      'item_status', 'sold',
      'raffle_drawn', true
    );
  end if;

  v_stock := public.batata_live_item_stock(p_live_item_id);
  if coalesce((v_stock->>'ok')::boolean, false) is not true then
    return v_stock;
  end if;

  v_total := coalesce((v_stock->>'total_qty')::int, 1);
  v_available := coalesce((v_stock->>'available_qty')::int, 0);
  v_blocked := coalesce((v_stock->>'blocked_qty')::int, 0);
  v_reserved := coalesce((v_stock->>'reserved_accepted_qty')::int, 0);
  v_converted := coalesce((v_stock->>'sold_converted_qty')::int, 0);

  v_next_status := case
    when v_converted >= greatest(v_total, 1) then 'sold'
    when v_reserved >= greatest(v_total, 1) then 'reserved_full'
    when v_reserved > 0 then 'reserved_partial'
    when v_blocked > 0 and v_available <= 0 then 'reserved_full'
    else 'available'
  end;

  if coalesce(v_li.status, '') is distinct from v_next_status then
    if v_next_status = 'sold' then
      perform set_config('batata.mark_sold_internal', '1', true);
    end if;
    update public.live_items
    set status = v_next_status,
        is_active = case when v_next_status = 'sold' then false else is_active end,
        updated_at = now()
    where id = v_li.id;
    if v_next_status = 'sold' then
      perform set_config('batata.mark_sold_internal', '', true);
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'live_item_id', v_li.id,
    'item_status', v_next_status,
    'total_qty', v_total,
    'available_qty', v_available,
    'blocked_qty', v_blocked,
    'reserved_accepted_qty', v_reserved
  );
end;
$$;

create or replace function public.batata_raffle_seal_prize_stock(p_raffle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_raffle public.live_raffles%rowtype;
  v_li public.live_items%rowtype;
  v_product_id uuid;
  v_winners int := 0;
  v_stock int;
begin
  if p_raffle_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_raffle');
  end if;

  select * into v_raffle from public.live_raffles where id = p_raffle_id;
  if v_raffle.id is null then
    return jsonb_build_object('ok', false, 'error', 'raffle_not_found');
  end if;
  if v_raffle.live_item_id is null then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'manual_prize');
  end if;

  select count(*)::int into v_winners
  from public.live_raffle_winners w
  where w.raffle_id = p_raffle_id;
  if v_winners < 1 then
    return jsonb_build_object('ok', false, 'error', 'no_winners');
  end if;

  select * into v_li from public.live_items where id = v_raffle.live_item_id;
  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  v_product_id := coalesce(v_li.product_id, v_li.checkout_product_id);

  -- Selar cartão do directo SEMPRE (também live_only sem product)
  perform set_config('batata.mark_sold_internal', '1', true);
  update public.live_items
     set status = 'sold',
         is_active = false,
         updated_at = now()
   where id = v_li.id;
  perform set_config('batata.mark_sold_internal', '', true);

  if v_product_id is not null then
    select coalesce(quantity, 0) into v_stock
    from public.products where id = v_product_id for update;

    update public.products
       set quantity = greatest(coalesce(v_stock, 0) - v_winners, 0),
           is_sold = (greatest(coalesce(v_stock, 0) - v_winners, 0) < 1),
           list_on_marketplace = case
             when greatest(coalesce(v_stock, 0) - v_winners, 0) < 1 then false
             else list_on_marketplace
           end
     where id = v_product_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'product_id', v_product_id,
    'winners', v_winners,
    'live_item_id', v_li.id,
    'live_item_status', 'sold'
  );
end;
$$;

-- ===========================================================================
-- DV P1 — revoke table: sem GRANT directo authenticated; só RPC
-- DV P2 — proof_ok consulta registry (deixa de ser immutable)
-- ===========================================================================
revoke all on table public.batata_private_object_revoked from public, anon, authenticated;
grant all on table public.batata_private_object_revoked to service_role;

create or replace function public.batata_dispute_proof_url_ok(
  p_url text,
  p_buyer uuid,
  p_oid uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_url text := public.batata_storage_url_path_canonical(coalesce(p_url, ''));
  v_after_host text;
  v_needle text;
  v_path text;
begin
  if v_url = '' then
    return true;
  end if;
  if p_buyer is null or p_oid is null then
    return false;
  end if;
  v_after_host := regexp_replace(v_url, '^https://[^/?#]+', '');
  if position('//' in v_after_host) > 0 then
    return false;
  end if;
  if v_url like 'javascript:%' or v_url like 'data:%' or v_url like '%..%'
     or position('%2e%2e' in v_url) > 0
     or v_url like '%/object/public/%' then
    return false;
  end if;
  if v_url not like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%' then
    return false;
  end if;
  if v_url not like '%/object/sign/fleaber_private/%'
     and v_url not like '%/object/authenticated/fleaber_private/%' then
    return false;
  end if;
  v_needle := 'fleaber_private/order_disputes/' || p_buyer::text || '/' || p_oid::text || '/';
  if v_url !~ (v_needle || '[^/]+$') then
    return false;
  end if;

  v_path := substring(v_url from 'fleaber_private/(order_disputes/[^?]+)');
  if v_path is not null and exists (
    select 1 from public.batata_private_object_revoked r
    where r.object_path = v_path
       or r.object_path = regexp_replace(v_path, '/$', '')
  ) then
    return false;
  end if;

  return true;
end;
$$;

revoke all on function public.batata_dispute_proof_url_ok(text, uuid, uuid) from public, anon;
grant execute on function public.batata_dispute_proof_url_ok(text, uuid, uuid)
  to authenticated, service_role;

-- ===========================================================================
-- DW P1 — release ∥ disputa: mesmo cadeado; clawback se crédito já saiu
-- ===========================================================================
create or replace function public.batata_clawback_seller_release_for_dispute(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_amt numeric := 0;
begin
  if p_order_id is null then
    return false;
  end if;
  perform set_config('batata.wallet_internal', '1', true);
  perform pg_advisory_xact_lock(
    ('x' || substr(md5(p_order_id::text), 1, 16))::bit(64)::bigint
  );

  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null or v_order.wallet_release_processed_at is null then
    return false;
  end if;

  select coalesce(sum(amount), 0) into v_amt
  from public.wallet_transactions
  where order_id = p_order_id
    and type = 'venda'
    and amount > 0;

  if v_amt <= 0 then
    return false;
  end if;

  -- Evitar clawback duplicado
  if exists (
    select 1 from public.wallet_transactions
    where order_id = p_order_id
      and type = 'estorno'
      and amount >= v_amt
  ) then
    return false;
  end if;

  insert into public.wallet_transactions (
    wallet_id,
    order_id,
    amount,
    type,
    description
  ) values (
    v_order.seller_id,
    p_order_id,
    v_amt,
    'estorno',
    'Clawback: disputa aberta após libertação'
  );

  update public.wallets
     set balance = round(balance - v_amt, 2)
   where id = v_order.seller_id;

  update public.orders
     set wallet_release_processed_at = null
   where id = p_order_id;

  return true;
end;
$$;

revoke all on function public.batata_clawback_seller_release_for_dispute(uuid)
  from public, anon, authenticated;
grant execute on function public.batata_clawback_seller_release_for_dispute(uuid)
  to service_role;

create or replace function public.batata_order_disputes_guard_release_lock()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_released timestamptz;
begin
  if NEW.order_id is null then
    return NEW;
  end if;

  -- Mesmo cadeado que batata_release_seller_wallet_for_order
  perform pg_advisory_xact_lock(
    ('x' || substr(md5(NEW.order_id::text), 1, 16))::bit(64)::bigint
  );

  select wallet_release_processed_at into v_released
  from public.orders
  where id = NEW.order_id
  for update;

  if v_released is not null then
    perform public.batata_clawback_seller_release_for_dispute(NEW.order_id);
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_order_disputes_release_lock on public.order_disputes;
create trigger trg_batata_order_disputes_release_lock
  before insert on public.order_disputes
  for each row
  execute function public.batata_order_disputes_guard_release_lock();

-- ===========================================================================
-- DT — claim: wait mais longo no Edge; mutex buyer cobre até cs_
-- (SQL: alargar expires mutex + re-check cs_ em qualquer line do buyer overlap)
-- ===========================================================================
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

  -- Qualquer cs_ já nestas lines → reuse (fail-closed)
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
