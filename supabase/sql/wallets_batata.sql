-- Fleaber BATATA: carteiras, movimentos e estados de devolucao.
-- Executar no SQL Editor do Supabase.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.wallets (
  id uuid primary key references auth.users(id) on delete cascade,
  stripe_account_id text,
  balance numeric(12, 2) not null default 0.00,
  updated_at timestamptz not null default now()
);

create table if not exists public.wallet_transactions (
  id uuid primary key default extensions.gen_random_uuid(),
  wallet_id uuid not null references public.wallets(id) on delete cascade,
  amount numeric(12, 2) not null,
  type text not null check (type in ('venda', 'compra', 'reembolso', 'levantamento')),
  description text not null,
  created_at timestamptz not null default now(),
  order_id uuid
);

create table if not exists public.fleaber_commissions (
  id uuid primary key default extensions.gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  amount numeric(12, 2) not null,
  source text not null default 'protection_fee',
  description text not null default 'Taxa de Proteção Fleaber',
  created_at timestamptz not null default now()
);

alter table if exists public.orders
  add column if not exists returned_at timestamptz,
  add column if not exists wallet_release_processed_at timestamptz,
  add column if not exists wallet_refund_processed_at timestamptz;

do $$
declare
  v_constraint record;
begin
  for v_constraint in
    select conname, pg_get_constraintdef(oid) as definition
    from pg_constraint
    where conrelid = 'public.orders'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%status%'
  loop
    execute format('alter table public.orders drop constraint if exists %I', v_constraint.conname);
  end loop;
end;
$$;

alter table public.orders
  add constraint orders_status_batata_check
  check (
    status is null
    or status in (
      'reserva_pendente',
      'reservado',
      'pendente',
      'aguarda_confirmacao',
      'pago',
      'enviado',
      'entregue',
      'concluido',
      'cancelado',
      'pedido_devolucao',
      'em_devolucao',
      'devolucao_entregue',
      'disputa_devolucao_vendedor',
      'devolvida'
    )
  );

create unique index if not exists wallet_transactions_order_type_uidx
  on public.wallet_transactions (wallet_id, order_id, type)
  where order_id is not null;

create unique index if not exists fleaber_commissions_order_source_uidx
  on public.fleaber_commissions (order_id, source);

alter table public.wallets enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.fleaber_commissions enable row level security;

drop policy if exists "wallets_select_own" on public.wallets;
create policy "wallets_select_own"
  on public.wallets
  for select
  using (id = auth.uid());

drop policy if exists "wallets_insert_own" on public.wallets;
create policy "wallets_insert_own"
  on public.wallets
  for insert
  with check (id = auth.uid());

drop policy if exists "wallet_transactions_select_own" on public.wallet_transactions;
create policy "wallet_transactions_select_own"
  on public.wallet_transactions
  for select
  using (wallet_id = auth.uid());

drop policy if exists "fleaber_commissions_admin_select" on public.fleaber_commissions;
create policy "fleaber_commissions_admin_select"
  on public.fleaber_commissions
  for select
  using (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and lower(coalesce(p.user_type, '')) in (
          'admin',
          'admim',
          'administrador',
          'administracao'
        )
    )
  );

create or replace function public.batata_touch_wallet_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists batata_touch_wallet_updated_at_trg on public.wallets;
create trigger batata_touch_wallet_updated_at_trg
before update on public.wallets
for each row
execute function public.batata_touch_wallet_updated_at();

create or replace function public.batata_ensure_wallet(p_user_id uuid default auth.uid())
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user_id is null then
    raise exception 'Missing wallet user id.';
  end if;

  insert into public.wallets (id, balance)
  values (p_user_id, 0.00)
  on conflict (id) do nothing;

  return p_user_id;
end;
$$;

create or replace function public.batata_order_amount(p_order public.orders)
returns numeric
language plpgsql
stable
as $$
begin
  return greatest(coalesce(p_order.price_total, 0), 0)::numeric(12, 2);
end;
$$;

create or replace function public.batata_order_commission_amount(
  p_total numeric
)
returns numeric
language plpgsql
stable
as $$
declare
  v_total numeric := greatest(coalesce(p_total, 0), 0);
  v_protected_amount numeric;
