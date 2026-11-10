-- Fleaber BATATA: Rifa da Live (bloco 1 — núcleo).
-- Executar no SQL Editor após live_streaming_mux_batata.sql e lives existentes.
-- Não altera reservas, checkout, gorjetas nem stock.

-- ---------------------------------------------------------------------------
-- 1) Tabelas
-- ---------------------------------------------------------------------------
create table if not exists public.live_raffles (
  id uuid primary key default extensions.gen_random_uuid(),
  live_id uuid not null references public.lives (id) on delete cascade,
  seller_id uuid not null references auth.users (id) on delete cascade,
  title text not null check (char_length(trim(title)) > 0),
  description text,
  photo_url text,
  estimated_value_eur numeric(12, 2) check (estimated_value_eur is null or estimated_value_eur >= 0),
  winner_count int not null default 1 check (winner_count between 1 and 10),
  status text not null default 'draft'
    check (status in ('draft', 'active', 'closed', 'drawn', 'cancelled')),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  show_public_leaderboard boolean not null default false,
  draw_seed text,
  drawn_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists live_raffles_one_active_per_live_uidx
  on public.live_raffles (live_id)
  where status = 'active';

create index if not exists live_raffles_live_status_idx
  on public.live_raffles (live_id, status, created_at desc);

create table if not exists public.live_raffle_entries (
  id uuid primary key default extensions.gen_random_uuid(),
  raffle_id uuid not null references public.live_raffles (id) on delete cascade,
  live_id uuid not null references public.lives (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  ticket_balance int not null default 0 check (ticket_balance >= 0),
  joined_at timestamptz not null default now(),
  last_ticket_at timestamptz,
  is_eligible boolean not null default true,
  disqualified_at timestamptz,
  disqualify_reason text,
  unique (raffle_id, user_id)
);

create index if not exists live_raffle_entries_raffle_tickets_idx
  on public.live_raffle_entries (raffle_id, ticket_balance desc);

create table if not exists public.live_raffle_actions (
  id uuid primary key default extensions.gen_random_uuid(),
  raffle_id uuid not null references public.live_raffles (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  action_type text not null,
  tickets_delta int not null,
  source_id text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (raffle_id, action_type, source_id)
);

create index if not exists live_raffle_actions_raffle_user_idx
  on public.live_raffle_actions (raffle_id, user_id, created_at desc);

create table if not exists public.live_raffle_winners (
  id uuid primary key default extensions.gen_random_uuid(),
  raffle_id uuid not null references public.live_raffles (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  entry_id uuid references public.live_raffle_entries (id) on delete set null,
  rank int not null check (rank > 0),
  tickets_at_draw int not null default 0 check (tickets_at_draw >= 0),
  draw_proof jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (raffle_id, rank),
  unique (raffle_id, user_id)
);

create table if not exists public.live_raffle_lifetime_grants (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  seller_id uuid not null references auth.users (id) on delete cascade,
  grant_type text not null,
  first_granted_at timestamptz not null default now(),
  first_raffle_id uuid references public.live_raffles (id) on delete set null,
  unique (user_id, seller_id, grant_type)
);

create table if not exists public.live_raffle_audit_log (
  id uuid primary key default extensions.gen_random_uuid(),
  raffle_id uuid not null references public.live_raffles (id) on delete cascade,
  actor_user_id uuid references auth.users (id) on delete set null,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists live_raffle_audit_log_raffle_idx
  on public.live_raffle_audit_log (raffle_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 2) RLS (leitura limitada; mutações via RPC)
-- ---------------------------------------------------------------------------
alter table public.live_raffles enable row level security;
alter table public.live_raffle_entries enable row level security;
alter table public.live_raffle_actions enable row level security;
alter table public.live_raffle_winners enable row level security;
alter table public.live_raffle_lifetime_grants enable row level security;
alter table public.live_raffle_audit_log enable row level security;

drop policy if exists live_raffles_select_auth on public.live_raffles;
create policy live_raffles_select_auth
  on public.live_raffles for select to authenticated
  using (true);

drop policy if exists live_raffle_entries_select_own_or_seller on public.live_raffle_entries;
create policy live_raffle_entries_select_own_or_seller
  on public.live_raffle_entries for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.live_raffles r
      where r.id = raffle_id and r.seller_id = auth.uid()
    )
  );

drop policy if exists live_raffle_actions_select_own on public.live_raffle_actions;
create policy live_raffle_actions_select_own
  on public.live_raffle_actions for select to authenticated
  using (user_id = auth.uid());

drop policy if exists live_raffle_winners_select_auth on public.live_raffle_winners;
create policy live_raffle_winners_select_auth
  on public.live_raffle_winners for select to authenticated
  using (true);

drop policy if exists live_raffle_lifetime_grants_select_own on public.live_raffle_lifetime_grants;
create policy live_raffle_lifetime_grants_select_own
  on public.live_raffle_lifetime_grants for select to authenticated
  using (user_id = auth.uid());

drop policy if exists live_raffle_audit_seller on public.live_raffle_audit_log;
create policy live_raffle_audit_seller
  on public.live_raffle_audit_log for select to authenticated
  using (
    exists (
      select 1 from public.live_raffles r
      where r.id = raffle_id and r.seller_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 3) Helpers internos
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_raffle_live_seller(p_live_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(l.seller_id, l.vendedor_id)
  from public.lives l
  where l.id = p_live_id;
$$;

create or replace function public.batata_live_raffle_assert_seller(p_live_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_seller uuid;
begin
  v_seller := public.batata_live_raffle_live_seller(p_live_id);
  if v_seller is null then
    raise exception 'live_not_found';
  end if;
  if auth.uid() is distinct from v_seller
     and not public.batata_staff_has_permission(v_seller, 'can_view_live_dashboard') then
    raise exception 'not_allowed';
  end if;
  return v_seller;
end;
$$;

create or replace function public.batata_live_raffle_touch_updated()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists live_raffles_touch_updated_trg on public.live_raffles;
create trigger live_raffles_touch_updated_trg
  before update on public.live_raffles
  for each row execute function public.batata_live_raffle_touch_updated();

create or replace function public.batata_live_raffle_audit(
  p_raffle_id uuid,
  p_event_type text,
  p_payload jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.live_raffle_audit_log (raffle_id, actor_user_id, event_type, payload)
  values (p_raffle_id, auth.uid(), p_event_type, coalesce(p_payload, '{}'::jsonb));
end;
$$;

create or replace function public.batata_award_live_raffle_tickets(
  p_raffle_id uuid,
  p_user_id uuid,
  p_action_type text,
  p_tickets_delta int,
  p_source_id text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_raffle public.live_raffles%rowtype;
  v_entry public.live_raffle_entries%rowtype;
  v_delta int;
begin
  if p_raffle_id is null or p_user_id is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_args');
  end if;

  v_delta := coalesce(p_tickets_delta, 0);
  if v_delta = 0 then
    return jsonb_build_object('ok', false, 'error', 'zero_delta');
  end if;

  select * into v_raffle from public.live_raffles where id = p_raffle_id;
  if v_raffle.id is null then
    return jsonb_build_object('ok', false, 'error', 'raffle_not_found');
  end if;

  if v_raffle.status <> 'active' then
    return jsonb_build_object('ok', false, 'error', 'raffle_not_active');
  end if;

  if v_raffle.ends_at is not null and v_raffle.ends_at <= now() then
    return jsonb_build_object('ok', false, 'error', 'raffle_ended');
  end if;

  if exists (
    select 1 from public.live_raffle_actions a
    where a.raffle_id = p_raffle_id
      and a.action_type = p_action_type
      and a.source_id = p_source_id
  ) then
    select * into v_entry
    from public.live_raffle_entries
    where raffle_id = p_raffle_id and user_id = p_user_id;
    return jsonb_build_object(
      'ok', true,
      'duplicate', true,
      'ticket_balance', coalesce(v_entry.ticket_balance, 0)
    );
  end if;

  insert into public.live_raffle_entries (raffle_id, live_id, user_id, ticket_balance, last_ticket_at)
  values (p_raffle_id, v_raffle.live_id, p_user_id, 0, now())
  on conflict (raffle_id, user_id) do nothing;

  select * into v_entry
  from public.live_raffle_entries
  where raffle_id = p_raffle_id and user_id = p_user_id
  for update;

  if not v_entry.is_eligible then
    return jsonb_build_object('ok', false, 'error', 'not_eligible');
  end if;

  insert into public.live_raffle_actions (
    raffle_id, user_id, action_type, tickets_delta, source_id, metadata
  ) values (
    p_raffle_id, p_user_id, p_action_type, v_delta, p_source_id, coalesce(p_metadata, '{}'::jsonb)
  );

  update public.live_raffle_entries
  set ticket_balance = greatest(ticket_balance + v_delta, 0),
      last_ticket_at = now()
  where id = v_entry.id
  returning * into v_entry;

  perform public.batata_live_raffle_audit(
    p_raffle_id,
    'tickets_awarded',
    jsonb_build_object(
      'user_id', p_user_id,
      'action_type', p_action_type,
      'tickets_delta', v_delta,
      'ticket_balance', v_entry.ticket_balance
    )
  );

  return jsonb_build_object(
    'ok', true,
    'ticket_balance', v_entry.ticket_balance,
    'entry_id', v_entry.id
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4) RPCs públicas (bloco 1)
-- ---------------------------------------------------------------------------
drop function if exists public.batata_create_live_raffle(
  uuid, text, text, text, numeric, int, timestamptz, boolean
);

create or replace function public.batata_create_live_raffle(
  p_live_id uuid,
  p_title text,
  p_description text default null,
  p_photo_url text default null,
  p_estimated_value_eur numeric default null,
  p_winner_count int default 1,
  p_ends_at timestamptz default null,
  p_activate boolean default true,
  p_show_public_leaderboard boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seller uuid;
  v_row public.live_raffles%rowtype;
  v_title text;
begin
  v_seller := public.batata_live_raffle_assert_seller(p_live_id);
  v_title := trim(coalesce(p_title, ''));
  if v_title = '' then
    raise exception 'title_required';
  end if;

  if p_activate and exists (
    select 1 from public.live_raffles r
    where r.live_id = p_live_id and r.status = 'active'
  ) then
    raise exception 'active_raffle_exists';
  end if;

  insert into public.live_raffles (
    live_id,
    seller_id,
    title,
    description,
    photo_url,
    estimated_value_eur,
    winner_count,
    status,
    ends_at,
    show_public_leaderboard
  ) values (
    p_live_id,
    v_seller,
    v_title,
    nullif(trim(coalesce(p_description, '')), ''),
    nullif(trim(coalesce(p_photo_url, '')), ''),
    p_estimated_value_eur,
    greatest(coalesce(p_winner_count, 1), 1),
    case when coalesce(p_activate, true) then 'active' else 'draft' end,
    p_ends_at,
    coalesce(p_show_public_leaderboard, true)
  )
  returning * into v_row;

  perform public.batata_live_raffle_audit(
    v_row.id,
    'created',
    jsonb_build_object('status', v_row.status, 'ends_at', v_row.ends_at)
  );

  return jsonb_build_object('ok', true, 'raffle_id', v_row.id, 'status', v_row.status);
end;
$$;

create or replace function public.batata_activate_live_raffle(p_raffle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.live_raffles%rowtype;
begin
  select * into v_row from public.live_raffles where id = p_raffle_id;
  if v_row.id is null then
    raise exception 'raffle_not_found';
  end if;

  perform public.batata_live_raffle_assert_seller(v_row.live_id);

  if v_row.status <> 'draft' then
    raise exception 'invalid_status';
  end if;

  if exists (
    select 1 from public.live_raffles r
    where r.live_id = v_row.live_id and r.status = 'active' and r.id <> v_row.id
  ) then
    raise exception 'active_raffle_exists';
  end if;

  update public.live_raffles
  set status = 'active', starts_at = now()
  where id = p_raffle_id
  returning * into v_row;

  perform public.batata_live_raffle_audit(v_row.id, 'activated', '{}'::jsonb);
  return jsonb_build_object('ok', true, 'status', v_row.status);
end;
$$;

create or replace function public.batata_cancel_live_raffle(
  p_raffle_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.live_raffles%rowtype;
begin
  select * into v_row from public.live_raffles where id = p_raffle_id;
  if v_row.id is null then
    raise exception 'raffle_not_found';
  end if;

  perform public.batata_live_raffle_assert_seller(v_row.live_id);

  if v_row.status in ('drawn', 'cancelled') then
    raise exception 'invalid_status';
  end if;

  update public.live_raffles set status = 'cancelled' where id = p_raffle_id
  returning * into v_row;

  perform public.batata_live_raffle_audit(
    v_row.id,
    'cancelled',
    jsonb_build_object('reason', coalesce(p_reason, ''))
  );

  return jsonb_build_object('ok', true, 'status', v_row.status);
end;
$$;

create or replace function public.batata_close_live_raffle(p_raffle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.live_raffles%rowtype;
begin
  select * into v_row from public.live_raffles where id = p_raffle_id;
  if v_row.id is null then
    raise exception 'raffle_not_found';
  end if;

  perform public.batata_live_raffle_assert_seller(v_row.live_id);

  if v_row.status <> 'active' then
    raise exception 'invalid_status';
  end if;

  update public.live_raffles set status = 'closed' where id = p_raffle_id
  returning * into v_row;

  perform public.batata_live_raffle_audit(v_row.id, 'closed', '{}'::jsonb);
  return jsonb_build_object('ok', true, 'status', v_row.status);
end;
$$;

create or replace function public.batata_join_live_raffle(p_raffle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_award jsonb;
begin
  if v_uid is null then
    raise exception 'auth_required';
  end if;

  v_award := public.batata_award_live_raffle_tickets(
    p_raffle_id,
    v_uid,
    'join',
    1,
    'join:' || v_uid::text
  );

  if coalesce(v_award->>'ok', 'false') <> 'true' then
    return v_award;
  end if;

  perform public.batata_live_raffle_audit(
    p_raffle_id,
    'joined',
    jsonb_build_object('user_id', v_uid, 'ticket_balance', v_award->'ticket_balance')
  );

  return jsonb_build_object(
    'ok', true,
    'joined', true,
    'ticket_balance', v_award->'ticket_balance',
    'duplicate', coalesce(v_award->>'duplicate', 'false') = 'true'
  );
end;
$$;

create or replace function public.batata_tick_live_raffle(p_raffle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.live_raffles%rowtype;
begin
  select * into v_row from public.live_raffles where id = p_raffle_id;
  if v_row.id is null then
    return jsonb_build_object('ok', false, 'error', 'raffle_not_found');
  end if;

  if v_row.status = 'active'
     and v_row.ends_at is not null
     and v_row.ends_at <= now() then
    update public.live_raffles set status = 'closed' where id = p_raffle_id
    returning * into v_row;
    perform public.batata_live_raffle_audit(v_row.id, 'auto_closed', '{}'::jsonb);
  end if;

  return jsonb_build_object('ok', true, 'status', v_row.status);
end;
$$;

create or replace function public.batata_get_live_raffle_state(p_live_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_uid uuid := auth.uid();
  v_raffle public.live_raffles%rowtype;
  v_entry public.live_raffle_entries%rowtype;
  v_winners jsonb := '[]'::jsonb;
  v_leaderboard jsonb := '[]'::jsonb;
  v_seconds_left int;
begin
  if p_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'live_required');
  end if;

  select * into v_raffle
  from public.live_raffles r
  where r.live_id = p_live_id
    and r.status in ('active', 'closed', 'drawn')
  order by
    case r.status
      when 'active' then 1
      when 'closed' then 2
      else 3
    end,
    r.created_at desc,
    r.id desc
  limit 1;

  if v_raffle.id is null then
    return jsonb_build_object('ok', true, 'has_raffle', false);
  end if;

  if v_raffle.status = 'active'
     and v_raffle.ends_at is not null
     and v_raffle.ends_at <= now() then
    v_raffle.status := 'closed';
  end if;

  if v_uid is not null then
    select * into v_entry
    from public.live_raffle_entries e
    where e.raffle_id = v_raffle.id and e.user_id = v_uid;
  end if;

  if v_raffle.status = 'drawn' then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'rank', w.rank,
          'user_id', w.user_id,
          'display_name', coalesce(p.full_name, 'Participante'),
          'tickets_at_draw', w.tickets_at_draw
        )
        order by w.rank
      ),
      '[]'::jsonb
    )
    into v_winners
    from public.live_raffle_winners w
    left join public.profiles p on p.id = w.user_id
    where w.raffle_id = v_raffle.id;
  end if;

  if v_raffle.ends_at is not null and v_raffle.status = 'active' then
    v_seconds_left := greatest(
      extract(epoch from (v_raffle.ends_at - now()))::int,
      0
    );
  end if;

  if v_raffle.show_public_leaderboard then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'rank', row_number,
          'user_id', user_id,
          'display_name', display_name,
          'ticket_balance', ticket_balance
        )
        order by row_number
      ),
      '[]'::jsonb
    )
    into v_leaderboard
    from (
      select
        row_number() over (
          order by e.ticket_balance desc, e.last_ticket_at asc nulls last, e.id
        ) as row_number,
        e.user_id,
        coalesce(nullif(trim(p.full_name), ''), 'Participante') as display_name,
        e.ticket_balance
      from public.live_raffle_entries e
      left join public.profiles p on p.id = e.user_id
      where e.raffle_id = v_raffle.id
        and e.is_eligible
        and e.ticket_balance > 0
      limit 5
    ) lb;
  end if;

  return jsonb_build_object(
    'ok', true,
    'has_raffle', true,
    'raffle', jsonb_build_object(
      'id', v_raffle.id,
      'live_id', v_raffle.live_id,
      'title', v_raffle.title,
      'description', v_raffle.description,
      'photo_url', v_raffle.photo_url,
      'estimated_value_eur', v_raffle.estimated_value_eur,
      'winner_count', v_raffle.winner_count,
      'status', v_raffle.status,
      'starts_at', v_raffle.starts_at,
      'ends_at', v_raffle.ends_at,
      'has_timer', v_raffle.ends_at is not null,
      'seconds_left', v_seconds_left,
      'show_public_leaderboard', v_raffle.show_public_leaderboard,
      'drawn_at', v_raffle.drawn_at
    ),
    'viewer', jsonb_build_object(
      'joined', v_entry.id is not null,
      'ticket_balance', coalesce(v_entry.ticket_balance, 0),
      'is_winner', exists (
        select 1 from public.live_raffle_winners w
        where w.raffle_id = v_raffle.id and w.user_id = v_uid
      ),
      'follow_bonus_claimed', (
        v_uid is not null
        and exists (
          select 1
          from public.live_raffle_lifetime_grants g
          where g.user_id = v_uid
            and g.seller_id = v_raffle.seller_id
            and g.grant_type = 'follow_seller'
        )
      ),
      'share_bonus_claimed', (
        v_uid is not null
        and exists (
          select 1
          from public.live_raffle_actions a
          where a.raffle_id = v_raffle.id
            and a.user_id = v_uid
            and a.action_type = 'share'
        )
      ),
      'purchase_bonus_claimed', (
        v_uid is not null
        and exists (
          select 1
          from public.live_raffle_actions a
          where a.raffle_id = v_raffle.id
            and a.user_id = v_uid
            and a.action_type = 'purchase'
        )
      )
    ),
    'leaderboard', v_leaderboard,
    'winners', v_winners
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Bloco 2 — Seguir vendedor (+1 lifetime, trigger em follows)
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_raffle_on_follow_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_raffle_id uuid;
  v_award jsonb;
begin
  if new.follower_id is null or new.following_id is null then
    return new;
  end if;

  if new.follower_id = new.following_id then
    return new;
  end if;

  if exists (
    select 1
    from public.live_raffle_lifetime_grants g
    where g.user_id = new.follower_id
      and g.seller_id = new.following_id
      and g.grant_type = 'follow_seller'
  ) then
    return new;
  end if;

  select r.id into v_raffle_id
  from public.live_raffles r
  where r.seller_id = new.following_id
    and r.status = 'active'
  order by r.created_at desc, r.id desc
  limit 1;

  if v_raffle_id is null then
    return new;
  end if;

  v_award := public.batata_award_live_raffle_tickets(
    v_raffle_id,
    new.follower_id,
    'follow',
    1,
    'follow_lifetime:' || new.following_id::text
  );

  if coalesce(v_award->>'ok', 'false') <> 'true' then
    return new;
  end if;

  insert into public.live_raffle_lifetime_grants (
    user_id,
    seller_id,
    grant_type,
    first_raffle_id
  ) values (
    new.follower_id,
    new.following_id,
    'follow_seller',
    v_raffle_id
  )
  on conflict (user_id, seller_id, grant_type) do nothing;

  perform public.batata_live_raffle_audit(
    v_raffle_id,
    'follow_lifetime_awarded',
    jsonb_build_object(
      'user_id', new.follower_id,
      'seller_id', new.following_id,
      'ticket_balance', v_award->'ticket_balance',
      'duplicate', coalesce(v_award->>'duplicate', 'false') = 'true'
    )
  );

  return new;
end;
$$;

drop trigger if exists live_raffle_follow_award_trg on public.follows;
create trigger live_raffle_follow_award_trg
  after insert on public.follows
  for each row
  execute function public.batata_live_raffle_on_follow_insert();

-- ---------------------------------------------------------------------------
-- Bloco 3 — Partilhar live (+1 intenção, uma vez por rifa)
-- ---------------------------------------------------------------------------
create or replace function public.batata_claim_live_raffle_share_intent(p_raffle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_raffle public.live_raffles%rowtype;
  v_award jsonb;
begin
  if v_uid is null then
    raise exception 'auth_required';
  end if;

  select * into v_raffle from public.live_raffles where id = p_raffle_id;
  if v_raffle.id is null then
    return jsonb_build_object('ok', false, 'error', 'raffle_not_found');
  end if;

  if v_raffle.status <> 'active' then
    return jsonb_build_object('ok', false, 'error', 'raffle_not_active');
  end if;

  if not exists (
    select 1
    from public.live_raffle_entries e
    where e.raffle_id = p_raffle_id and e.user_id = v_uid
  ) then
    return jsonb_build_object('ok', false, 'error', 'join_required');
  end if;

  v_award := public.batata_award_live_raffle_tickets(
    p_raffle_id,
    v_uid,
    'share',
    1,
    'share_intent:' || v_uid::text
  );

  if coalesce(v_award->>'ok', 'false') <> 'true' then
    return v_award;
  end if;

  perform public.batata_live_raffle_audit(
    p_raffle_id,
    'share_intent_claimed',
    jsonb_build_object(
      'user_id', v_uid,
      'ticket_balance', v_award->'ticket_balance',
      'duplicate', coalesce(v_award->>'duplicate', 'false') = 'true'
    )
  );

  return jsonb_build_object(
    'ok', true,
    'ticket_balance', v_award->'ticket_balance',
    'duplicate', coalesce(v_award->>'duplicate', 'false') = 'true'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Bloco 7 — Chat social (mensagens sistema, humanizer no cliente)
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_raffle_social_broadcast(
  p_live_id uuid,
  p_body text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_body text;
begin
  if p_live_id is null then
    return;
  end if;
  v_body := trim(coalesce(p_body, ''));
  if v_body = '' then
    return;
  end if;

  insert into public.live_messages (
    live_id,
    user_id,
    kind,
    body,
    sender_label
  ) values (
    p_live_id,
    auth.uid(),
    'system',
    '🎟️ Rifa: ' || v_body,
    'Rifa da Live'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Bloco 4 — Links de partilha + visitantes qualificados (+2 referrer)
-- ---------------------------------------------------------------------------
create table if not exists public.live_raffle_referral_links (
  id uuid primary key default extensions.gen_random_uuid(),
  raffle_id uuid not null references public.live_raffles (id) on delete cascade,
  live_id uuid not null references public.lives (id) on delete cascade,
  referrer_user_id uuid not null references auth.users (id) on delete cascade,
  code text not null,
  created_at timestamptz not null default now(),
  unique (raffle_id, referrer_user_id),
  unique (code)
);

create index if not exists live_raffle_referral_links_live_idx
  on public.live_raffle_referral_links (live_id, referrer_user_id);

create table if not exists public.live_raffle_referral_visits (
  id uuid primary key default extensions.gen_random_uuid(),
  link_id uuid not null references public.live_raffle_referral_links (id) on delete cascade,
  visitor_user_id uuid not null references auth.users (id) on delete cascade,
  live_id uuid not null references public.lives (id) on delete cascade,
  first_seen_at timestamptz not null default now(),
  qualified_at timestamptz,
  referrer_awarded boolean not null default false,
  unique (link_id, visitor_user_id)
);

create index if not exists live_raffle_referral_visits_live_idx
  on public.live_raffle_referral_visits (live_id, visitor_user_id);

alter table public.live_raffle_referral_links enable row level security;
alter table public.live_raffle_referral_visits enable row level security;

drop policy if exists live_raffle_referral_links_select_auth on public.live_raffle_referral_links;
create policy live_raffle_referral_links_select_auth
  on public.live_raffle_referral_links for select to authenticated
  using (true);

drop policy if exists live_raffle_referral_visits_select_own on public.live_raffle_referral_visits;
create policy live_raffle_referral_visits_select_own
  on public.live_raffle_referral_visits for select to authenticated
  using (visitor_user_id = auth.uid());

create or replace function public.batata_ensure_live_raffle_referral_link(p_raffle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_raffle public.live_raffles%rowtype;
  v_row public.live_raffle_referral_links%rowtype;
  v_code text;
begin
  if v_uid is null then
    raise exception 'auth_required';
  end if;

  select * into v_raffle from public.live_raffles where id = p_raffle_id;
  if v_raffle.id is null then
    return jsonb_build_object('ok', false, 'error', 'raffle_not_found');
  end if;

  select * into v_row
  from public.live_raffle_referral_links l
  where l.raffle_id = p_raffle_id and l.referrer_user_id = v_uid;

  if v_row.id is not null then
    return jsonb_build_object('ok', true, 'code', v_row.code, 'existing', true);
  end if;

  loop
    v_code := lower(substr(encode(extensions.gen_random_bytes(5), 'hex'), 1, 10));
    exit when not exists (
      select 1 from public.live_raffle_referral_links where code = v_code
    );
  end loop;

  insert into public.live_raffle_referral_links (
    raffle_id, live_id, referrer_user_id, code
  ) values (
    p_raffle_id, v_raffle.live_id, v_uid, v_code
  )
  returning * into v_row;

  return jsonb_build_object('ok', true, 'code', v_row.code, 'existing', false);
end;
$$;

create or replace function public.batata_register_live_raffle_referral_visit(
  p_live_id uuid,
  p_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_link public.live_raffle_referral_links%rowtype;
  v_code text;
begin
  if v_uid is null then
    raise exception 'auth_required';
  end if;

  v_code := lower(trim(coalesce(p_code, '')));
  if v_code = '' or p_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_args');
  end if;

  select * into v_link
  from public.live_raffle_referral_links l
  where l.code = v_code and l.live_id = p_live_id;

  if v_link.id is null then
    return jsonb_build_object('ok', false, 'error', 'link_not_found');
  end if;

  if v_link.referrer_user_id = v_uid then
    return jsonb_build_object('ok', false, 'error', 'self_referral');
  end if;

  insert into public.live_raffle_referral_visits (
    link_id, visitor_user_id, live_id
  ) values (
    v_link.id, v_uid, p_live_id
  )
  on conflict (link_id, visitor_user_id) do nothing;

  return jsonb_build_object('ok', true, 'registered', true);
end;
$$;

create or replace function public.batata_qualify_live_raffle_referral_visits(p_live_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_visit record;
  v_link public.live_raffle_referral_links%rowtype;
  v_raffle public.live_raffles%rowtype;
  v_award jsonb;
  v_qualified int := 0;
begin
  if p_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'live_required');
  end if;

  for v_visit in
    select v.*
    from public.live_raffle_referral_visits v
    where v.live_id = p_live_id
      and v.qualified_at is null
      and v.first_seen_at <= now() - interval '60 seconds'
  loop
    select * into v_link from public.live_raffle_referral_links where id = v_visit.link_id;
    if v_link.id is null then
      continue;
    end if;

    select * into v_raffle from public.live_raffles where id = v_link.raffle_id;
    if v_raffle.id is null or v_raffle.status <> 'active' then
      continue;
    end if;

    update public.live_raffle_referral_visits
    set qualified_at = now()
    where id = v_visit.id and qualified_at is null;

    if not found then
      continue;
    end if;

    if v_visit.referrer_awarded then
      continue;
    end if;

    v_award := public.batata_award_live_raffle_tickets(
      v_link.raffle_id,
      v_link.referrer_user_id,
      'referral',
      2,
      'referral_visit:' || v_visit.id::text
    );

    if coalesce(v_award->>'ok', 'false') = 'true' then
      update public.live_raffle_referral_visits
      set referrer_awarded = true
      where id = v_visit.id;

      perform public.batata_live_raffle_social_broadcast(
        p_live_id,
        coalesce(
          (select nullif(trim(p.full_name), '') from public.profiles p where p.id = v_link.referrer_user_id),
          'Alguém'
        ) || ' ganhou +2 rifas — visitante qualificado'
      );

      v_qualified := v_qualified + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'qualified', v_qualified);
end;
$$;

-- ---------------------------------------------------------------------------
-- Bloco 5 — Compra paga (+2 por order_id)
-- ---------------------------------------------------------------------------
create or replace function public.batata_award_live_raffle_purchase_bonus(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_raffle public.live_raffles%rowtype;
  v_award jsonb;
begin
  if v_uid is null or p_order_id is null then
    return jsonb_build_object('ok', false, 'error', 'auth_required');
  end if;

  select * into v_order from public.orders where id = p_order_id;
  if v_order.id is null then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  if v_order.buyer_id is distinct from v_uid then
    return jsonb_build_object('ok', false, 'error', 'not_buyer');
  end if;

  if lower(trim(coalesce(v_order.status, ''))) not in (
    'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
  ) then
    return jsonb_build_object('ok', false, 'error', 'order_not_paid');
  end if;

  if v_order.live_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_live_order');
  end if;

  select * into v_raffle
  from public.live_raffles r
  where r.live_id = v_order.live_id
    and r.status = 'active'
  order by r.created_at desc, r.id desc
  limit 1;

  if v_raffle.id is null then
    return jsonb_build_object('ok', false, 'error', 'no_active_raffle');
  end if;

  if not exists (
    select 1 from public.live_raffle_entries e
    where e.raffle_id = v_raffle.id and e.user_id = v_uid
  ) then
    return jsonb_build_object('ok', false, 'error', 'join_required');
  end if;

  v_award := public.batata_award_live_raffle_tickets(
    v_raffle.id,
    v_uid,
    'purchase',
    2,
    'purchase_order:' || p_order_id::text
  );

  if coalesce(v_award->>'ok', 'false') <> 'true' then
    return v_award;
  end if;

  if coalesce(v_award->>'duplicate', 'false') <> 'true' then
    perform public.batata_live_raffle_social_broadcast(
      v_order.live_id,
      coalesce(
        (select nullif(trim(p.full_name), '') from public.profiles p where p.id = v_uid),
        'Comprador'
      ) || ' ganhou +2 rifas com a compra'
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'ticket_balance', v_award->'ticket_balance',
    'duplicate', coalesce(v_award->>'duplicate', 'false') = 'true'
  );
end;
$$;

create or replace function public.batata_draw_live_raffle_winners(p_raffle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.live_raffles%rowtype;
  v_seed text;
  v_rank int;
  v_needed int;
  v_total_weight bigint;
  v_pick bigint;
  v_cursor bigint := 0;
  v_winner record;
  v_winners jsonb := '[]'::jsonb;
  v_participants int;
begin
  select * into v_row from public.live_raffles where id = p_raffle_id for update;
  if v_row.id is null then
    raise exception 'raffle_not_found';
  end if;

  perform public.batata_live_raffle_assert_seller(v_row.live_id);

  if v_row.status = 'active' then
    if v_row.ends_at is not null and v_row.ends_at <= now() then
      update public.live_raffles set status = 'closed' where id = p_raffle_id
      returning * into v_row;
    else
      raise exception 'raffle_still_active';
    end if;
  end if;

  if v_row.status <> 'closed' then
    raise exception 'invalid_status';
  end if;

  select count(*)::int into v_participants
  from public.live_raffle_entries e
  where e.raffle_id = p_raffle_id
    and e.is_eligible
    and e.ticket_balance > 0;

  if v_participants < 1 then
    raise exception 'no_participants';
  end if;

  v_seed := encode(extensions.gen_random_bytes(32), 'hex');
  v_needed := least(v_row.winner_count, v_participants);

  for v_rank in 1..v_needed loop
    select coalesce(sum(e.ticket_balance), 0)::bigint into v_total_weight
    from public.live_raffle_entries e
    where e.raffle_id = p_raffle_id
      and e.is_eligible
      and e.ticket_balance > 0
      and not exists (
        select 1 from public.live_raffle_winners w
        where w.raffle_id = p_raffle_id and w.user_id = e.user_id
      );

    if v_total_weight < 1 then
      exit;
    end if;

    v_pick := (abs(hashtextextended(v_seed || ':' || v_rank::text, 0)) % v_total_weight) + 1;
    v_cursor := 0;

    for v_winner in
      select e.id as entry_id, e.user_id, e.ticket_balance
      from public.live_raffle_entries e
      where e.raffle_id = p_raffle_id
        and e.is_eligible
        and e.ticket_balance > 0
        and not exists (
          select 1 from public.live_raffle_winners w
          where w.raffle_id = p_raffle_id and w.user_id = e.user_id
        )
      order by e.id
    loop
      v_cursor := v_cursor + v_winner.ticket_balance;
      if v_cursor >= v_pick then
        insert into public.live_raffle_winners (
          raffle_id, user_id, entry_id, rank, tickets_at_draw, draw_proof
        ) values (
          p_raffle_id,
          v_winner.user_id,
          v_winner.entry_id,
          v_rank,
          v_winner.ticket_balance,
          jsonb_build_object(
            'seed', v_seed,
            'rank', v_rank,
            'pick', v_pick,
            'total_weight', v_total_weight
          )
        );
        v_winners := v_winners || jsonb_build_array(
          jsonb_build_object(
            'rank', v_rank,
            'user_id', v_winner.user_id,
            'tickets_at_draw', v_winner.ticket_balance
          )
        );
        exit;
      end if;
    end loop;
  end loop;

  if jsonb_array_length(v_winners) < 1 then
    raise exception 'draw_failed';
  end if;

  update public.live_raffles
  set status = 'drawn',
      draw_seed = v_seed,
      drawn_at = now()
  where id = p_raffle_id
  returning * into v_row;

  perform public.batata_live_raffle_audit(
    p_raffle_id,
    'drawn',
    jsonb_build_object('seed', v_seed, 'winners', v_winners)
  );

  if jsonb_array_length(v_winners) > 0 then
    perform public.batata_live_raffle_social_broadcast(
      v_row.live_id,
      coalesce(
        (
          select nullif(trim(p.full_name), '')
          from public.profiles p
          where p.id = (v_winners->0->>'user_id')::uuid
        ),
        'Participante'
      ) || ' ganhou a Rifa da Live!'
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'status', v_row.status,
    'draw_seed', v_seed,
    'winners', v_winners
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5) Grants
-- ---------------------------------------------------------------------------
revoke all on function public.batata_create_live_raffle(
  uuid, text, text, text, numeric, int, timestamptz, boolean, boolean
) from public;
grant execute on function public.batata_create_live_raffle(
  uuid, text, text, text, numeric, int, timestamptz, boolean, boolean
) to authenticated;

revoke all on function public.batata_activate_live_raffle(uuid) from public;
grant execute on function public.batata_activate_live_raffle(uuid) to authenticated;

revoke all on function public.batata_cancel_live_raffle(uuid, text) from public;
grant execute on function public.batata_cancel_live_raffle(uuid, text) to authenticated;

revoke all on function public.batata_close_live_raffle(uuid) from public;
grant execute on function public.batata_close_live_raffle(uuid) to authenticated;

revoke all on function public.batata_join_live_raffle(uuid) from public;
grant execute on function public.batata_join_live_raffle(uuid) to authenticated;

revoke all on function public.batata_get_live_raffle_state(uuid) from public;
grant execute on function public.batata_get_live_raffle_state(uuid) to authenticated;

revoke all on function public.batata_draw_live_raffle_winners(uuid) from public;
grant execute on function public.batata_draw_live_raffle_winners(uuid) to authenticated;

revoke all on function public.batata_tick_live_raffle(uuid) from public;
grant execute on function public.batata_tick_live_raffle(uuid) to authenticated;

revoke all on function public.batata_award_live_raffle_tickets(uuid, uuid, text, int, text, jsonb) from public;
grant execute on function public.batata_award_live_raffle_tickets(uuid, uuid, text, int, text, jsonb) to authenticated;

revoke all on function public.batata_claim_live_raffle_share_intent(uuid) from public;
grant execute on function public.batata_claim_live_raffle_share_intent(uuid) to authenticated;

revoke all on function public.batata_ensure_live_raffle_referral_link(uuid) from public;
grant execute on function public.batata_ensure_live_raffle_referral_link(uuid) to authenticated;

revoke all on function public.batata_register_live_raffle_referral_visit(uuid, text) from public;
grant execute on function public.batata_register_live_raffle_referral_visit(uuid, text) to authenticated;

revoke all on function public.batata_qualify_live_raffle_referral_visits(uuid) from public;
grant execute on function public.batata_qualify_live_raffle_referral_visits(uuid) to authenticated;

revoke all on function public.batata_award_live_raffle_purchase_bonus(uuid) from public;
grant execute on function public.batata_award_live_raffle_purchase_bonus(uuid) to authenticated;

revoke all on function public.batata_live_raffle_social_broadcast(uuid, text) from public;
grant execute on function public.batata_live_raffle_social_broadcast(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6) Realtime
-- ---------------------------------------------------------------------------
do $$
begin
  alter publication supabase_realtime add table public.live_raffles;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.live_raffle_entries;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.live_raffle_winners;
exception when duplicate_object then null;
end $$;
