-- Fix Home feed: lives RLS EXISTS on profiles fails because
-- profiles_select_auth only allows id = auth.uid().
-- Use batata_profile_is_hub_published (SECURITY DEFINER) instead.
-- BATATA: não abre profiles; só boolean hub_published.

create or replace function public.batata_profile_is_hub_published(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select p.hub_published from public.profiles p where p.id = p_id),
    false
  );
$$;

revoke all on function public.batata_profile_is_hub_published(uuid) from public;
grant execute on function public.batata_profile_is_hub_published(uuid)
  to anon, authenticated, service_role;

drop policy if exists "lives_select_feed_or_owner" on public.lives;
create policy "lives_select_feed_or_owner"
  on public.lives
  for select
  to anon, authenticated
  using (
    auth.uid() = seller_id
    or auth.uid() = vendedor_id
    or (
      lower(trim(coalesce(status, ''))) = 'live'
      and coalesce(is_active, false) = true
      and public.batata_profile_is_hub_published(
        coalesce(seller_id, vendedor_id)
      )
    )
    or (
      lower(trim(coalesce(status, ''))) = 'ended'
      and public.batata_profile_is_hub_published(
        coalesce(seller_id, vendedor_id)
      )
    )
    or (
      lower(trim(coalesce(status, ''))) = 'scheduled'
      and auth.uid() = coalesce(seller_id, vendedor_id)
    )
  );
