-- ZIP 168 — backfill ended_at em lives já ended (sem alterar status/is_active).
-- Não toca produtos / anúncios Amazon.
begin;

update public.lives
set ended_at = coalesce(went_live_at, created_at, timezone('utc', now()))
where status = 'ended'
  and ended_at is null;

-- Prova: 0 sem ended_at
do $$
declare n int;
begin
  select count(*) into n from public.lives where status = 'ended' and ended_at is null;
  raise notice 'ENDED_WITHOUT_ENDED_AT_AFTER=%', n;
  if n <> 0 then
    raise exception 'ZIP168 backfill incomplete: % rows', n;
  end if;
end $$;

commit;
