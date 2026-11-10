-- Fleaber BATATA: handles públicos Hub (/{handle}, /{handle}/live).
-- Iteração 12 / passo #20b — NÃO fazer deploy em staging/prod sem aprovação explícita.
--
-- Pré-requisitos (já aplicados em staging Fleaber):
--   - public.profiles (+ phone_verified_at recomendado)
--   - supabase/sql/admin_batata.sql (batata_is_admin) — para RLS admin em reserved_handles
--
-- Ordem: executar ESTE ficheiro inteiro no SQL Editor Supabase (staging).
-- Backfill sugestões: só após aprovação → SELECT batata_backfill_handle_suggestions();
--
-- ============================================================================
-- ROLLBACK (manual — perder redirects se apagar tabelas; links partilhados!)
-- ============================================================================
-- 1) drop trigger profiles_handle_guard_trg on public.profiles;
-- 2) drop function batata_profiles_handle_guard();
-- 3) revoke + drop RPCs batata_*handle* (lista abaixo)
-- 4) drop table profile_handle_claim_log, profile_handle_blocklist_words,
--    profile_handle_redirects, reserved_handles;
-- 5) alter table profiles drop column if exists handle_suggested,
--    drop column if exists handle_changes_window_start,
--    drop column if exists handle_change_count,
--    drop column if exists handle_last_changed_at,
--    drop column if exists handle_claimed_at,
--    drop column if exists hub_published,
--    drop column if exists handle;
-- 6) drop index profiles_handle_uidx, profiles_hub_published_handle_idx;
-- NOTA: manter profile_handle_redirects se já existirem links 301 em produção.

-- ---------------------------------------------------------------------------
-- 0) Extensões
-- ---------------------------------------------------------------------------
create extension if not exists unaccent with schema extensions;
create extension if not exists fuzzystrmatch with schema extensions;

-- ---------------------------------------------------------------------------
-- 1) Colunas profiles
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists handle text,
  add column if not exists hub_published boolean not null default false,
  add column if not exists handle_suggested text,
  add column if not exists handle_claimed_at timestamptz,
  add column if not exists handle_last_changed_at timestamptz,
  add column if not exists handle_change_count int not null default 0,
  add column if not exists handle_changes_window_start timestamptz;

alter table public.profiles
  drop constraint if exists profiles_handle_format_chk;
alter table public.profiles
  add constraint profiles_handle_format_chk
  check (
    handle is null
    or (
      char_length(handle) between 3 and 30
      and handle ~ '^[a-z0-9]([a-z0-9_-]{1,28}[a-z0-9])?$'
      and handle !~ '--'
      and handle !~ '__'
      and handle !~ '^[0-9]+$'
    )
  );

alter table public.profiles
  drop constraint if exists profiles_hub_requires_handle_chk;
alter table public.profiles
  add constraint profiles_hub_requires_handle_chk
  check (hub_published = false or handle is not null);

create unique index if not exists profiles_handle_uidx
  on public.profiles (handle)
  where handle is not null;

create index if not exists profiles_hub_published_handle_idx
  on public.profiles (hub_published, handle)
  where hub_published = true and handle is not null;

-- ---------------------------------------------------------------------------
-- 2) Tabelas auxiliares
-- ---------------------------------------------------------------------------
create table if not exists public.profile_handle_redirects (
  old_handle text primary key,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  new_handle text not null,
  replaced_at timestamptz not null default now(),
  redirect_until timestamptz,
  constraint profile_handle_redirects_old_format_chk
    check (old_handle ~ '^[a-z0-9]([a-z0-9_-]{1,28}[a-z0-9])?$')
);

create index if not exists profile_handle_redirects_profile_idx
  on public.profile_handle_redirects (profile_id, replaced_at desc);

