-- 119.7 — Fecho vendedores profissionais
-- Badge só se verified; vendas suspensas enquanto trader ≠ verified;
-- Admin review RPC; reforço anti auto-aprovação; RLS admin docs.

-- 1) Função: vendas permitidas?
create or replace function public.seller_trade_can_sell(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_user_id is null then false
    when not exists (
      select 1 from public.seller_trade_profiles t
      where t.user_id = p_user_id and t.is_trader = true
    ) then true  -- particular / sem declaração
    when exists (
      select 1 from public.seller_trade_profiles t
      where t.user_id = p_user_id
        and t.is_trader = true
        and t.verification_status = 'verified'
    ) then true
    else false  -- trader incomplete/pending/rejected
  end;
$$;

comment on function public.seller_trade_can_sell(uuid) is
  'false se declarou profissional e ainda não está verified (suspende novas vendas).';

grant execute on function public.seller_trade_can_sell(uuid) to authenticated;

-- 2) Guard reforçado: utilizador não define verified/rejected/reviewed_*
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
    -- Cliente nunca escreve campos de revisão
    if tg_op = 'UPDATE' then
      new.reviewed_at := old.reviewed_at;
      new.reviewed_by := old.reviewed_by;
      if new.verification_status in ('verified', 'rejected')
         and new.verification_status is distinct from old.verification_status then
        raise exception 'Aprovação/rejeição só pela administração Fleaber';
      end if;
      if old.verification_status = 'verified'
         and new.verification_status is distinct from 'verified'
         and new.is_trader = true then
        -- Só admin pode remover verified mantendo trader
        raise exception 'Não podes alterar o estado verificado';
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

-- 3) Bloquear novos produtos / republicações enquanto vendas suspensas
create or replace function public.seller_trade_guard_product_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seller uuid;
begin
  v_seller := new.seller_id;
  if v_seller is null then
    return new;
  end if;
  -- Bloqueia anúncios que saem de rascunho / ficam no marketplace ou live
  if coalesce(new.is_draft, false) = false
     and (
       coalesce(new.list_on_marketplace, false) = true
       or coalesce(new.available_for_live, false) = true
     )
     and not public.seller_trade_can_sell(v_seller) then
    raise exception
      'Vendas temporariamente suspensas: conclui a verificação profissional '
      'em Definições → Dados profissionais (ou desactiva a declaração profissional).';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_seller_trade_guard_product on public.products;
create trigger trg_seller_trade_guard_product
  before insert or update on public.products
  for each row execute function public.seller_trade_guard_product_write();

-- 4) Bloquear novas encomendas (não afecta updates de encomendas existentes)
create or replace function public.seller_trade_guard_order_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.seller_id is not null
     and not public.seller_trade_can_sell(new.seller_id) then
    raise exception
      'Este vendedor tem a verificação profissional em curso. '
      'Novas compras estão temporariamente indisponíveis.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_seller_trade_guard_order on public.orders;
create trigger trg_seller_trade_guard_order
  before insert on public.orders
  for each row execute function public.seller_trade_guard_order_insert();

-- 5) View pública: is_professional = apenas verified (badge)
create or replace view public.profiles_directory_public
with (security_barrier = true)
as
select
  p.id,
  p.created_at,
  p.full_name,
  p.photo_url,
  p.location,
  p.is_live,
  p.next_live,
  p.last_live,
  p.total_lives,
  p.user_type,
  p.handle,
  coalesce(p.vacation_mode, false) as vacation_mode,
  coalesce(p.external_payments_enabled, false) as external_payments_enabled,
  (p.phone_verified_at is not null) as phone_verified,
  (coalesce(t.verification_status, 'none') = 'verified') as is_professional,
  (coalesce(t.verification_status, 'none') = 'verified') as professional_verified,
  case
    when coalesce(t.verification_status, 'none') = 'verified'
      then nullif(trim(t.trade_name), '')
    else null
  end as professional_trade_name,
  case
    when coalesce(t.verification_status, 'none') = 'verified'
      then nullif(trim(t.city), '')
    else null
  end as professional_city,
  case
    when coalesce(t.verification_status, 'none') = 'verified'
      then coalesce(nullif(trim(t.country), ''), 'PT')
    else null
  end as professional_country
