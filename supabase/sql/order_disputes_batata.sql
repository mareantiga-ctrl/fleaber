-- Fleaber BATATA: disputas de encomendas.
-- Executar no SQL Editor do Supabase.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.order_disputes (
  id uuid primary key default extensions.gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  -- Sem FK para profiles: neste projeto profiles.id não está garantido como UNIQUE/PK.
  -- A RLS abaixo valida buyer_id contra orders.buyer_id e auth.uid().
  buyer_id uuid not null,
  reason text not null check (
    reason in ('danificado', 'nao_corresponde', 'em_falta', 'outro')
  ),
  description text not null default '',
  proof_photos text[] not null default '{}',
  current_turn text not null default 'vendedor' check (
    current_turn in ('vendedor', 'comprador', 'administracao')
  ),
  next_deadline timestamptz not null default (now() + interval '72 hours'),
  status text not null default 'aberta' check (
    status in (
      'aberta',
      'respondida_vendedor',
      'respondida_comprador',
      'escalada_fleaber',
      'resolvida',
      'recusada'
    )
  ),
  seller_offer_type text,
  seller_pays_return_shipping boolean not null default false,
  seller_refund_percent numeric(5, 2),
  buyer_decision text,
  return_label_created_at timestamptz,
  return_delivered_at timestamptz,
  seller_inspection_deadline timestamptz,
  seller_return_issue_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.order_disputes
  add column if not exists current_turn text not null default 'vendedor',
  add column if not exists next_deadline timestamptz not null default (now() + interval '72 hours'),
  add column if not exists seller_offer_type text,
  add column if not exists seller_pays_return_shipping boolean not null default false,
  add column if not exists seller_refund_percent numeric(5, 2),
  add column if not exists buyer_decision text,
  add column if not exists return_label_created_at timestamptz,
  add column if not exists return_delivered_at timestamptz,
  add column if not exists seller_inspection_deadline timestamptz,
  add column if not exists seller_return_issue_at timestamptz;

alter table public.order_disputes
  drop constraint if exists order_disputes_current_turn_check,
  add constraint order_disputes_current_turn_check
  check (current_turn in ('vendedor', 'comprador', 'administracao'));

alter table public.order_disputes
  drop constraint if exists order_disputes_status_check,
  add constraint order_disputes_status_check
  check (
    status in (
      'aberta',
      'respondida_vendedor',
      'respondida_comprador',
      'escalada_fleaber',
      'resolvida',
      'recusada'
    )
  );

create table if not exists public.order_dispute_replies (
  id uuid primary key default extensions.gen_random_uuid(),
  dispute_id uuid not null references public.order_disputes(id) on delete cascade,
  sender_id uuid not null,
  message text not null default '',
  proof_photos text[] not null default '{}',
  created_at timestamptz not null default now()
);

drop index if exists public.order_disputes_order_open_uidx;
create unique index order_disputes_order_open_uidx
  on public.order_disputes (order_id)
  where status in (
    'aberta',
    'respondida_vendedor',
    'respondida_comprador',
    'escalada_fleaber'
  );

alter table public.order_disputes enable row level security;
alter table public.order_dispute_replies enable row level security;

drop policy if exists "order_disputes_select_participants" on public.order_disputes;
create policy "order_disputes_select_participants"
  on public.order_disputes
  for select
  using (
    buyer_id = auth.uid()
    or exists (
      select 1
      from public.orders o
      where o.id = order_disputes.order_id
        and o.seller_id = auth.uid()
    )
  );

drop policy if exists "order_disputes_insert_buyer" on public.order_disputes;
create policy "order_disputes_insert_buyer"
  on public.order_disputes
  for insert
  with check (
    buyer_id = auth.uid()
    and exists (
      select 1
      from public.orders o
      where o.id = order_disputes.order_id
        and o.buyer_id = auth.uid()
        and lower(coalesce(o.status, '')) in ('concluido', 'entregue')
        and o.wallet_release_processed_at is null
    )
  );

drop policy if exists "order_disputes_update_participants" on public.order_disputes;
create policy "order_disputes_update_participants"
  on public.order_disputes
  for update
  using (
    exists (
      select 1
      from public.orders o
      where o.id = order_disputes.order_id
        and (o.buyer_id = auth.uid() or o.seller_id = auth.uid())
    )
  )
  with check (
    exists (
      select 1
      from public.orders o
      where o.id = order_disputes.order_id
        and (o.buyer_id = auth.uid() or o.seller_id = auth.uid())
    )
  );

drop policy if exists "order_dispute_replies_select_participants" on public.order_dispute_replies;
create policy "order_dispute_replies_select_participants"
  on public.order_dispute_replies
  for select
  using (
    exists (
      select 1
      from public.order_disputes od
      join public.orders o on o.id = od.order_id
      where od.id = order_dispute_replies.dispute_id
        and (o.buyer_id = auth.uid() or o.seller_id = auth.uid())
    )
  );

drop policy if exists "order_dispute_replies_insert_participants" on public.order_dispute_replies;
create policy "order_dispute_replies_insert_participants"
  on public.order_dispute_replies
  for insert
  with check (
    sender_id = auth.uid()
    and exists (
      select 1
      from public.order_disputes od
      join public.orders o on o.id = od.order_id
      where od.id = order_dispute_replies.dispute_id
        and od.status <> 'escalada_fleaber'
        and od.status <> 'resolvida'
        and (o.buyer_id = auth.uid() or o.seller_id = auth.uid())
    )
  );

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