create table if not exists public.reserved_handles (
  handle text primary key,
  reason text not null,
  severity text not null default 'hard'
    check (severity in ('hard', 'review')),
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.profile_handle_blocklist_words (
  word text primary key,
  locale text not null default 'any'
);

create table if not exists public.profile_handle_claim_log (
  id bigserial primary key,
  profile_id uuid references public.profiles (id) on delete set null,
  actor_id uuid references public.profiles (id) on delete set null,
  action text not null
    check (action in ('claim', 'change', 'suggest', 'publish', 'unpublish')),
  input_raw text,
  handle_normalized text,
  result text not null check (result in ('ok', 'rejected', 'error')),
  reject_reason text,
  ip_hash text,
  created_at timestamptz not null default now()
);

create index if not exists profile_handle_claim_log_profile_created_idx
  on public.profile_handle_claim_log (profile_id, created_at desc);

create index if not exists profile_handle_claim_log_actor_hour_idx
  on public.profile_handle_claim_log (actor_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 3) Trigger — impedir UPDATE directo handle/hub_published
-- ---------------------------------------------------------------------------
create or replace function public.batata_profiles_handle_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_setting('batata.handle_rpc', true) is distinct from '1' then
    if new.handle is distinct from old.handle
       or new.hub_published is distinct from old.hub_published then
      raise exception 'handle_immutable_use_rpc'
        using hint = 'Use batata_claim_handle, batata_change_handle ou batata_publish_hub.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_handle_guard_trg on public.profiles;
create trigger profiles_handle_guard_trg
  before update of handle, hub_published on public.profiles
  for each row
  execute function public.batata_profiles_handle_guard();

-- ---------------------------------------------------------------------------
-- 4) Helpers internos
-- ---------------------------------------------------------------------------
create or replace function public.batata_handle_format_ok(p_handle text)
returns boolean
language sql
immutable
as $$
  select p_handle is not null
    and char_length(p_handle) between 3 and 30
    and p_handle ~ '^[a-z0-9]([a-z0-9_-]{1,28}[a-z0-9])?$'
    and p_handle !~ '--'
    and p_handle !~ '__'
    and p_handle !~ '^[0-9]+$';
$$;

create or replace function public.batata_normalize_handle(p_input text)
returns text
language plpgsql
immutable
set search_path = public, extensions
as $$
declare
  v text;
begin
  if p_input is null or btrim(p_input) = '' then
    return '';
  end if;

  v := lower(btrim(p_input));
  v := extensions.unaccent(v);
  v := regexp_replace(v, '[\s]+', '-', 'g');
  v := regexp_replace(v, '[^a-z0-9_-]', '', 'g');
  v := regexp_replace(v, '-{2,}', '-', 'g');
  v := regexp_replace(v, '_{2,}', '_', 'g');
  v := regexp_replace(v, '^[-_]+|[-_]+$', '', 'g');

  if char_length(v) > 30 then
    v := left(v, 30);
    v := regexp_replace(v, '[-_]+$', '', 'g');
  end if;

  return coalesce(v, '');
end;
$$;

