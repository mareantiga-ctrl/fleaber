-- Fleaber BATATA: Live Director — rifa exclui contas sim do winner pool.
-- Requer: live_director_batata.sql (batata_is_sim_account).
-- Não altera join; só draw e contagem de elegíveis reais.

create or replace function public.batata_count_real_raffle_participants(p_raffle_id uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
  from public.live_raffle_entries e
  where e.raffle_id = p_raffle_id
    and e.is_eligible
    and e.ticket_balance > 0
    and not public.batata_is_sim_account(e.user_id);
$$;

revoke all on function public.batata_count_real_raffle_participants(uuid) from public;
grant execute on function public.batata_count_real_raffle_participants(uuid) to authenticated;

-- Substitui draw: exclui sim; se zero reais elegíveis → estado honesto sem vencedor bot.
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
  v_real_participants int;
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

  v_real_participants := public.batata_count_real_raffle_participants(p_raffle_id);

  if v_participants < 1 then
    raise exception 'no_participants';
  end if;

  if v_real_participants < 1 then
    perform public.batata_live_raffle_audit(
      p_raffle_id,
      'draw_skipped_no_real_eligible',
      jsonb_build_object(
        'total_participants', v_participants,
        'real_participants', 0,
        'message', 'sem_participantes_reais_elegiveis'
      )
    );
    return jsonb_build_object(
      'ok', false,
      'error', 'no_real_eligible_participants',
      'message', 'Sem participantes reais elegíveis para sorteio.',
      'total_participants', v_participants,
      'real_participants', 0
    );
  end if;

  v_seed := encode(extensions.gen_random_bytes(32), 'hex');
  v_needed := least(v_row.winner_count, v_real_participants);

  for v_rank in 1..v_needed loop
    select coalesce(sum(e.ticket_balance), 0)::bigint into v_total_weight
    from public.live_raffle_entries e
    where e.raffle_id = p_raffle_id
      and e.is_eligible
      and e.ticket_balance > 0
      and not public.batata_is_sim_account(e.user_id)
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
        and not public.batata_is_sim_account(e.user_id)
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
            'total_weight', v_total_weight,
            'real_users_only', true
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
    jsonb_build_object('seed', v_seed, 'winners', v_winners, 'real_users_only', true)
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
        'Vencedor'
      )
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'raffle_id', p_raffle_id,
    'winners', v_winners,
    'real_users_only', true
  );
end;
$$;

revoke all on function public.batata_draw_live_raffle_winners(uuid) from public;
grant execute on function public.batata_draw_live_raffle_winners(uuid) to authenticated;
