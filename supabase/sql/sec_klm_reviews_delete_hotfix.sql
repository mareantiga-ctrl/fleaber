-- Hotfix: reviews DELETE deve falhar com erro (não 200 vazio)
drop policy if exists "reviews_delete_own" on public.reviews;
drop policy if exists reviews_delete_own_attempt on public.reviews;

create policy reviews_delete_own_attempt
  on public.reviews
  for delete
  to authenticated
  using (
    buyer_id = auth.uid()
    or target_id = auth.uid()
    or public.batata_is_admin()
  );

create or replace function public.batata_reviews_guard_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if v_role = 'authenticated' and v_uid is not null then
    raise exception 'review_delete_forbidden' using errcode = '42501';
  end if;
  return OLD;
end;
$fn$;

drop trigger if exists trg_batata_reviews_guard_delete on public.reviews;
create trigger trg_batata_reviews_guard_delete
  before delete on public.reviews
  for each row
  execute function public.batata_reviews_guard_delete();

notify pgrst, 'reload schema';
