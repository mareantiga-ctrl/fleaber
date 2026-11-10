-- ZIP 171-C1: ambientes Stripe/DPD sticky por encomenda (default TEST+QA).
-- NÃO activa Stripe LIVE nem DPD comercial. Combinações reais = PENDENTE GO + secrets dual.

create table if not exists public.ops_env_sessions (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users (id),
  stripe_mode text not null check (stripe_mode in ('test', 'live')),
  dpd_mode text not null check (dpd_mode in ('qa', 'commercial')),
  reason text not null check (char_length(trim(reason)) >= 3),
  confirm_real boolean not null default false,
  is_active boolean not null default true,
  closed_at timestamptz,
  closed_by uuid references auth.users (id),
  note text
);

create index if not exists ops_env_sessions_active_idx
  on public.ops_env_sessions (is_active, created_at desc)
  where is_active;

create table if not exists public.ops_env_audit (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  actor_id uuid references auth.users (id),
  action text not null,
  stripe_mode text,
  dpd_mode text,
  order_id uuid,
  session_id uuid,
  detail jsonb not null default '{}'::jsonb
);

create index if not exists ops_env_audit_created_at_idx
  on public.ops_env_audit (created_at desc);

alter table public.orders
  add column if not exists ops_stripe_mode text,
  add column if not exists ops_dpd_mode text,
  add column if not exists ops_env_session_id uuid;

-- Backfill seguro: tudo TEST+QA
update public.orders
set ops_stripe_mode = coalesce(ops_stripe_mode, 'test'),
    ops_dpd_mode = coalesce(ops_dpd_mode, 'qa')
where ops_stripe_mode is null or ops_dpd_mode is null;

alter table public.orders
  alter column ops_stripe_mode set default 'test',
  alter column ops_dpd_mode set default 'qa';

do $chk$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_ops_stripe_mode_chk'
  ) then
    alter table public.orders
      add constraint orders_ops_stripe_mode_chk
      check (ops_stripe_mode in ('test', 'live'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_ops_dpd_mode_chk'
  ) then
    alter table public.orders
      add constraint orders_ops_dpd_mode_chk
      check (ops_dpd_mode in ('qa', 'commercial'));
  end if;
end;
$chk$;

comment on column public.orders.ops_stripe_mode is
  'ZIP171: sticky Stripe mode da encomenda (default test).';
comment on column public.orders.ops_dpd_mode is
  'ZIP171: sticky DPD mode da encomenda (default qa).';

alter table public.ops_env_sessions enable row level security;
alter table public.ops_env_audit enable row level security;

revoke all on table public.ops_env_sessions from public, anon, authenticated;
revoke all on table public.ops_env_audit from public, anon, authenticated;
grant select, insert, update on table public.ops_env_sessions to service_role;
grant select, insert on table public.ops_env_audit to service_role;
grant usage, select on sequence public.ops_env_audit_id_seq to service_role;

create or replace function public.batata_is_platform_admin(p_uid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = p_uid
      and lower(trim(coalesce(p.user_type, ''))) in (
        'admin', 'admim', 'administrador', 'administracao'
      )
  );
$$;

revoke all on function public.batata_is_platform_admin(uuid) from public, anon;
grant execute on function public.batata_is_platform_admin(uuid) to authenticated, service_role;

-- Lista sessões (admin)
create or replace function public.batata_admin_ops_env_list(p_limit int default 30)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.batata_is_platform_admin(v_uid) then
    raise exception 'not_admin';
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(s) order by s.created_at desc)
    from (
      select id, created_at, created_by, stripe_mode, dpd_mode, reason,
             confirm_real, is_active, closed_at, note
      from public.ops_env_sessions
      order by created_at desc
      limit greatest(1, least(coalesce(p_limit, 30), 100))
    ) s
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.batata_admin_ops_env_list(int) from public, anon;
grant execute on function public.batata_admin_ops_env_list(int) to authenticated, service_role;

