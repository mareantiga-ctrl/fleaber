-- Residuais P2/P3 pós-auditorias 20260830 (staging BATATA)
-- Review reputação · email rate · raffle draw_seed
-- production_touched: false · fase4: false

-- ---------------------------------------------------------------------------
-- P2 review MB WAY: reputação pública SÓ purchase_verified
-- (off-platform continua a poder inserir review; não inflaciona média pública)
-- ---------------------------------------------------------------------------
create or replace view public.reviews_public_ratings
as
select
  id,
  created_at,
  target_id,
  stars,
  comment,
  is_automatic,
  target_type,
  author_role,
  purchase_verified
from public.reviews
where coalesce(purchase_verified, false) = true;

alter view public.reviews_public_ratings set (security_invoker = false);
revoke all on public.reviews_public_ratings from public;
grant select on public.reviews_public_ratings to anon, authenticated, service_role;

comment on view public.reviews_public_ratings is
  'RTBB-1115-P2: reputação pública só com compra plataforma verificada.';

-- ---------------------------------------------------------------------------
-- P3 email→UUID: rate 5/h (convites staff mantêm-se; enum mais lento)
-- ---------------------------------------------------------------------------
create or replace function public.batata_find_user_id_by_email(p_email text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(coalesce(p_email, '')));
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
  v_found uuid;
  v_is_seller boolean := false;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if v_email = '' or position('@' in v_email) = 0 or char_length(v_email) > 320 then
    return null;
  end if;

  select exists (
    select 1 from public.profiles p
    where p.id = v_uid
      and lower(trim(coalesce(p.user_type, ''))) in ('vendedor', 'seller')
  ) into v_is_seller;

  if not v_is_seller then
    return null;
  end if;

  insert into public.batata_rpc_rate_limits (uid, rpc, window_start, hits)
  values (v_uid, 'batata_find_user_id_by_email', v_window, 1)
  on conflict (uid, rpc, window_start)
  do update set hits = public.batata_rpc_rate_limits.hits + 1
  returning hits into v_hits;

  if v_hits > 5 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  select u.id
  into v_found
  from auth.users u
  where lower(trim(u.email)) = v_email
  limit 1;

  return v_found;
end;
$$;

comment on function public.batata_find_user_id_by_email(text) is
  'P3 residual: email→UUID só vendedor; rate 5/h (convites staff).';

revoke all on function public.batata_find_user_id_by_email(text) from public, anon;
grant execute on function public.batata_find_user_id_by_email(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- P3 draw_seed: JWT/anon não lê a coluna (sorteio via DEFINER continua OK)
-- ---------------------------------------------------------------------------
revoke select on public.live_raffles from anon, authenticated;

grant select (
  id,
  live_id,
  seller_id,
  title,
  description,
  photo_url,
  estimated_value_eur,
  winner_count,
  status,
  starts_at,
  ends_at,
  show_public_leaderboard,
  drawn_at,
  created_at,
  updated_at,
  live_item_id
) on public.live_raffles to anon, authenticated;

grant select on public.live_raffles to service_role;

comment on column public.live_raffles.draw_seed is
  'P3: sem SELECT JWT/anon — só service_role / SECURITY DEFINER.';

notify pgrst, 'reload schema';
