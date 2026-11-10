-- 119.9 — Pedido de alteração de estatuto (sair de profissional)
-- + dados públicos sem telefone/email no checkout
-- BATATA: não enfraquecer RLS / admin-only.

-- 1) Colunas de pedido para deixar de ser profissional
alter table public.seller_trade_profiles
  add column if not exists leave_request_pending boolean not null default false,
  add column if not exists leave_request_reason text,
  add column if not exists leave_requested_at timestamptz;

comment on column public.seller_trade_profiles.leave_request_pending is
  'Pedido para voltar a particular — só admin conclui.';

-- 2) Guard: cliente verified NÃO pode is_trader=false nem limpar verified
create or replace function public.seller_trade_profiles_guard_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_admin boolean := false;
  v_is_service boolean := false;
begin
  new.updated_at := now();
  v_is_service := coalesce(auth.jwt() ->> 'role', '') = 'service_role'
    or current_user in ('postgres', 'supabase_admin')
    or coalesce((select rolsuper from pg_roles where rolname = current_user), false);
  begin
    v_is_admin := public.batata_is_admin();
  exception when others then
    v_is_admin := false;
  end;

  if not v_is_service and not v_is_admin then
    if tg_op = 'UPDATE' then
      new.reviewed_at := old.reviewed_at;
      new.reviewed_by := old.reviewed_by;
      -- Cliente não altera flags de pedido excepto via RPC dedicada
      new.leave_request_pending := old.leave_request_pending;
      new.leave_request_reason := old.leave_request_reason;
      new.leave_requested_at := old.leave_requested_at;

      if new.verification_status in ('verified', 'rejected')
         and new.verification_status is distinct from old.verification_status then
        raise exception 'Aprovação ou rejeição só pela administração Fleaber';
      end if;
      if old.verification_status = 'verified'
         and new.verification_status is distinct from 'verified' then
        raise exception 'Não podes alterar o estado verificado';
      end if;
      -- Impedir «desligar» profissional aprovado no cliente
      if old.verification_status = 'verified'
         and old.is_trader = true
         and new.is_trader = false then
        raise exception
          'Para deixares de ser profissional, pede alteração de estatuto. A decisão é da Fleaber.';
      end if;
    end if;
    if tg_op = 'INSERT' and new.verification_status in ('verified', 'rejected') then
      raise exception 'Estado inicial inválido';
    end if;
  end if;

  if new.is_trader = false then
    new.verification_status := 'none';
    new.rejection_reason := null;
    new.submitted_at := null;
    new.leave_request_pending := false;
    new.leave_request_reason := null;
    new.leave_requested_at := null;
    if not v_is_admin and not v_is_service then
      new.reviewed_at := null;
      new.reviewed_by := null;
    end if;
  elsif new.is_trader = true
        and new.verification_status in ('none') then
    new.verification_status := 'incomplete';
  end if;
  return new;
end;
$$;

-- 3) RPC: pedir para sair de profissional
create or replace function public.seller_trade_request_leave(p_reason text default null)
returns public.seller_trade_profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.seller_trade_profiles;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if v_uid is null then
    raise exception 'Não autenticado';
  end if;
  select * into v_row
  from public.seller_trade_profiles
  where user_id = v_uid
  for update;
  if not found
     or v_row.is_trader is not true
     or coalesce(v_row.verification_status, 'none') <> 'verified' then
    raise exception 'Só vendedores profissionais aprovados podem pedir alteração de estatuto';
  end if;
  if v_row.leave_request_pending then
    raise exception 'Já tens um pedido de alteração em análise';
  end if;
  update public.seller_trade_profiles
  set leave_request_pending = true,
      leave_request_reason = v_reason,
      leave_requested_at = now(),
      updated_at = now()
  where user_id = v_uid
  returning * into v_row;
  return v_row;
end;
$$;

grant execute on function public.seller_trade_request_leave(text) to authenticated;

