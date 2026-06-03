-- Fleaber BATATA: gorjetas em direto (carteira + Stripe).
-- Executar no SQL Editor do Supabase após wallets_batata.sql.

create table if not exists public.live_tips (
  id uuid primary key default extensions.gen_random_uuid(),
  live_id uuid references public.lives(id) on delete set null,
  buyer_id uuid not null references auth.users(id) on delete cascade,
  seller_id uuid not null references auth.users(id) on delete cascade,
  amount numeric(12, 2) not null check (amount > 0),
  processing_fee numeric(12, 2) not null default 0 check (processing_fee >= 0),
  seller_amount numeric(12, 2) not null check (seller_amount >= 0),
  message text,
  payment_source text not null default 'wallet'
    check (payment_source in ('wallet', 'stripe')),
  status text not null default 'pending'
    check (status in ('pending', 'completed', 'failed', 'cancelled')),
  stripe_session_id text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create unique index if not exists live_tips_stripe_session_uidx
  on public.live_tips (stripe_session_id)
  where stripe_session_id is not null;

alter table public.live_tips enable row level security;

drop policy if exists "live_tips_select_participants" on public.live_tips;
create policy "live_tips_select_participants"
  on public.live_tips
  for select
  using (buyer_id = auth.uid() or seller_id = auth.uid());

alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_type_check;

alter table public.wallet_transactions
  add constraint wallet_transactions_type_check
  check (
    type in (
      'venda',
      'compra',
      'reembolso',
      'levantamento',
      'gorjeta_enviada',
      'gorjeta_recebida'
    )
  );

alter table public.wallet_transactions
  add column if not exists tip_id uuid references public.live_tips(id) on delete set null;

create unique index if not exists wallet_transactions_tip_type_uidx
  on public.wallet_transactions (wallet_id, tip_id, type)
  where tip_id is not null;

create or replace function public.batata_live_tip_processing_fee(p_amount numeric)
returns numeric
language sql
immutable
as $$
  select round(greatest(coalesce(p_amount, 0), 0) * 0.029 + 0.40, 2)::numeric(12, 2);
$$;

create or replace function public.batata_live_tip_seller_amount(p_amount numeric)
returns numeric
language sql
immutable
as $$
  select greatest(
    round(coalesce(p_amount, 0), 2) - public.batata_live_tip_processing_fee(p_amount),
    0
  )::numeric(12, 2);
$$;

create or replace function public.batata_wallet_apply_tip_once(
  p_wallet_id uuid,
  p_tip_id uuid,
  p_amount numeric,
  p_type text,
  p_description text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row_count integer := 0;
begin
  if p_wallet_id is null or p_tip_id is null then
    return false;
  end if;

  if coalesce(p_amount, 0) = 0 then
    return false;
  end if;

  perform public.batata_ensure_wallet(p_wallet_id);

  insert into public.wallet_transactions (
    wallet_id,
    amount,
    type,
    description,
    tip_id
  ) values (
    p_wallet_id,
    round(p_amount, 2),
    p_type,
    p_description,
    p_tip_id
  )
  on conflict (wallet_id, tip_id, type) where tip_id is not null do nothing;

  get diagnostics v_row_count = row_count;
  if v_row_count = 0 then
    return false;
  end if;

  update public.wallets
  set balance = round(balance + p_amount, 2)
  where id = p_wallet_id;

  return true;
end;
$$;

create or replace function public.batata_send_live_tip_from_wallet(
  p_live_id uuid,
  p_seller_id uuid,
  p_amount numeric,
  p_message text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer_id uuid := auth.uid();
  v_tip_id uuid;
  v_fee numeric;
  v_seller_amount numeric;
  v_balance numeric;
  v_live_seller uuid;
  v_note text;
begin
  if v_buyer_id is null then
    raise exception 'Tem de iniciar sessão para enviar gorjeta.';
  end if;

  if p_seller_id is null or p_seller_id = v_buyer_id then
    raise exception 'Vendedor inválido para gorjeta.';
  end if;

  if coalesce(p_amount, 0) < 1 then
    raise exception 'Valor mínimo de gorjeta: 1 €.';
  end if;

  if p_live_id is not null then
    select seller_id into v_live_seller
    from public.lives
    where id = p_live_id;

    if v_live_seller is null then
      raise exception 'Direto não encontrado.';
    end if;

    if v_live_seller <> p_seller_id then
      raise exception 'O vendedor não corresponde a este direto.';
    end if;
  end if;

  v_fee := public.batata_live_tip_processing_fee(p_amount);
  v_seller_amount := public.batata_live_tip_seller_amount(p_amount);
  v_note := nullif(trim(coalesce(p_message, '')), '');

  perform public.batata_ensure_wallet(v_buyer_id);
  perform public.batata_ensure_wallet(p_seller_id);

  select balance into v_balance
  from public.wallets
  where id = v_buyer_id
  for update;

  if coalesce(v_balance, 0) < round(p_amount, 2) then
    raise exception 'insufficient_wallet_balance';
  end if;

  insert into public.live_tips (
    live_id,
    buyer_id,
    seller_id,
    amount,
    processing_fee,
    seller_amount,
    message,
    payment_source,
    status,
    completed_at
  ) values (
    p_live_id,
    v_buyer_id,
    p_seller_id,
    round(p_amount, 2),
    v_fee,
    v_seller_amount,
    v_note,
    'wallet',
    'completed',
    now()
  )
  returning id into v_tip_id;

  if not public.batata_wallet_apply_tip_once(
    v_buyer_id,
    v_tip_id,
    -round(p_amount, 2),
    'gorjeta_enviada',
    coalesce(v_note, 'Gorjeta em direto')
  ) then
    raise exception 'Não foi possível debitar a carteira.';
  end if;

  if not public.batata_wallet_apply_tip_once(
    p_seller_id,
    v_tip_id,
    v_seller_amount,
    'gorjeta_recebida',
    coalesce(v_note, 'Gorjeta recebida em direto')
  ) then
    raise exception 'Não foi possível creditar o vendedor.';
  end if;

  return v_tip_id;
end;
$$;

create or replace function public.batata_create_live_tip_pending(
  p_live_id uuid,
  p_seller_id uuid,
  p_amount numeric,
  p_message text default null,
  p_stripe_session_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer_id uuid := auth.uid();
  v_tip_id uuid;
  v_fee numeric;
  v_seller_amount numeric;
  v_live_seller uuid;
  v_note text;
begin
  if v_buyer_id is null then
    raise exception 'Tem de iniciar sessão para enviar gorjeta.';
  end if;

  if p_seller_id is null or p_seller_id = v_buyer_id then
    raise exception 'Vendedor inválido para gorjeta.';
  end if;

  if coalesce(p_amount, 0) < 1 then
    raise exception 'Valor mínimo de gorjeta: 1 €.';
  end if;

  if p_live_id is not null then
    select seller_id into v_live_seller
    from public.lives
    where id = p_live_id;

    if v_live_seller is null then
      raise exception 'Direto não encontrado.';
    end if;

    if v_live_seller <> p_seller_id then
      raise exception 'O vendedor não corresponde a este direto.';
    end if;
  end if;

  v_fee := public.batata_live_tip_processing_fee(p_amount);
  v_seller_amount := public.batata_live_tip_seller_amount(p_amount);
  v_note := nullif(trim(coalesce(p_message, '')), '');

  insert into public.live_tips (
    live_id,
    buyer_id,
    seller_id,
    amount,
    processing_fee,
    seller_amount,
    message,
    payment_source,
    status,
    stripe_session_id
  ) values (
    p_live_id,
    v_buyer_id,
    p_seller_id,
    round(p_amount, 2),
    v_fee,
    v_seller_amount,
    v_note,
    'stripe',
    'pending',
    nullif(trim(coalesce(p_stripe_session_id, '')), '')
  )
  returning id into v_tip_id;

  return v_tip_id;
end;
$$;

create or replace function public.batata_settle_live_tip_from_stripe(
  p_tip_id uuid,
  p_stripe_session_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tip public.live_tips%rowtype;
  v_note text;
begin
  if p_tip_id is null then
    return false;
  end if;

  select * into v_tip
  from public.live_tips
  where id = p_tip_id
  for update;

  if not found then
    return false;
  end if;

  if v_tip.status = 'completed' then
    return true;
  end if;

  if v_tip.status <> 'pending' or v_tip.payment_source <> 'stripe' then
    return false;
  end if;

  v_note := coalesce(v_tip.message, 'Gorjeta em direto');

  perform public.batata_ensure_wallet(v_tip.seller_id);

  if not public.batata_wallet_apply_tip_once(
    v_tip.seller_id,
    v_tip.id,
    v_tip.seller_amount,
    'gorjeta_recebida',
    v_note
  ) then
    return false;
  end if;

  update public.live_tips
  set
    status = 'completed',
    completed_at = now(),
    stripe_session_id = coalesce(
      nullif(trim(coalesce(p_stripe_session_id, '')), ''),
      stripe_session_id
    )
  where id = v_tip.id;

  return true;
end;
$$;

grant execute on function public.batata_send_live_tip_from_wallet(uuid, uuid, numeric, text) to authenticated;
grant execute on function public.batata_create_live_tip_pending(uuid, uuid, numeric, text, text) to authenticated;
grant execute on function public.batata_settle_live_tip_from_stripe(uuid, text) to service_role;
