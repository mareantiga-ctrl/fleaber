-- P2 lote 4: RTB-B-1755-P2-FOLLOWS-ENUM
-- BUG: policy "Acesso Seguidores" using(true) → enum global follower/following.
-- Preserva: seguir/deixar de seguir (follower_id = auth.uid()); ver se EU sigo X;
--           ver quem me segue (following_id = auth.uid()).
-- production_touched: false · fase4: false

alter table public.follows enable row level security;

drop policy if exists "Acesso Seguidores" on public.follows;
drop policy if exists follows_select_parties on public.follows;
drop policy if exists follows_insert_own on public.follows;
drop policy if exists follows_delete_own on public.follows;
drop policy if exists follows_update_own on public.follows;

create policy follows_select_parties
  on public.follows
  for select
  to authenticated
  using (
    follower_id = auth.uid()
    or following_id = auth.uid()
  );

create policy follows_insert_own
  on public.follows
  for insert
  to authenticated
  with check (
    follower_id = auth.uid()
    and following_id is distinct from auth.uid()
  );

create policy follows_delete_own
  on public.follows
  for delete
  to authenticated
  using (follower_id = auth.uid());

revoke all on table public.follows from anon, public;
grant select, insert, delete on table public.follows to authenticated;

notify pgrst, 'reload schema';
