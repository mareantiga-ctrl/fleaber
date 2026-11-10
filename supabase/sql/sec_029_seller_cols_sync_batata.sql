-- SEC-029 — sync seller_id / vendedor_id + tip coalesce (BATATA)
-- Observe: 0 mismatches / 0 only-one-col. Trigger = higiene futura.
-- Tip: coalesce(seller_id, vendedor_id) — evita falso «Direto não encontrado».

-- 1) Backfill (no-op se já alinhado)
update public.lives
set seller_id = vendedor_id
where seller_id is null and vendedor_id is not null;

update public.lives
set vendedor_id = seller_id
where vendedor_id is null and seller_id is not null;

update public.lives
set vendedor_id = seller_id
where seller_id is not null
  and vendedor_id is not null
  and seller_id is distinct from vendedor_id;

-- 2) Trigger
create or replace function public.batata_lives_sync_seller_cols()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.seller_id is null and new.vendedor_id is not null then
    new.seller_id := new.vendedor_id;
  elsif new.vendedor_id is null and new.seller_id is not null then
    new.vendedor_id := new.seller_id;
  elsif new.seller_id is not null
    and new.vendedor_id is not null
    and new.seller_id is distinct from new.vendedor_id then
    new.vendedor_id := new.seller_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_batata_lives_sync_seller_cols on public.lives;
create trigger trg_batata_lives_sync_seller_cols
before insert or update of seller_id, vendedor_id
on public.lives
for each row
execute function public.batata_lives_sync_seller_cols();

-- 3) Tip RPCs — só o bloco lives (mantém resto igual ao live_tips_batata.sql)
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
    if not exists (select 1 from public.lives where id = p_live_id) then
      raise exception 'Direto não encontrado.';
    end if;

    select coalesce(seller_id, vendedor_id) into v_live_seller
    from public.lives
    where id = p_live_id;

    if v_live_seller is null then
      raise exception 'Direto sem vendedor.';
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
    if not exists (select 1 from public.lives where id = p_live_id) then
      raise exception 'Direto não encontrado.';
    end if;

    select coalesce(seller_id, vendedor_id) into v_live_seller
    from public.lives
    where id = p_live_id;

    if v_live_seller is null then
      raise exception 'Direto sem vendedor.';
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

notify pgrst, 'reload schema';
