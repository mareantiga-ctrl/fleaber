-- ZIP 187 — Signup scale guard (Amen 500/day, anti-abuso, challenge adaptativo)
-- BATATA: não toca Stripe/DPD/Moloni; confirmação por email mantém-se no Auth.

create table if not exists public.signup_guard_config (
  key text primary key,
  value_int integer not null,
  note text,
  updated_at timestamptz not null default now()
);

comment on table public.signup_guard_config is
  'Limites de registo derivados do teto Amen documentado (500/dia). Sem inventar limites horários Amen.';

insert into public.signup_guard_config (key, value_int, note) values
  ('amen_daily_smtp', 500, 'Único limite Amen.pt publicado (envios/dia por caixa)'),
  ('soft_ip_per_hour', 30, 'Acima disto exige desafio adaptativo; NÃO bloqueia IP partilhado'),
  ('device_per_day', 8, 'Máx. contas por device_id / dia Lisboa'),
  ('email_per_hour', 5, 'Máx. tentativas de signup por email / hora'),
  ('min_form_ms', 1200, 'Formulário preenchido demasiado rápido = bot')
on conflict (key) do update
  set value_int = excluded.value_int,
      note = excluded.note,
      updated_at = now();

revoke all on table public.signup_guard_config from anon, authenticated;
grant select on table public.signup_guard_config to supabase_auth_admin;

create table if not exists public.signup_attempt_log (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  email_norm text,
  email_hash text,
  ip_text text,
  device_id text,
  outcome text not null,
  reason text,
  required_challenge boolean not null default false
);

create index if not exists signup_attempt_log_created_idx
  on public.signup_attempt_log (created_at desc);
create index if not exists signup_attempt_log_ip_created_idx
  on public.signup_attempt_log (ip_text, created_at desc);
create index if not exists signup_attempt_log_device_created_idx
  on public.signup_attempt_log (device_id, created_at desc);
create index if not exists signup_attempt_log_email_created_idx
  on public.signup_attempt_log (email_norm, created_at desc);

revoke all on table public.signup_attempt_log from anon, authenticated;
grant select, insert on table public.signup_attempt_log to supabase_auth_admin;
grant usage, select on sequence public.signup_attempt_log_id_seq to supabase_auth_admin;

-- Desafio adaptativo simples (sem serviço pago)
create table if not exists public.signup_challenges (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  ip_hint text,
  question text not null,
  answer_hash text not null,
  consumed_at timestamptz,
  token_hash text
);

revoke all on table public.signup_challenges from public;
grant select, insert, update on table public.signup_challenges to anon, authenticated, service_role;

create or replace function public._signup_cfg(p_key text, p_default int)
returns int
language sql
stable
as $$
  select coalesce(
    (select value_int from public.signup_guard_config where key = p_key),
    p_default
  );
$$;

create extension if not exists pgcrypto with schema extensions;

create or replace function public._signup_sha256(p text)
returns text
language sql
immutable
as $$
  select encode(
    extensions.digest(convert_to(coalesce(p, ''), 'utf8'), 'sha256'),
    'hex'
  );
$$;

-- Domínios descartáveis óbvios (lista curta, gratuita, local)
create table if not exists public.signup_denied_email_domains (
  domain text primary key,
  reason text not null default 'disposable'
);

insert into public.signup_denied_email_domains (domain, reason) values
  ('mailinator.com', 'disposable'),
  ('guerrillamail.com', 'disposable'),
  ('10minutemail.com', 'disposable'),
  ('tempmail.com', 'disposable'),
  ('yopmail.com', 'disposable'),
  ('trashmail.com', 'disposable'),
  ('sharklasers.com', 'disposable')
on conflict (domain) do nothing;

revoke all on table public.signup_denied_email_domains from anon, authenticated;
grant select on table public.signup_denied_email_domains to supabase_auth_admin, anon, authenticated;