create or replace function public.batata_handle_log(
  p_action text,
  p_input_raw text,
  p_handle_normalized text,
  p_result text,
  p_reject_reason text default null,
  p_profile_id uuid default null,
  p_actor_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profile_handle_claim_log (
    profile_id,
    actor_id,
    action,
    input_raw,
    handle_normalized,
    result,
    reject_reason
  ) values (
    coalesce(p_profile_id, auth.uid()),
    coalesce(p_actor_id, auth.uid()),
    p_action,
    p_input_raw,
    p_handle_normalized,
    p_result,
    p_reject_reason
  );
end;
$$;

create or replace function public.batata_handle_rate_limit_ok(p_action text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_count int;
begin
  if v_uid is null then
    return false;
  end if;

  select count(*)::int into v_count
  from public.profile_handle_claim_log l
  where l.actor_id = v_uid
    and l.action in ('claim', 'change')
    and l.created_at > now() - interval '1 hour';

  return coalesce(v_count, 0) < 10;
end;
$$;

create or replace function public.batata_check_handle_available(
  p_handle text,
  p_profile_id uuid default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_handle text := btrim(coalesce(p_handle, ''));
begin
  if v_handle = '' or not public.batata_handle_format_ok(v_handle) then
    return false;
  end if;

  if exists (
    select 1
    from public.reserved_handles rh
    where rh.handle = v_handle
      and rh.severity = 'hard'
  ) then
    return false;
  end if;

  if exists (
    select 1
    from public.profile_handle_redirects r
    where r.old_handle = v_handle
  ) then
    return false;
  end if;

  if exists (
    select 1
    from public.profiles p
    where p.handle = v_handle
      and (p_profile_id is null or p.id <> p_profile_id)
  ) then
    return false;
  end if;

  return true;
end;
$$;

create or replace function public.batata_validate_handle(
  p_input text,
  p_profile_id uuid default null,
  p_check_availability boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_raw text := coalesce(p_input, '');
  v_handle text := public.batata_normalize_handle(p_input);
  v_reasons text[] := array[]::text[];
  v_reserved record;
  v_word text;
begin
  if v_handle = '' or char_length(v_handle) < 3 then
    v_reasons := array_append(v_reasons, 'too_short');
  end if;

  if char_length(v_handle) > 30 then
    v_reasons := array_append(v_reasons, 'too_long');
  end if;

  if v_handle <> '' and not public.batata_handle_format_ok(v_handle) then
    v_reasons := array_append(v_reasons, 'invalid_format');
  end if;

  if v_handle ~ '^[0-9]+$' then
    v_reasons := array_append(v_reasons, 'numeric_only');
  end if;

  if exists (
    select 1 from public.reserved_handles rh
    where rh.handle = v_handle
  ) then
    v_reasons := array_append(v_reasons, 'reserved');
  end if;

  if v_handle ~ '^(fleaber|admin|suporte|support|oficial)(-|$)'
     or v_handle ~ '(-oficial|-suporte|-support)$' then
    v_reasons := array_append(v_reasons, 'impersonation');
  end if;

  for v_reserved in
    select rh.handle, rh.reason
    from public.reserved_handles rh
    where rh.reason in ('brand', 'staff')
  loop
    if extensions.levenshtein(v_handle, v_reserved.handle) <= 2 then
      v_reasons := array_append(v_reasons, 'levenshtein');
      exit;
    end if;
  end loop;

  for v_word in
    select bw.word
    from public.profile_handle_blocklist_words bw
    where v_handle like '%' || bw.word || '%'
  loop
    v_reasons := array_append(v_reasons, 'offensive');
    exit;
  end loop;

  if p_check_availability
     and not public.batata_check_handle_available(v_handle, p_profile_id) then
    v_reasons := array_append(v_reasons, 'unavailable');
  end if;

  return jsonb_build_object(
    'ok', coalesce(array_length(v_reasons, 1), 0) = 0,
    'handle', v_handle,
    'input', v_raw,
    'reasons', to_jsonb(coalesce(v_reasons, array[]::text[]))
  );
end;
$$;

create or replace function public.batata_suggest_handles(
  p_seed text,
  p_profile_id uuid default null,
  p_limit int default 5
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_base text := public.batata_normalize_handle(p_seed);
  v_try text;
  v_out text[] := array[]::text[];
  i int;
  v_suffix text;
begin
  if v_base = '' or char_length(v_base) < 3 then
    v_base := 'vendedor';
  end if;

  v_try := left(v_base, 30);
  if public.batata_check_handle_available(v_try, p_profile_id) then
    v_out := array_append(v_out, v_try);
  end if;

  for i in 2..greatest(p_limit + 3, 8) loop
    exit when coalesce(array_length(v_out, 1), 0) >= p_limit;
    v_suffix := '-' || i::text;
    v_try := left(v_base, 30 - char_length(v_suffix)) || v_suffix;
    if public.batata_check_handle_available(v_try, p_profile_id) then
      v_out := array_append(v_out, v_try);
    end if;
  end loop;

  return jsonb_build_object('suggestions', to_jsonb(v_out));
end;
$$;

create or replace function public.batata_profile_can_claim_handle(p_profile_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_phone_verified timestamptz;
begin
  if p_profile_id is null then
    return false;
  end if;

  select p.phone_verified_at into v_phone_verified
  from public.profiles p
  where p.id = p_profile_id;

  return v_phone_verified is not null;
end;
$$;

create or replace function public.batata_profile_can_publish_hub(p_profile_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_phone_verified timestamptz;
  v_email_confirmed timestamptz;
  v_has_catalog boolean := false;
begin
  if p_profile_id is null then
    return false;
  end if;

  select p.phone_verified_at into v_phone_verified
  from public.profiles p
  where p.id = p_profile_id;

  if v_phone_verified is null then
    return false;
  end if;

  select u.email_confirmed_at into v_email_confirmed
  from auth.users u
  where u.id = p_profile_id;

  if v_email_confirmed is null then
    return false;
  end if;

  select exists (
    select 1 from public.products pr where pr.seller_id = p_profile_id
    union all
    select 1 from public.lives l
    where coalesce(l.seller_id, l.vendedor_id) = p_profile_id
  ) into v_has_catalog;

  return v_has_catalog;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5) RPCs mutáveis (SECURITY DEFINER)
-- ---------------------------------------------------------------------------
create or replace function public.batata_claim_handle(p_handle text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_current text;
  v_val jsonb;
  v_handle text;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  if not public.batata_handle_rate_limit_ok('claim') then
    perform public.batata_handle_log(
      'claim', p_handle, null, 'rejected', 'rate_limit', v_uid, v_uid
    );
    raise exception 'handle_rate_limit';
  end if;

  if not public.batata_profile_can_claim_handle(v_uid) then
    perform public.batata_handle_log(
      'claim', p_handle, null, 'rejected', 'phone_not_verified', v_uid, v_uid
    );
    raise exception 'phone_not_verified';
  end if;

  select p.handle into v_current
  from public.profiles p
  where p.id = v_uid;

  if v_current is not null then
    perform public.batata_handle_log(
      'claim', p_handle, v_current, 'rejected', 'handle_already_set', v_uid, v_uid
    );
    raise exception 'handle_already_set';
  end if;

  v_val := public.batata_validate_handle(p_handle, v_uid, true);
  v_handle := v_val->>'handle';

  if coalesce((v_val->>'ok')::boolean, false) is not true then
    perform public.batata_handle_log(
      'claim', p_handle, v_handle, 'rejected', 'handle_invalid', v_uid, v_uid
    );
    return jsonb_build_object(
      'ok', false,
      'error', 'handle_invalid',
      'validation', v_val
    );
  end if;

  perform set_config('batata.handle_rpc', '1', true);

  update public.profiles
  set
    handle = v_handle,
    handle_claimed_at = now(),
    handle_suggested = null
  where id = v_uid;

  perform public.batata_handle_log(
    'claim', p_handle, v_handle, 'ok', null, v_uid, v_uid
  );

  return jsonb_build_object(
    'ok', true,
    'profile_id', v_uid,
    'handle', v_handle,
    'hub_published', (
      select p.hub_published from public.profiles p where p.id = v_uid
    )
  );
end;
$$;

create or replace function public.batata_change_handle(p_new_handle text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_old text;
  v_val jsonb;
  v_new text;
  v_window_start timestamptz;
  v_change_count int;
  v_last_changed timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  if not public.batata_handle_rate_limit_ok('change') then
    perform public.batata_handle_log(
      'change', p_new_handle, null, 'rejected', 'rate_limit', v_uid, v_uid
    );
    raise exception 'handle_rate_limit';
  end if;

  select p.handle, p.handle_changes_window_start, p.handle_change_count, p.handle_last_changed_at
  into v_old, v_window_start, v_change_count, v_last_changed
  from public.profiles p
  where p.id = v_uid;

  if v_old is null then
    raise exception 'handle_not_set';
  end if;

  if v_last_changed is not null
     and v_last_changed > now() - interval '7 days' then
    perform public.batata_handle_log(
      'change', p_new_handle, v_old, 'rejected', 'cooldown_7d', v_uid, v_uid
    );
    raise exception 'handle_change_cooldown';
  end if;

  if v_window_start is null or v_window_start < now() - interval '90 days' then
    v_window_start := now();
    v_change_count := 0;
  end if;

  if v_change_count >= 2 then
    perform public.batata_handle_log(
      'change', p_new_handle, v_old, 'rejected', 'max_changes_90d', v_uid, v_uid
    );
    raise exception 'handle_max_changes_90d';
  end if;

  v_val := public.batata_validate_handle(p_new_handle, v_uid, true);
  v_new := v_val->>'handle';

  if coalesce((v_val->>'ok')::boolean, false) is not true then
    perform public.batata_handle_log(
      'change', p_new_handle, v_new, 'rejected', 'handle_invalid', v_uid, v_uid
    );
    return jsonb_build_object(
      'ok', false,
      'error', 'handle_invalid',
      'validation', v_val
    );
  end if;

  if v_new = v_old then
    return jsonb_build_object('ok', true, 'handle', v_old, 'unchanged', true);
  end if;

  perform set_config('batata.handle_rpc', '1', true);

  insert into public.profile_handle_redirects (old_handle, profile_id, new_handle)
  values (v_old, v_uid, v_new)
  on conflict (old_handle) do nothing;

  update public.profiles
  set
    handle = v_new,
    handle_last_changed_at = now(),
    handle_change_count = v_change_count + 1,
    handle_changes_window_start = v_window_start
  where id = v_uid;

  perform public.batata_handle_log(
    'change', p_new_handle, v_new, 'ok', null, v_uid, v_uid
  );

  return jsonb_build_object(
    'ok', true,
    'profile_id', v_uid,
    'handle', v_new,
    'redirect_from', v_old
  );
end;
$$;

create or replace function public.batata_publish_hub(p_publish boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_handle text;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select p.handle into v_handle
  from public.profiles p
  where p.id = v_uid;

  if coalesce(p_publish, true) then
    if v_handle is null then
      raise exception 'handle_required';
    end if;

    if not public.batata_profile_can_publish_hub(v_uid) then
      perform public.batata_handle_log(
        'publish', null, v_handle, 'rejected', 'seller_not_ready', v_uid, v_uid
      );
      raise exception 'seller_not_ready';
    end if;

    perform set_config('batata.handle_rpc', '1', true);
    update public.profiles set hub_published = true where id = v_uid;

    perform public.batata_handle_log(
      'publish', null, v_handle, 'ok', null, v_uid, v_uid
    );

    return jsonb_build_object(
      'ok', true,
      'hub_published', true,
      'handle', v_handle,
      'profile_id', v_uid
    );
  end if;

  perform set_config('batata.handle_rpc', '1', true);
  update public.profiles set hub_published = false where id = v_uid;

  perform public.batata_handle_log(
    'unpublish', null, v_handle, 'ok', null, v_uid, v_uid
  );

  return jsonb_build_object(
    'ok', true,
    'hub_published', false,
    'handle', v_handle,
    'profile_id', v_uid
  );
end;
$$;

create or replace function public.batata_resolve_handle(p_handle text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_in text := public.batata_normalize_handle(p_handle);
  v_profile_id uuid;
  v_handle text;
  v_published boolean;
  v_redirect text;
begin
  if v_in = '' then
    return jsonb_build_object(
      'found', false,
      'error', 'not_found',
      'http_status', 404
    );
  end if;

  select p.id, p.handle, p.hub_published
  into v_profile_id, v_handle, v_published
  from public.profiles p
  where p.handle = v_in
  limit 1;

  if v_profile_id is not null and v_published is true then
    return jsonb_build_object(
      'found', true,
      'profile_id', v_profile_id,
      'handle', v_handle,
      'hub_published', true,
      'redirect_to', null,
      'http_status', 200
    );
  end if;

  select r.new_handle into v_redirect
  from public.profile_handle_redirects r
  where r.old_handle = v_in
    and (r.redirect_until is null or r.redirect_until > now())
  limit 1;

  if v_redirect is not null then
    return jsonb_build_object(
      'found', true,
      'profile_id', (
        select p.id from public.profiles p where p.handle = v_redirect limit 1
      ),
      'handle', v_redirect,
      'redirect_to', v_redirect,
      'hub_published', (
        select p.hub_published from public.profiles p where p.handle = v_redirect limit 1
      ),
      'http_status', 301
    );
  end if;

  return jsonb_build_object(
    'found', false,
    'error', 'not_found',
    'http_status', 404
  );
end;
$$;

-- Backfill sugestões (NÃO corre automaticamente — service_role / SQL Editor admin)
create or replace function public.batata_backfill_handle_suggestions(
  p_dry_run boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row record;
  v_base text;
  v_try text;
  v_suffix int;
  v_updated int := 0;
  v_skipped int := 0;
begin
  for v_row in
    select p.id, p.full_name, p.handle, p.handle_suggested
    from public.profiles p
    where p.handle is null
      and (
        exists (select 1 from public.products pr where pr.seller_id = p.id)
        or exists (
          select 1 from public.lives l
          where coalesce(l.seller_id, l.vendedor_id) = p.id
        )
        or lower(coalesce(p.user_type, '')) in ('vendedor', 'seller')
      )
  loop
    if v_row.handle_suggested is not null then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_base := public.batata_normalize_handle(coalesce(v_row.full_name, ''));
    if v_base = '' or char_length(v_base) < 3 then
      v_base := 'vendedor-' || left(replace(v_row.id::text, '-', ''), 8);
    end if;

    v_try := left(v_base, 30);
    v_suffix := 2;
    while not public.batata_check_handle_available(v_try, v_row.id) loop
      v_try := left(v_base, greatest(3, 30 - char_length('-' || v_suffix::text)))
        || '-' || v_suffix::text;
      v_suffix := v_suffix + 1;
      if v_suffix > 50 then
        v_try := null;
        exit;
      end if;
    end loop;

    if v_try is null then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    if not p_dry_run then
      update public.profiles
      set handle_suggested = v_try
      where id = v_row.id;
    end if;

    v_updated := v_updated + 1;
  end loop;

  return jsonb_build_object(
    'dry_run', p_dry_run,
    'updated', v_updated,
    'skipped', v_skipped
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 6) Seeds — reserved_handles + blocklist mínima
-- ---------------------------------------------------------------------------
insert into public.reserved_handles (handle, reason, severity, notes)
values
  ('fleaber', 'brand', 'hard', 'Marca Fleaber'),
  ('fleaberpt', 'brand', 'hard', null),
  ('oficial', 'brand', 'hard', null),
  ('suporte', 'staff', 'hard', null),
  ('support', 'staff', 'hard', null),
  ('admin', 'staff', 'hard', null),
  ('api', 'route', 'hard', null),
  ('www', 'route', 'hard', null),
  ('app', 'route', 'hard', null),
  ('hub', 'route', 'hard', null),
  ('live', 'route', 'hard', null),
  ('shop', 'route', 'hard', null),
  ('reviews', 'route', 'hard', null),
  ('marketplace', 'route', 'hard', null),
  ('login', 'route', 'hard', null),
  ('signup', 'route', 'hard', null),
  ('auth', 'route', 'hard', null),
  ('stripe', 'route', 'hard', null),
  ('mux', 'route', 'hard', null),
  ('arena', 'route', 'hard', null),
  ('minhas-reservas', 'route', 'hard', null),
  ('mensagens', 'route', 'hard', null),
  ('conta', 'route', 'hard', null),
  ('perfil', 'route', 'hard', null),
  ('home', 'route', 'hard', null),
  ('help', 'route', 'hard', null),
  ('ajuda', 'route', 'hard', null),
  ('mod', 'staff', 'hard', null),
  ('staff', 'staff', 'hard', null),
  ('test', 'route', 'hard', null),
  ('staging', 'route', 'hard', null),
  ('dev', 'route', 'hard', null),
  ('root', 'route', 'hard', null),
  ('system', 'route', 'hard', null)
on conflict (handle) do nothing;

-- Blocklist mínima (expandir via admin; palavras curtas perigosas omitidas aqui)
insert into public.profile_handle_blocklist_words (word, locale)
values
  ('nazi', 'any'),
  ('hitler', 'any'),
  ('porno', 'any'),
  ('puta', 'pt'),
  ('caralho', 'pt')
on conflict (word) do nothing;

-- ---------------------------------------------------------------------------
-- 7) RLS
-- ---------------------------------------------------------------------------
alter table public.profile_handle_redirects enable row level security;
alter table public.reserved_handles enable row level security;
alter table public.profile_handle_blocklist_words enable row level security;
alter table public.profile_handle_claim_log enable row level security;

drop policy if exists profile_handle_redirects_select_own on public.profile_handle_redirects;
create policy profile_handle_redirects_select_own
  on public.profile_handle_redirects
  for select
  to authenticated
  using (profile_id = auth.uid());

drop policy if exists profile_handle_redirects_admin_all on public.profile_handle_redirects;
create policy profile_handle_redirects_admin_all
  on public.profile_handle_redirects
  for all
  to authenticated
  using (public.batata_is_admin())
  with check (public.batata_is_admin());

drop policy if exists reserved_handles_admin_all on public.reserved_handles;
create policy reserved_handles_admin_all
  on public.reserved_handles
  for all
  to authenticated
  using (public.batata_is_admin())
  with check (public.batata_is_admin());

drop policy if exists profile_handle_blocklist_admin_all on public.profile_handle_blocklist_words;
create policy profile_handle_blocklist_admin_all
  on public.profile_handle_blocklist_words
  for all
  to authenticated
  using (public.batata_is_admin())
  with check (public.batata_is_admin());

drop policy if exists profile_handle_claim_log_select_own on public.profile_handle_claim_log;
create policy profile_handle_claim_log_select_own
  on public.profile_handle_claim_log
  for select
  to authenticated
  using (actor_id = auth.uid() or profile_id = auth.uid());

drop policy if exists profile_handle_claim_log_admin_select on public.profile_handle_claim_log;
create policy profile_handle_claim_log_admin_select
  on public.profile_handle_claim_log
  for select
  to authenticated
  using (public.batata_is_admin());

-- Escrita claim_log só via SECURITY DEFINER (sem INSERT policy para authenticated)

-- ---------------------------------------------------------------------------
-- 8) Grants
-- ---------------------------------------------------------------------------
revoke all on function public.batata_normalize_handle(text) from public;
grant execute on function public.batata_normalize_handle(text) to anon, authenticated, service_role;

revoke all on function public.batata_validate_handle(text, uuid, boolean) from public;
grant execute on function public.batata_validate_handle(text, uuid, boolean) to anon, authenticated, service_role;

revoke all on function public.batata_check_handle_available(text, uuid) from public;
grant execute on function public.batata_check_handle_available(text, uuid) to anon, authenticated, service_role;

revoke all on function public.batata_suggest_handles(text, uuid, int) from public;
grant execute on function public.batata_suggest_handles(text, uuid, int) to authenticated, service_role;

revoke all on function public.batata_resolve_handle(text) from public;
grant execute on function public.batata_resolve_handle(text) to anon, authenticated, service_role;

revoke all on function public.batata_claim_handle(text) from public;
grant execute on function public.batata_claim_handle(text) to authenticated, service_role;

revoke all on function public.batata_change_handle(text) from public;
grant execute on function public.batata_change_handle(text) to authenticated, service_role;

revoke all on function public.batata_publish_hub(boolean) from public;
grant execute on function public.batata_publish_hub(boolean) to authenticated, service_role;

revoke all on function public.batata_backfill_handle_suggestions(boolean) from public, anon, authenticated;
grant execute on function public.batata_backfill_handle_suggestions(boolean) to service_role;

revoke all on function public.batata_handle_format_ok(text) from public;
grant execute on function public.batata_handle_format_ok(text) to service_role;

-- ---------------------------------------------------------------------------
-- 9) Self-tests mínimos (correm no deploy — falham o script se regressão)
-- ---------------------------------------------------------------------------
do $$
declare
  v_norm text;
  v_val jsonb;
  v_ok boolean;
  v_policies int;
begin
  -- U01 normalize acentos
  v_norm := public.batata_normalize_handle('São João  Shop');
  if v_norm is distinct from 'sao-joao-shop' then
    raise exception 'SELFTEST U01 FAIL: normalize=% expected sao-joao-shop', v_norm;
  end if;

  -- U02 reserved fleaber
  v_val := public.batata_validate_handle('fleaber', null, false);
  if coalesce((v_val->>'ok')::boolean, true) then
    raise exception 'SELFTEST U02 FAIL: fleaber should be invalid';
  end if;

  -- U02b too short
  v_val := public.batata_validate_handle('ab', null, false);
  if coalesce((v_val->>'ok')::boolean, true) then
    raise exception 'SELFTEST U02b FAIL: ab should be invalid';
  end if;

  -- U03 levenshtein fleber
  v_val := public.batata_validate_handle('fleber', null, false);
  if coalesce((v_val->>'ok')::boolean, true)
     and not (v_val->'reasons')::jsonb ? 'levenshtein' then
    raise exception 'SELFTEST U03 FAIL: fleber should hit levenshtein';
  end if;

  -- U04 unavailable via reserved route
  v_ok := public.batata_check_handle_available('login', null);
  if v_ok then
    raise exception 'SELFTEST U04 FAIL: login should be unavailable';
  end if;

  -- R05 resolve reserved → 404
  v_val := public.batata_resolve_handle('fleaber');
  if coalesce((v_val->>'http_status')::int, 0) <> 404 then
    raise exception 'SELFTEST R05 FAIL: resolve fleaber expected 404 got %', v_val;
  end if;

  -- L01 policies exist
  select count(*) into v_policies
  from pg_policies
  where schemaname = 'public'
    and tablename in (
      'profile_handle_redirects',
      'reserved_handles',
      'profile_handle_claim_log'
    );

  if v_policies < 4 then
    raise exception 'SELFTEST L01 FAIL: expected >=4 RLS policies, got %', v_policies;
  end if;

  raise notice 'profile_handles_batata.sql: ALL SELF-TESTS PASS (U01-U04, R05, L01)';
end;
$$;

notify pgrst, 'reload schema';