-- 4) RPC admin: decidir pedido de saída
create or replace function public.seller_trade_admin_decide_leave(
  p_user_id uuid,
  p_approve boolean,
  p_reason text default null
)
returns public.seller_trade_profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.seller_trade_profiles;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if not public.batata_is_admin()
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and current_user not in ('postgres', 'supabase_admin') then
    raise exception 'forbidden';
  end if;
  select * into v_row
  from public.seller_trade_profiles
  where user_id = p_user_id
  for update;
  if not found or not coalesce(v_row.leave_request_pending, false) then
    raise exception 'Não há pedido de alteração de estatuto para este utilizador';
  end if;
  if p_approve then
    update public.seller_trade_profiles
    set is_trader = false,
        verification_status = 'none',
        leave_request_pending = false,
        leave_request_reason = null,
        leave_requested_at = null,
        rejection_reason = null,
        reviewed_at = now(),
        reviewed_by = auth.uid(),
        updated_at = now()
    where user_id = p_user_id
    returning * into v_row;
  else
    update public.seller_trade_profiles
    set leave_request_pending = false,
        leave_request_reason = coalesce(v_reason, leave_request_reason),
        leave_requested_at = null,
        reviewed_at = now(),
        reviewed_by = auth.uid(),
        updated_at = now()
    where user_id = p_user_id
    returning * into v_row;
  end if;
  return v_row;
end;
$$;

grant execute on function public.seller_trade_admin_decide_leave(uuid, boolean, text)
  to authenticated;

-- 5) Info pública: sem telefone/email (só identificação comercial obrigatória)
drop function if exists public.seller_trade_public_info(uuid[]);
create or replace function public.seller_trade_public_info(p_seller_ids uuid[])
returns table (
  user_id uuid,
  is_professional boolean,
  professional_verified boolean,
  trade_name text,
  city text,
  country text,
  contact_email text,
  contact_phone text,
  sales_suspended boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.id as user_id,
    (coalesce(t.verification_status, 'none') = 'verified') as is_professional,
    (coalesce(t.verification_status, 'none') = 'verified') as professional_verified,
    case when coalesce(t.verification_status, 'none') = 'verified'
      then nullif(trim(t.trade_name), '') else null end as trade_name,
    case when coalesce(t.verification_status, 'none') = 'verified'
      then nullif(trim(t.city), '') else null end as city,
    case when coalesce(t.verification_status, 'none') = 'verified'
      then coalesce(nullif(trim(t.country), ''), 'PT') else null end as country,
    -- Contactos directos não expostos ao comprador (chat interno)
    null::text as contact_email,
    null::text as contact_phone,
    (
      coalesce(t.is_trader, false)
      and coalesce(t.verification_status, 'none') <> 'verified'
    ) as sales_suspended
  from unnest(p_seller_ids) as s(id)
  left join public.seller_trade_profiles t on t.user_id = s.id;
$$;

grant execute on function public.seller_trade_public_info(uuid[]) to authenticated;

-- 6) Fila admin: incluir pedidos de saída
drop function if exists public.seller_trade_admin_list_queue(text, int);
create or replace function public.seller_trade_admin_list_queue(
  p_status text default 'pending',
  p_limit int default 50
)
returns table (
  user_id uuid,
  full_name text,
  handle text,
  is_trader boolean,
  verification_status text,
  trade_name text,
  legal_name text,
  nif text,
  address_line text,
  postal_code text,
  city text,
  country text,
  phone text,
  email text,
  company_registry text,
  representative_name text,
  rejection_reason text,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid,
  doc_count bigint,
  updated_at timestamptz,
  leave_request_pending boolean,
  leave_request_reason text,
  leave_requested_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.batata_is_admin() then
    raise exception 'forbidden';
  end if;
  return query
  select
    t.user_id,
    p.full_name,
    p.handle,
    t.is_trader,
    t.verification_status,
    t.trade_name,
    t.legal_name,
    t.nif,
    t.address_line,
    t.postal_code,
    t.city,
    t.country,
    t.phone,
    t.email,
    t.company_registry,
    t.representative_name,
    t.rejection_reason,
    t.submitted_at,
    t.reviewed_at,
    t.reviewed_by,
    (select count(*)::bigint from public.seller_trade_documents d where d.user_id = t.user_id),
    t.updated_at,
    t.leave_request_pending,
    t.leave_request_reason,
    t.leave_requested_at
  from public.seller_trade_profiles t
  left join public.profiles p on p.id = t.user_id
  where t.is_trader = true
    and (
      p_status = 'all'
      or (p_status = 'leave' and t.leave_request_pending = true)
      or (p_status <> 'leave' and t.verification_status = p_status)
      or (p_status = 'pending' and t.leave_request_pending = true)
    )
  order by
    case when t.leave_request_pending then 0 else 1 end,
    case when t.verification_status = 'pending' then 0
         when t.verification_status = 'incomplete' then 1
         when t.verification_status = 'rejected' then 2
         else 3 end,
    coalesce(t.leave_requested_at, t.submitted_at, t.updated_at) desc nulls last
  limit greatest(1, least(coalesce(p_limit, 50), 200));
end;
$$;

grant execute on function public.seller_trade_admin_list_queue(text, int) to authenticated;