-- Emitir desafio (anon) quando o cliente recebe pedido de challenge
create or replace function public.signup_issue_challenge(p_ip_hint text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  a int;
  b int;
  ans int;
  q text;
  rid uuid;
  exp timestamptz := now() + interval '10 minutes';
begin
  a := 2 + floor(random() * 8)::int;
  b := 2 + floor(random() * 8)::int;
  ans := a + b;
  q := format('Quanto é %s + %s?', a, b);
  insert into public.signup_challenges (expires_at, ip_hint, question, answer_hash)
  values (exp, nullif(trim(coalesce(p_ip_hint, '')), ''), q, public._signup_sha256(ans::text))
  returning id into rid;
  return jsonb_build_object(
    'challenge_id', rid,
    'question', q,
    'expires_at', exp
  );
end;
$$;

revoke all on function public.signup_issue_challenge(text) from public;
grant execute on function public.signup_issue_challenge(text) to anon, authenticated;

create or replace function public.signup_verify_challenge(
  p_challenge_id uuid,
  p_answer text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  row public.signup_challenges%rowtype;
  token text;
begin
  select * into row from public.signup_challenges where id = p_challenge_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'challenge_not_found');
  end if;
  if row.consumed_at is not null then
    return jsonb_build_object('ok', false, 'error', 'challenge_used');
  end if;
  if row.expires_at < now() then
    return jsonb_build_object('ok', false, 'error', 'challenge_expired');
  end if;
  if row.answer_hash <> public._signup_sha256(trim(coalesce(p_answer, ''))) then
    return jsonb_build_object('ok', false, 'error', 'challenge_wrong');
  end if;
  token := encode(gen_random_bytes(24), 'hex');
  update public.signup_challenges
    set consumed_at = now(),
        token_hash = public._signup_sha256(token)
    where id = p_challenge_id;
  return jsonb_build_object('ok', true, 'challenge_token', token);
end;
$$;

revoke all on function public.signup_verify_challenge(uuid, text) from public;
grant execute on function public.signup_verify_challenge(uuid, text) to anon, authenticated;

-- Simulação / pré-check sem criar user nem enviar email
create or replace function public.signup_guard_simulate(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(trim(coalesce(p->>'email', '')));
  v_ip text := nullif(trim(coalesce(p->>'ip', '')), '');
  v_device_id text := nullif(trim(coalesce(p->>'device_id', '')), '');
  v_form_ms int := coalesce((p->>'form_ms')::int, 999999);
  v_honeypot text := coalesce(p->>'hp', '');
  v_challenge_token text := nullif(trim(coalesce(p->>'challenge_token', '')), '');
  v_dry_run boolean := coalesce((p->>'dry_run')::boolean, true);
  v_email_domain text;
  v_amen_daily int := public._signup_cfg('amen_daily_smtp', 500);
  v_soft_ip int := public._signup_cfg('soft_ip_per_hour', 30);
  v_device_day int := public._signup_cfg('device_per_day', 8);
  v_email_hour int := public._signup_cfg('email_per_hour', 5);
  v_min_form int := public._signup_cfg('min_form_ms', 1200);
  v_day_start timestamptz := date_trunc('day', timezone('Europe/Lisbon', now())) at time zone 'Europe/Lisbon';
  v_hour_ago timestamptz := now() - interval '1 hour';
  v_users_today int;
  v_ip_hour int := 0;
  v_device_today int := 0;
  v_email_hour_cnt int := 0;
  v_need_challenge boolean := false;
  v_tok_ok boolean := false;
begin
  if v_email = '' or position('@' in v_email) = 0 then
    return jsonb_build_object('ok', false, 'reason', 'invalid_email', 'need_challenge', false);
  end if;
  v_email_domain := split_part(v_email, '@', 2);

  if v_honeypot <> '' then
    return jsonb_build_object('ok', false, 'reason', 'bot_honeypot', 'need_challenge', false);
  end if;

  if v_form_ms < v_min_form then
    return jsonb_build_object('ok', false, 'reason', 'bot_too_fast', 'need_challenge', false);
  end if;

  if exists (
    select 1 from public.signup_denied_email_domains d
    where lower(d.domain) = lower(v_email_domain)
  ) then
    return jsonb_build_object('ok', false, 'reason', 'denied_domain', 'need_challenge', false);
  end if;

  select count(*)::int into v_users_today
  from auth.users u
  where u.created_at >= v_day_start
    and coalesce(u.email, '') <> '';

  if v_users_today >= v_amen_daily then
    return jsonb_build_object(
      'ok', false,
      'reason', 'daily_smtp_budget',
      'need_challenge', false,
      'users_today', v_users_today,
      'amen_daily', v_amen_daily
    );
  end if;

  if v_email <> '' then
    select count(*)::int into v_email_hour_cnt
    from public.signup_attempt_log l
    where l.email_norm = v_email
      and l.created_at >= v_hour_ago
      and l.outcome = 'allow';
    if v_email_hour_cnt >= v_email_hour then
      return jsonb_build_object('ok', false, 'reason', 'email_rate', 'need_challenge', false);
    end if;
  end if;

  if v_device_id is not null then
    select count(*)::int into v_device_today
    from public.signup_attempt_log l
    where l.device_id = v_device_id
      and l.created_at >= v_day_start
      and l.outcome = 'allow';
    if v_device_today >= v_device_day then
      return jsonb_build_object('ok', false, 'reason', 'device_rate', 'need_challenge', false);
    end if;
  end if;

  if v_ip is not null then
    select count(*)::int into v_ip_hour
    from public.signup_attempt_log l
    where l.ip_text = v_ip
      and l.created_at >= v_hour_ago
      and l.outcome = 'allow';
    if v_ip_hour >= v_soft_ip then
      v_need_challenge := true;
      if v_challenge_token is null then
        return jsonb_build_object(
          'ok', false,
          'reason', 'challenge_required',
          'need_challenge', true,
          'ip_hour', v_ip_hour,
          'soft_ip', v_soft_ip,
          'users_today', v_users_today,
          'amen_daily', v_amen_daily,
          'remaining_today', greatest(v_amen_daily - v_users_today, 0)
        );
      end if;
      select exists (
        select 1 from public.signup_challenges c
        where c.token_hash = public._signup_sha256(v_challenge_token)
          and c.consumed_at is not null
          and c.consumed_at > now() - interval '15 minutes'
      ) into v_tok_ok;
      if not v_tok_ok then
        return jsonb_build_object(
          'ok', false,
          'reason', 'challenge_invalid',
          'need_challenge', true
        );
      end if;
    end if;
  end if;

  if not v_dry_run then
    insert into public.signup_attempt_log (
      email_norm, email_hash, ip_text, device_id, outcome, reason, required_challenge
    ) values (
      v_email,
      public._signup_sha256(v_email),
      v_ip,
      v_device_id,
      'allow',
      'ok',
      v_need_challenge
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'reason', 'ok',
    'need_challenge', v_need_challenge,
    'users_today', v_users_today,
    'amen_daily', v_amen_daily,
    'remaining_today', greatest(v_amen_daily - v_users_today, 0),
    'ip_hour', v_ip_hour,
    'soft_ip', v_soft_ip,
    'device_today', v_device_today,
    'email_hour', v_email_hour_cnt
  );
end;
$$;

revoke all on function public.signup_guard_simulate(jsonb) from public;
grant execute on function public.signup_guard_simulate(jsonb) to anon, authenticated, service_role, supabase_auth_admin;

-- Hook Auth: corre ANTES de criar user / enviar email de confirmação
create or replace function public.hook_fleaber_signup_guard(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  email text := lower(trim(coalesce(event->'user'->>'email', '')));
  ip text := nullif(trim(coalesce(event->'metadata'->>'ip_address', '')), '');
  meta jsonb := coalesce(event->'user'->'user_metadata', '{}'::jsonb);
  device_id text := nullif(trim(coalesce(meta->>'device_id', '')), '');
  form_ms int := coalesce((meta->>'form_ms')::int, 999999);
  honeypot text := coalesce(meta->>'hp', '');
  challenge_token text := nullif(trim(coalesce(meta->>'challenge_token', '')), '');
  sim jsonb;
  reason text;
begin
  sim := public.signup_guard_simulate(jsonb_build_object(
    'email', email,
    'ip', ip,
    'device_id', device_id,
    'form_ms', form_ms,
    'hp', honeypot,
    'challenge_token', challenge_token,
    'dry_run', false
  ));

  if coalesce((sim->>'ok')::boolean, false) then
    return '{}'::jsonb;
  end if;

  reason := coalesce(sim->>'reason', 'blocked');

  insert into public.signup_attempt_log (
    email_norm, email_hash, ip_text, device_id, outcome, reason, required_challenge
  ) values (
    email,
    public._signup_sha256(email),
    ip,
    device_id,
    'deny',
    reason,
    coalesce((sim->>'need_challenge')::boolean, false)
  );

  return jsonb_build_object(
    'error', jsonb_build_object(
      'http_code', case when reason = 'challenge_required' then 429 else 403 end,
      'message', case reason
        when 'daily_smtp_budget' then
          'Atingimos o limite diário de novos registos. Tenta amanhã.'
        when 'email_rate' then
          'Demasiadas tentativas com este e-mail. Espera uma hora.'
        when 'device_rate' then
          'Demasiadas contas neste dispositivo hoje. Tenta amanhã.'
        when 'challenge_required' then
          'Precisamos de uma verificação rápida. Completa o desafio e tenta outra vez.'
        when 'challenge_invalid' then
          'Verificação incorrecta ou expirada. Tenta outra vez.'
        when 'denied_domain' then
          'Este domínio de e-mail não é aceite. Usa outro e-mail.'
        when 'bot_honeypot' then
          'Não foi possível criar a conta.'
        when 'bot_too_fast' then
          'Não foi possível criar a conta. Preenche o formulário com calma.'
        else
          'Não foi possível criar a conta neste momento.'
      end
    )
  );
end;
$$;

grant execute on function public.hook_fleaber_signup_guard(jsonb) to supabase_auth_admin;
revoke execute on function public.hook_fleaber_signup_guard(jsonb) from anon, authenticated, public;
