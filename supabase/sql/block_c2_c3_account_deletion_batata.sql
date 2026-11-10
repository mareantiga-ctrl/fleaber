-- Block C2/C3: account deletion request + anonymize (produção segura).
-- NÃO apaga encomendas/comissões/disputas. Anonimiza PII; bloqueia login via edge.
-- Staging nuke (delete-test-account) permanece separado.

-- ---------------------------------------------------------------------------
-- Colunas + tabela de pedidos
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists deletion_requested_at timestamptz,
  add column if not exists anonymized_at timestamptz;

create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  user_id uuid,
  facebook_user_id text,
  confirmation_code text not null unique,
  source text not null check (source in ('app', 'meta', 'admin', 'email')),
  status text not null default 'received'
    check (status in (
      'received',
      'blocked_active_obligations',
      'anonymized',
      'completed',
      'manual_review'
    )),
  block_reasons jsonb,
  result jsonb,
  notes text
);

create index if not exists account_deletion_requests_user_idx
  on public.account_deletion_requests (user_id);
create index if not exists account_deletion_requests_fb_idx
  on public.account_deletion_requests (facebook_user_id);
create index if not exists account_deletion_requests_code_idx
  on public.account_deletion_requests (confirmation_code);

alter table public.account_deletion_requests enable row level security;

drop policy if exists "account_deletion_requests_select_own" on public.account_deletion_requests;
create policy "account_deletion_requests_select_own"
  on public.account_deletion_requests for select to authenticated
  using (user_id = auth.uid());

-- Sem INSERT/UPDATE/DELETE para authenticated — só service_role / security definer.

