-- Seller professional / trader status (DSA Art. 30 + consumer info).
-- Declaration ≠ verification. Public view never exposes NIF or documents.

create table if not exists public.seller_trade_profiles (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  is_trader boolean not null default false,
  verification_status text not null default 'none'
    check (verification_status in (
      'none',        -- particular / sem declaração
      'incomplete',  -- declarou profissional, dados incompletos
      'pending',     -- submeteu para análise
      'verified',    -- verificado pela Fleaber
      'rejected'     -- rejeitado
    )),
  trade_name text,
  legal_name text,
  nif text,
  address_line text,
  postal_code text,
  city text,
  country text not null default 'PT',
  phone text,
  email text,
  company_registry text,
  representative_name text,
  rejection_reason text,
  stripe_kyc_hint boolean not null default false,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.seller_trade_profiles is
  'Estatuto profissional do vendedor (declaração + verificação documental). NIF/docs privados.';

create table if not exists public.seller_trade_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  storage_path text not null,
  file_name text not null,
  mime_type text,
  byte_size integer,
  doc_type text not null default 'id_or_registry'
    check (doc_type in ('id_or_registry', 'address_proof', 'other')),
  created_at timestamptz not null default now()
);

create index if not exists seller_trade_documents_user_idx
  on public.seller_trade_documents (user_id);

alter table public.seller_trade_profiles enable row level security;
alter table public.seller_trade_documents enable row level security;

drop policy if exists seller_trade_profiles_select_own on public.seller_trade_profiles;
create policy seller_trade_profiles_select_own
  on public.seller_trade_profiles for select to authenticated
  using (user_id = auth.uid());

drop policy if exists seller_trade_profiles_upsert_own on public.seller_trade_profiles;
create policy seller_trade_profiles_upsert_own
  on public.seller_trade_profiles for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists seller_trade_profiles_update_own on public.seller_trade_profiles;
create policy seller_trade_profiles_update_own
  on public.seller_trade_profiles for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Sellers cannot self-set verified; trigger enforces.
create or replace function public.seller_trade_profiles_guard_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at := now();
  if tg_op = 'UPDATE'
     and new.verification_status is distinct from old.verification_status
     and new.verification_status = 'verified'
     and coalesce(auth.uid()::text, '') = coalesce(new.user_id::text, '')
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    -- Utilizador não pode auto-verificar
    raise exception 'verification_status verified requer revisão Fleaber';
  end if;
  if new.is_trader = false then
    new.verification_status := 'none';
    new.rejection_reason := null;
    new.submitted_at := null;
  elsif new.is_trader = true
        and new.verification_status in ('none') then
    new.verification_status := 'incomplete';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_seller_trade_profiles_guard on public.seller_trade_profiles;
create trigger trg_seller_trade_profiles_guard
  before insert or update on public.seller_trade_profiles
  for each row execute function public.seller_trade_profiles_guard_status();

drop policy if exists seller_trade_documents_select_own on public.seller_trade_documents;
create policy seller_trade_documents_select_own
  on public.seller_trade_documents for select to authenticated
  using (user_id = auth.uid());

drop policy if exists seller_trade_documents_insert_own on public.seller_trade_documents;
create policy seller_trade_documents_insert_own
  on public.seller_trade_documents for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists seller_trade_documents_delete_own on public.seller_trade_documents;
create policy seller_trade_documents_delete_own
  on public.seller_trade_documents for delete to authenticated
  using (user_id = auth.uid());

-- Private storage bucket for trade docs
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'seller-trade-docs',
  'seller-trade-docs',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists seller_trade_docs_select_own on storage.objects;
create policy seller_trade_docs_select_own
  on storage.objects for select to authenticated
  using (
    bucket_id = 'seller-trade-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists seller_trade_docs_insert_own on storage.objects;
create policy seller_trade_docs_insert_own
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'seller-trade-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists seller_trade_docs_delete_own on storage.objects;
create policy seller_trade_docs_delete_own
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'seller-trade-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Public directory: badge flags only (no NIF / docs / full address)
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
  coalesce(t.is_trader, false) as is_professional,
  (coalesce(t.verification_status, 'none') = 'verified') as professional_verified,
  case
    when coalesce(t.is_trader, false) then nullif(trim(t.trade_name), '')
    else null
  end as professional_trade_name,
  case
    when coalesce(t.is_trader, false) then nullif(trim(t.city), '')
    else null
  end as professional_city,
  case
    when coalesce(t.is_trader, false) then coalesce(nullif(trim(t.country), ''), 'PT')
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

comment on view public.profiles_directory_public is
  'Directory autenticada + flags profissionais públicas (sem NIF/docs).';

grant select on public.profiles_directory_public to authenticated;
revoke all on public.profiles_directory_public from anon;

grant select, insert, update on public.seller_trade_profiles to authenticated;
grant select, insert, delete on public.seller_trade_documents to authenticated;

-- RPC: dados profissionais públicos mínimos para checkout (sem NIF)
create or replace function public.seller_trade_public_info(p_seller_ids uuid[])
returns table (
  user_id uuid,
  is_professional boolean,
  professional_verified boolean,
  trade_name text,
  city text,
  country text,
  contact_email text,
  contact_phone text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    t.user_id,
    t.is_trader as is_professional,
    (t.verification_status = 'verified') as professional_verified,
    nullif(trim(t.trade_name), '') as trade_name,
    nullif(trim(t.city), '') as city,
    coalesce(nullif(trim(t.country), ''), 'PT') as country,
    case when t.is_trader then nullif(trim(t.email), '') else null end as contact_email,
    case when t.is_trader then nullif(trim(t.phone), '') else null end as contact_phone
  from public.seller_trade_profiles t
  where t.user_id = any (p_seller_ids)
    and t.is_trader = true;
$$;

grant execute on function public.seller_trade_public_info(uuid[]) to authenticated;