from public.profiles p
left join public.seller_trade_profiles t on t.user_id = p.id
where coalesce(p.hub_published, false) = true
   or p.id = auth.uid()
   or exists (
     select 1
     from public.chats c
     where auth.uid() is not null
       and (
         (c.user_a = auth.uid() and c.user_b = p.id)
         or (c.user_b = auth.uid() and c.user_a = p.id)
       )
   );

grant select on public.profiles_directory_public to authenticated;

-- 6) RPC público checkout: só verified = profissional
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
    case when coalesce(t.verification_status, 'none') = 'verified'
      then nullif(trim(t.email), '') else null end as contact_email,
    case when coalesce(t.verification_status, 'none') = 'verified'
      then nullif(trim(t.phone), '') else null end as contact_phone,
    (
      coalesce(t.is_trader, false)
      and coalesce(t.verification_status, 'none') <> 'verified'
    ) as sales_suspended
  from unnest(p_seller_ids) as s(id)
  left join public.seller_trade_profiles t on t.user_id = s.id;
$$;

grant execute on function public.seller_trade_public_info(uuid[]) to authenticated;

-- 7) RLS admin: ler perfis/docs de todos
drop policy if exists seller_trade_profiles_select_admin on public.seller_trade_profiles;
create policy seller_trade_profiles_select_admin
  on public.seller_trade_profiles for select to authenticated
  using (user_id = auth.uid() or public.batata_is_admin());

drop policy if exists seller_trade_documents_select_admin on public.seller_trade_documents;
create policy seller_trade_documents_select_admin
  on public.seller_trade_documents for select to authenticated
  using (user_id = auth.uid() or public.batata_is_admin());

drop policy if exists seller_trade_docs_select_admin on storage.objects;
create policy seller_trade_docs_select_admin
  on storage.objects for select to authenticated
  using (
    bucket_id = 'seller-trade-docs'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.batata_is_admin()
    )
  );

-- 8) Admin: listar pedidos
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
  updated_at timestamptz
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
    (select count(*) from public.seller_trade_documents d where d.user_id = t.user_id),
    t.updated_at
  from public.seller_trade_profiles t
  left join public.profiles p on p.id = t.user_id
  where t.is_trader = true
    and (
      p_status is null
      or p_status = ''
      or p_status = 'all'
      or t.verification_status = p_status
    )
  order by
    case when t.verification_status = 'pending' then 0
         when t.verification_status = 'incomplete' then 1
         when t.verification_status = 'rejected' then 2
         else 3 end,
    coalesce(t.submitted_at, t.updated_at) desc nulls last
  limit greatest(1, least(coalesce(p_limit, 50), 200));
end;
$$;

grant execute on function public.seller_trade_admin_list_queue(text, int) to authenticated;

-- 9) Admin: aprovar / rejeitar
create or replace function public.seller_trade_admin_review(
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
begin
  if not public.batata_is_admin() then
    raise exception 'forbidden';
  end if;
  if p_user_id is null then
    raise exception 'user_id obrigatório';
  end if;
  if p_approve is not true
     and nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'Motivo obrigatório na rejeição';
  end if;

  update public.seller_trade_profiles t
  set
    is_trader = true,
    verification_status = case when p_approve then 'verified' else 'rejected' end,
    rejection_reason = case when p_approve then null else trim(p_reason) end,
    reviewed_at = now(),
    reviewed_by = auth.uid(),
    updated_at = now()
  where t.user_id = p_user_id
  returning * into v_row;

  if v_row.user_id is null then
    raise exception 'Perfil profissional não encontrado';
  end if;
  return v_row;
end;
$$;

grant execute on function public.seller_trade_admin_review(uuid, boolean, text) to authenticated;

-- 10) Admin: listar docs de um vendedor
create or replace function public.seller_trade_admin_list_docs(p_user_id uuid)
returns setof public.seller_trade_documents
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.batata_is_admin() then
    raise exception 'forbidden';
  end if;
  return query
  select d.*
  from public.seller_trade_documents d
  where d.user_id = p_user_id
  order by d.created_at desc;
end;
$$;

grant execute on function public.seller_trade_admin_list_docs(uuid) to authenticated;