revoke all on table public.account_deletion_requests from anon;
revoke all on table public.account_deletion_requests from authenticated;
grant select on table public.account_deletion_requests to authenticated;
grant all on table public.account_deletion_requests to service_role;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.batata_account_has_active_obligations(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_active_orders int := 0;
  v_open_disputes int := 0;
  v_active_lives int := 0;
  v_wallet_balance numeric := 0;
  v_reasons text[] := '{}';
begin
  if p_user_id is null then
    return jsonb_build_object('blocked', true, 'reasons', jsonb_build_array('user_id_required'));
  end if;

  select count(*)::int into v_active_orders
  from public.orders o
  where (o.buyer_id = p_user_id or o.seller_id = p_user_id)
    and lower(trim(coalesce(o.status, ''))) not in (
      'concluido', 'concluído', 'cancelado', 'cancelled', 'devolvida'
    );

  select count(*)::int into v_open_disputes
  from public.order_disputes d
  join public.orders o on o.id = d.order_id
  where (o.buyer_id = p_user_id or o.seller_id = p_user_id)
    and lower(trim(coalesce(d.status, ''))) is distinct from 'recusada'
    and lower(trim(coalesce(d.status, ''))) is distinct from 'resolvida'
    and lower(trim(coalesce(d.status, ''))) is distinct from 'fechada';

  begin
    select count(*)::int into v_active_lives
    from public.lives l
    where coalesce(l.seller_id, l.vendedor_id) = p_user_id
      and coalesce(l.is_active, false) = true;
  exception when undefined_table then
    v_active_lives := 0;
  end;

  begin
    select coalesce(w.balance, 0) into v_wallet_balance
    from public.wallets w
    where w.id = p_user_id;
  exception when others then
    v_wallet_balance := 0;
  end;

  if v_active_orders > 0 then
    v_reasons := array_append(v_reasons, 'active_orders:' || v_active_orders::text);
  end if;
  if v_open_disputes > 0 then
    v_reasons := array_append(v_reasons, 'open_disputes:' || v_open_disputes::text);
  end if;
  if v_active_lives > 0 then
    v_reasons := array_append(v_reasons, 'active_lives:' || v_active_lives::text);
  end if;
  if coalesce(v_wallet_balance, 0) > 0.009 then
    v_reasons := array_append(v_reasons, 'wallet_balance:' || v_wallet_balance::text);
  end if;

  return jsonb_build_object(
    'blocked', coalesce(array_length(v_reasons, 1), 0) > 0,
    'reasons', to_jsonb(v_reasons),
    'active_orders', v_active_orders,
    'open_disputes', v_open_disputes,
    'active_lives', v_active_lives,
    'wallet_balance', v_wallet_balance
  );
end;
$fn$;

revoke all on function public.batata_account_has_active_obligations(uuid) from public;
grant execute on function public.batata_account_has_active_obligations(uuid) to service_role;
grant execute on function public.batata_account_has_active_obligations(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Anonimizar (idempotente). NÃO apaga orders / commissions.
-- ---------------------------------------------------------------------------
create or replace function public.batata_anonymize_account_for_deletion(
  p_user_id uuid,
  p_source text default 'app',
  p_confirmation_code text default null,
  p_facebook_user_id text default null,
  p_force_pii_only boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_obligations jsonb;
  v_blocked boolean := false;
  v_code text;
  v_status text;
  v_already boolean := false;
  v_products int := 0;
  v_lives int := 0;
  v_fav int := 0;
  v_res int := 0;
begin
  if p_user_id is null then
    raise exception 'user_id_required' using errcode = '22023';
  end if;

  select (p.anonymized_at is not null) into v_already
  from public.profiles p
  where p.id = p_user_id;
  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'profile_not_found',
      'user_id', p_user_id
    );
  end if;

  v_code := coalesce(
    nullif(trim(p_confirmation_code), ''),
    'DEL-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))
  );

  v_obligations := public.batata_account_has_active_obligations(p_user_id);
  v_blocked := coalesce((v_obligations->>'blocked')::boolean, false);

  if v_blocked and not p_force_pii_only then
    insert into public.account_deletion_requests (
      user_id, facebook_user_id, confirmation_code, source, status, block_reasons, result
    ) values (
      p_user_id,
      nullif(trim(coalesce(p_facebook_user_id, '')), ''),
      v_code,
      coalesce(nullif(trim(p_source), ''), 'app'),
      'blocked_active_obligations',
      v_obligations->'reasons',
      v_obligations
    )
    on conflict (confirmation_code) do update
      set updated_at = now(),
          status = excluded.status,
          block_reasons = excluded.block_reasons,
          result = excluded.result;

    update public.profiles
    set deletion_requested_at = coalesce(deletion_requested_at, now())
    where id = p_user_id;

    return jsonb_build_object(
      'ok', false,
      'blocked', true,
      'status', 'blocked_active_obligations',
      'confirmation_code', v_code,
      'obligations', v_obligations,
      'already_anonymized', v_already
    );
  end if;

  -- PII wipe (sempre quando não bloqueado, ou force_pii_only).
  update public.profiles
  set
    full_name = 'Conta eliminada',
    photo_url = null,
    phone = null,
    phone_verified_at = null,
    location = null,
    shipping_line1 = null,
    shipping_line2 = null,
    shipping_postal_code = null,
    shipping_city = null,
    mb_way = null,
    iban = null,
    external_payments_enabled = false,
    legal_full_name = null,
    hub_bio = null,
    handle = null,
    hub_published = false,
    vacation_mode = true,
    is_live = false,
    deletion_requested_at = coalesce(deletion_requested_at, now()),
    anonymized_at = coalesce(anonymized_at, now())
  where id = p_user_id;

  begin
    update public.products
    set list_on_marketplace = false,
        is_sold = true
    where seller_id = p_user_id
      and coalesce(list_on_marketplace, true) = true;
    get diagnostics v_products = row_count;
  exception when others then
    v_products := 0;
  end;

  begin
    update public.lives
    set is_active = false,
        status = 'ended',
        ended_at = coalesce(ended_at, now())
    where coalesce(seller_id, vendedor_id) = p_user_id
      and coalesce(is_active, false) = true;
    get diagnostics v_lives = row_count;
  exception when others then
    v_lives := 0;
  end;

  begin
    delete from public.favorites where user_id = p_user_id;
    get diagnostics v_fav = row_count;
  exception when others then
    v_fav := 0;
  end;

  -- Cancelar só holds pré-pago (não pagos).
  begin
    update public.orders
    set status = 'cancelado'
    where (buyer_id = p_user_id or seller_id = p_user_id)
      and lower(trim(coalesce(status, ''))) in (
        'reserva_pendente', 'reservado', 'pendente',
        'aguarda_confirmacao', 'aguarda_pagamento'
      )
      and coalesce(amount_paid_cents, 0) = 0
      and coalesce(nullif(trim(stripe_payment_intent_id), ''), '') = '';
    get diagnostics v_res = row_count;
  exception when others then
    v_res := 0;
  end;

  begin
    update public.live_reservation_requests
    set status = 'cancelled'
    where (buyer_id = p_user_id or seller_id = p_user_id)
      and lower(trim(coalesce(status, ''))) in ('pending', 'accepted');
  exception when others then
    null;
  end;

  v_status := case
    when v_blocked and p_force_pii_only then 'manual_review'
    else 'anonymized'
  end;

  insert into public.account_deletion_requests (
    user_id, facebook_user_id, confirmation_code, source, status, block_reasons, result
  ) values (
    p_user_id,
    nullif(trim(coalesce(p_facebook_user_id, '')), ''),
    v_code,
    coalesce(nullif(trim(p_source), ''), 'app'),
    v_status,
    case when v_blocked then v_obligations->'reasons' else null end,
    jsonb_build_object(
      'products_unlisted', v_products,
      'lives_ended', v_lives,
      'favorites_removed', v_fav,
      'prepay_orders_cancelled', v_res,
      'obligations', v_obligations,
      'already_anonymized', v_already
    )
  )
  on conflict (confirmation_code) do update
    set updated_at = now(),
        status = excluded.status,
        result = excluded.result;

  return jsonb_build_object(
    'ok', true,
    'blocked', v_blocked,
    'status', v_status,
    'confirmation_code', v_code,
    'user_id', p_user_id,
    'products_unlisted', v_products,
    'lives_ended', v_lives,
    'favorites_removed', v_fav,
    'prepay_orders_cancelled', v_res,
    'already_anonymized', v_already,
    'ban_auth_recommended', true
  );
end;
$fn$;

revoke all on function public.batata_anonymize_account_for_deletion(uuid, text, text, text, boolean) from public;
revoke all on function public.batata_anonymize_account_for_deletion(uuid, text, text, text, boolean) from anon;
revoke all on function public.batata_anonymize_account_for_deletion(uuid, text, text, text, boolean) from authenticated;
grant execute on function public.batata_anonymize_account_for_deletion(uuid, text, text, text, boolean) to service_role;

-- JWT self-service wrapper (não ban auth — edge faz ban/delete identity).
create or replace function public.batata_request_account_deletion(p_confirmation_code text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  return public.batata_anonymize_account_for_deletion(
    v_uid,
    'app',
    p_confirmation_code,
    null,
    false
  );
end;
$fn$;

revoke all on function public.batata_request_account_deletion(text) from public;
grant execute on function public.batata_request_account_deletion(text) to authenticated;
grant execute on function public.batata_request_account_deletion(text) to service_role;

comment on function public.batata_anonymize_account_for_deletion(uuid, text, text, text, boolean) is
  'Block C2/C3: anonimiza PII; não apaga histórico financeiro. Idempotente.';

notify pgrst, 'reload schema';
