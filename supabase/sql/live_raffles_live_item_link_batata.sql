-- Fleaber BATATA: liga prémio da rifa ao artigo do catálogo live (reservas normais + waitlist).
-- Executar após live_raffles_batata.sql.

alter table public.live_raffles
  add column if not exists live_item_id uuid references public.live_items (id) on delete set null;

create index if not exists live_raffles_live_item_idx
  on public.live_raffles (live_item_id)
  where live_item_id is not null;

drop function if exists public.batata_create_live_raffle(
  uuid, text, text, text, numeric, int, timestamptz, boolean, boolean
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
  p_show_public_leaderboard boolean default true,
  p_live_item_id uuid default null
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

  if p_live_item_id is not null then
    if not exists (
      select 1
      from public.live_items li
      where li.id = p_live_item_id
        and li.live_id = p_live_id
    ) then
      raise exception 'live_item_not_in_live';
    end if;
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
    show_public_leaderboard,
    live_item_id
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
    coalesce(p_show_public_leaderboard, true),
    p_live_item_id
  )
  returning * into v_row;

  perform public.batata_live_raffle_audit(
    v_row.id,
    'created',
    jsonb_build_object(
      'status', v_row.status,
      'ends_at', v_row.ends_at,
      'live_item_id', v_row.live_item_id
    )
  );

  return jsonb_build_object(
    'ok', true,
    'raffle_id', v_row.id,
    'status', v_row.status,
    'live_item_id', v_row.live_item_id
  );
end;
$$;

-- Expõe live_item_id no estado da rifa (resto igual ao live_raffles_batata.sql).
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
      'live_item_id', v_raffle.live_item_id,
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

revoke all on function public.batata_create_live_raffle(
  uuid, text, text, text, numeric, int, timestamptz, boolean, boolean, uuid
) from public;
grant execute on function public.batata_create_live_raffle(
  uuid, text, text, text, numeric, int, timestamptz, boolean, boolean, uuid
) to authenticated;