-- Criar sessão de teste (default TEST+QA). LIVE/COMERCIAL exige confirm_real=true + reason.
create or replace function public.batata_admin_ops_env_open(
  p_stripe_mode text,
  p_dpd_mode text,
  p_reason text,
  p_confirm_real boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_stripe text := lower(trim(coalesce(p_stripe_mode, 'test')));
  v_dpd text := lower(trim(coalesce(p_dpd_mode, 'qa')));
  v_reason text := trim(coalesce(p_reason, ''));
  v_id uuid;
  v_needs_confirm boolean;
begin
  if v_uid is null or not public.batata_is_platform_admin(v_uid) then
    raise exception 'not_admin';
  end if;
  if v_stripe not in ('test', 'live') then
    raise exception 'invalid_stripe_mode';
  end if;
  if v_dpd not in ('qa', 'commercial') then
    raise exception 'invalid_dpd_mode';
  end if;
  if char_length(v_reason) < 3 then
    raise exception 'reason_required';
  end if;

  v_needs_confirm := (v_stripe = 'live' or v_dpd = 'commercial');
  if v_needs_confirm and coalesce(p_confirm_real, false) is not true then
    raise exception 'confirm_real_required';
  end if;

  -- Uma sessão activa de cada vez (não afecta Edge secrets — só binding admin/RT).
  update public.ops_env_sessions
  set is_active = false,
      closed_at = now(),
      closed_by = v_uid
  where is_active;

  insert into public.ops_env_sessions (
    created_by, stripe_mode, dpd_mode, reason, confirm_real, is_active, note
  ) values (
    v_uid, v_stripe, v_dpd, v_reason, coalesce(p_confirm_real, false), true,
    case when v_needs_confirm
      then 'PENDENTE_GO: execução LIVE/COMERCIAL recusada nas Edges até secrets dual + autorização'
      else 'TEST+QA ready'
    end
  )
  returning id into v_id;

  insert into public.ops_env_audit (actor_id, action, stripe_mode, dpd_mode, session_id, detail)
  values (
    v_uid, 'session_open', v_stripe, v_dpd, v_id,
    jsonb_build_object('confirm_real', coalesce(p_confirm_real, false), 'reason', v_reason)
  );

  return jsonb_build_object(
    'ok', true,
    'session_id', v_id,
    'stripe_mode', v_stripe,
    'dpd_mode', v_dpd,
    'execution_ready', (v_stripe = 'test' and v_dpd = 'qa'),
    'note', case when v_needs_confirm
      then 'Sessão registada; pagamentos/etiquetas reais continuam bloqueados até GO.'
      else 'Sessão TEST+QA activa para binding em encomendas de teste.'
    end
  );
end;
$$;

revoke all on function public.batata_admin_ops_env_open(text, text, text, boolean) from public, anon;
grant execute on function public.batata_admin_ops_env_open(text, text, text, boolean)
  to authenticated, service_role;

-- Fechar sessão activa
create or replace function public.batata_admin_ops_env_close(p_session_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if v_uid is null or not public.batata_is_platform_admin(v_uid) then
    raise exception 'not_admin';
  end if;
  update public.ops_env_sessions
  set is_active = false, closed_at = now(), closed_by = v_uid
  where is_active
    and (p_session_id is null or id = p_session_id)
  returning id into v_id;

  insert into public.ops_env_audit (actor_id, action, session_id, detail)
  values (v_uid, 'session_close', v_id, '{}'::jsonb);

  return jsonb_build_object('ok', true, 'closed_session_id', v_id);
end;
$$;

revoke all on function public.batata_admin_ops_env_close(uuid) from public, anon;
grant execute on function public.batata_admin_ops_env_close(uuid) to authenticated, service_role;

-- Bind sticky env a uma encomenda (só se ainda não paga / sem PI)
create or replace function public.batata_admin_ops_env_bind_order(
  p_order_id uuid,
  p_session_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_sess public.ops_env_sessions%rowtype;
  v_ord public.orders%rowtype;
begin
  if v_uid is null or not public.batata_is_platform_admin(v_uid) then
    raise exception 'not_admin';
  end if;

  select * into v_ord from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'order_not_found';
  end if;
  if coalesce(v_ord.stripe_payment_intent_id, '') <> ''
     or coalesce(v_ord.status, '') in ('pago', 'enviado', 'entregue', 'concluido') then
    raise exception 'order_already_in_payment_cycle';
  end if;

  if p_session_id is null then
    select * into v_sess from public.ops_env_sessions
    where is_active order by created_at desc limit 1;
  else
    select * into v_sess from public.ops_env_sessions where id = p_session_id;
  end if;
  if not found then
    raise exception 'session_not_found';
  end if;

  update public.orders
  set ops_stripe_mode = v_sess.stripe_mode,
      ops_dpd_mode = v_sess.dpd_mode,
      ops_env_session_id = v_sess.id
  where id = p_order_id;

  insert into public.ops_env_audit (
    actor_id, action, stripe_mode, dpd_mode, order_id, session_id, detail
  ) values (
    v_uid, 'order_bind', v_sess.stripe_mode, v_sess.dpd_mode, p_order_id, v_sess.id,
    jsonb_build_object('prev_stripe', v_ord.ops_stripe_mode, 'prev_dpd', v_ord.ops_dpd_mode)
  );

  return jsonb_build_object(
    'ok', true,
    'order_id', p_order_id,
    'stripe_mode', v_sess.stripe_mode,
    'dpd_mode', v_sess.dpd_mode,
    'execution_ready', (v_sess.stripe_mode = 'test' and v_sess.dpd_mode = 'qa')
  );
end;
$$;

revoke all on function public.batata_admin_ops_env_bind_order(uuid, uuid) from public, anon;
grant execute on function public.batata_admin_ops_env_bind_order(uuid, uuid)
  to authenticated, service_role;

-- Estado actual (admin)
create or replace function public.batata_admin_ops_env_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_sess jsonb;
begin
  if v_uid is null or not public.batata_is_platform_admin(v_uid) then
    raise exception 'not_admin';
  end if;
  select to_jsonb(s) into v_sess
  from (
    select id, created_at, created_by, stripe_mode, dpd_mode, reason,
           confirm_real, is_active, note
    from public.ops_env_sessions
    where is_active
    order by created_at desc
    limit 1
  ) s;

  return jsonb_build_object(
    'ok', true,
    'default_for_new_orders', jsonb_build_object('stripe_mode','test','dpd_mode','qa'),
    'active_session', v_sess,
    'matrix', jsonb_build_object(
      'test_qa', 'functional',
      'live_qa', 'pendente_go_dual_secrets',
      'test_commercial', 'pendente_go_dpd_live',
      'live_commercial', 'pendente_go_dual_secrets'
    )
  );
end;
$$;

revoke all on function public.batata_admin_ops_env_status() from public, anon;
grant execute on function public.batata_admin_ops_env_status() to authenticated, service_role;