begin
  if v_total <= 0 then
    return 0::numeric(12, 2);
  end if;

  -- total = protected_amount + 0.65 + protected_amount * 0.05
  v_protected_amount := greatest((v_total - 0.65) / 1.05, 0);
  return least(round(0.65 + (v_protected_amount * 0.05), 2), v_total)::numeric(12, 2);
end;
$$;

create or replace function public.batata_record_fleaber_commission_once(
  p_order_id uuid,
  p_amount numeric,
  p_source text default 'protection_fee',
  p_description text default 'Taxa de Proteção Fleaber'
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row_count integer := 0;
begin
  if p_order_id is null or coalesce(p_amount, 0) <= 0 then
    return false;
  end if;

  insert into public.fleaber_commissions (
    order_id,
    amount,
    source,
    description
  ) values (
    p_order_id,
    round(p_amount, 2),
    coalesce(nullif(trim(p_source), ''), 'protection_fee'),
    coalesce(nullif(trim(p_description), ''), 'Taxa de Proteção Fleaber')
  )
  on conflict (order_id, source) do nothing;

  get diagnostics v_row_count = row_count;
  return v_row_count > 0;
end;
$$;

create or replace function public.batata_credit_wallet_once(
  p_wallet_id uuid,
  p_order_id uuid,
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
  v_inserted boolean := false;
  v_row_count integer := 0;
begin
  if p_wallet_id is null or p_order_id is null then
    return false;
  end if;

  if coalesce(p_amount, 0) <= 0 then
    return false;
  end if;

  perform public.batata_ensure_wallet(p_wallet_id);

  insert into public.wallet_transactions (
    wallet_id,
    amount,
    type,
    description,
    order_id
  ) values (
    p_wallet_id,
    round(p_amount, 2),
    p_type,
    p_description,
    p_order_id
  )
  on conflict (wallet_id, order_id, type) where order_id is not null do nothing;

  get diagnostics v_row_count = row_count;
  v_inserted := v_row_count > 0;

  if v_inserted then
    update public.wallets
    set balance = round(balance + p_amount, 2)
    where id = p_wallet_id;
  end if;

  return v_inserted;
end;
$$;

create or replace function public.batata_release_seller_wallet_for_order(
  p_order_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_product_title text;
  v_amount numeric;
  v_done boolean;
begin
  select * into v_order
  from public.orders
  where id = p_order_id;

  if not found or v_order.seller_id is null then
    return false;
  end if;

  if auth.uid() is not null and auth.uid() <> v_order.buyer_id then
    return false;
  end if;

  if lower(coalesce(v_order.status, '')) not in ('concluido') then
    return false;
  end if;

  if v_order.wallet_release_processed_at is not null then
    return false;
  end if;

  select nullif(trim(title), '') into v_product_title
  from public.products
  where id = v_order.product_id;

  v_amount := greatest(
    public.batata_order_amount(v_order) -
    public.batata_order_commission_amount(public.batata_order_amount(v_order)),
    0
  );
  v_done := public.batata_credit_wallet_once(
    v_order.seller_id,
    v_order.id,
    v_amount,
    'venda',
    'Venda de ' || coalesce(v_product_title, 'artigo Fleaber')
  );

  if v_done then
    perform public.batata_record_fleaber_commission_once(
      v_order.id,
      public.batata_order_commission_amount(public.batata_order_amount(v_order)),
      'protection_fee',
      'Taxa de Proteção Fleaber'
    );

    update public.orders
    set wallet_release_processed_at = now()
    where id = v_order.id;
  end if;

  return v_done;
end;
$$;

create or replace function public.batata_process_partial_refund_dispute(
  p_order_id uuid,
  p_refund_percent numeric
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_total numeric;
  v_percent numeric;
  v_refund numeric;
  v_commission numeric;
  v_seller_amount numeric;
  v_buyer_done boolean := false;
  v_seller_done boolean := false;
begin
  select * into v_order
  from public.orders
  where id = p_order_id;

  if not found or v_order.buyer_id is null or v_order.seller_id is null then
    return false;
  end if;

  if v_order.wallet_release_processed_at is not null
     or v_order.wallet_refund_processed_at is not null then
    return false;
  end if;

  v_total := public.batata_order_amount(v_order);
  v_percent := least(greatest(coalesce(p_refund_percent, 0), 0), 100);
  if v_total <= 0 or v_percent <= 0 then
    return false;
  end if;

  v_refund := round(v_total * (v_percent / 100), 2);
  v_commission := public.batata_order_commission_amount(v_total);
  v_seller_amount := greatest(round(v_total - v_refund - v_commission, 2), 0);

  v_buyer_done := public.batata_credit_wallet_once(
    v_order.buyer_id,
    v_order.id,
    v_refund,
    'reembolso',
    'Reembolso parcial de ' || round(v_percent, 2)::text || '%'
  );

  v_seller_done := public.batata_credit_wallet_once(
    v_order.seller_id,
    v_order.id,
    v_seller_amount,
    'venda',
    'Valor restante após reembolso parcial'
  );

  perform public.batata_record_fleaber_commission_once(
    v_order.id,
    v_commission,
    'protection_fee',
    'Taxa de Proteção Fleaber'
  );

  update public.orders
  set wallet_release_processed_at = now(),
      wallet_refund_processed_at = now()
  where id = v_order.id;

  return v_buyer_done or v_seller_done;
end;
$$;

create or replace function public.batata_refund_buyer_wallet_for_order(
  p_order_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_amount numeric;
  v_done boolean;
begin
  select * into v_order
  from public.orders
  where id = p_order_id;

  if not found or v_order.buyer_id is null then
    return false;
  end if;

  if lower(coalesce(v_order.status, '')) <> 'devolvida' then
    return false;
  end if;

  if v_order.wallet_refund_processed_at is not null then
    return false;
  end if;

  v_amount := public.batata_order_amount(v_order);
  v_done := public.batata_credit_wallet_once(
    v_order.buyer_id,
    v_order.id,
    v_amount,
    'reembolso',
    'Reembolso Encomenda #' || left(v_order.id::text, 8)
  );

  if v_done then
    update public.orders
    set wallet_refund_processed_at = now(),
        returned_at = coalesce(returned_at, now())
    where id = v_order.id;
  end if;

  return v_done;
end;
$$;

create or replace function public.batata_wallet_order_status_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if lower(coalesce(new.status, '')) = 'devolvida' then
    perform public.batata_refund_buyer_wallet_for_order(new.id);
  end if;

  return new;
end;
$$;

drop trigger if exists batata_wallet_order_status_trg on public.orders;
create trigger batata_wallet_order_status_trg
after insert or update of status on public.orders
for each row
execute function public.batata_wallet_order_status_trigger();

create or replace function public.batata_release_wallet_on_positive_buyer_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.order_id is not null
     and coalesce(new.stars, 0) >= 4
     and lower(coalesce(new.author_role, '')) in ('comprador', 'buyer') then
    perform public.batata_release_seller_wallet_for_order(new.order_id);
  end if;

  return new;
end;
$$;

drop trigger if exists batata_release_wallet_on_positive_buyer_review_trg
  on public.reviews;

create trigger batata_release_wallet_on_positive_buyer_review_trg
after insert on public.reviews
for each row
execute function public.batata_release_wallet_on_positive_buyer_review();

create or replace function public.batata_wallet_review_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if new.order_id is null then
    return new;
  end if;

  if new.author_role not in ('buyer', 'comprador') then
    return new;
  end if;

  if coalesce(new.stars, 0) < 4 then
    return new;
  end if;

  select * into v_order
  from public.orders
  where id = new.order_id;

  if found and lower(coalesce(v_order.status, '')) = 'concluido' then
    perform public.batata_release_seller_wallet_for_order(new.order_id);
  end if;

  return new;
end;
$$;

drop trigger if exists batata_wallet_review_trg on public.reviews;
create trigger batata_wallet_review_trg
after insert on public.reviews
for each row
execute function public.batata_wallet_review_trigger();
