-- SEC-016 suporte — rate limit genérico para edges (service_role)
-- Usado por resolve-mux-playback (e reutilizável). Depende de batata_anon_rate_limits
-- (criada em sec_008_009_010_020_021_batata.sql — corre #6 antes deste).
-- BATATA: não altera schema de lives / Mux keys.

create table if not exists public.batata_anon_rate_limits (
  rate_key text not null,
  rpc text not null,
  window_start timestamptz not null,
  hits int not null default 0,
  primary key (rate_key, rpc, window_start)
);

create or replace function public.batata_anon_rate_check(
  p_rate_key text,
  p_rpc text,
  p_max_hits int default 40
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
  v_key text := left(lower(trim(coalesce(p_rate_key, ''))), 200);
  v_rpc text := left(trim(coalesce(p_rpc, '')), 80);
  v_max int := greatest(coalesce(p_max_hits, 40), 1);
begin
  if v_key = '' or v_rpc = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;

  insert into public.batata_anon_rate_limits (rate_key, rpc, window_start, hits)
  values (v_key, v_rpc, v_window, 1)
  on conflict (rate_key, rpc, window_start) do update
  set hits = public.batata_anon_rate_limits.hits + 1
  returning hits into v_hits;

  if v_hits > v_max then
    return jsonb_build_object(
      'ok', false,
      'error', 'rate_limited',
      'hits', v_hits,
      'max', v_max
    );
  end if;

  return jsonb_build_object('ok', true, 'hits', v_hits, 'max', v_max);
end;
$$;

revoke all on function public.batata_anon_rate_check(text, text, int) from public, anon, authenticated;
grant execute on function public.batata_anon_rate_check(text, text, int) to service_role;

notify pgrst, 'reload schema';
