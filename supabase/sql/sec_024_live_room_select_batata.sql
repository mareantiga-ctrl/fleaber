-- SEC-024 — live_messages / live_viewers: SELECT já não é using(true)
-- BATATA: chat do directo activo/ended + dono/staff; viewers só próprio ou dono/staff.
-- Contagem de espectadores continua via batata_live_viewer_ping (DEFINER).
-- Hub anon: hub_live_messages_public (inalterado).

-- =============================================================================
-- live_messages SELECT
-- =============================================================================

drop policy if exists "live_messages_select_auth" on public.live_messages;
drop policy if exists live_messages_select_auth on public.live_messages;

create policy live_messages_select_scoped
  on public.live_messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.lives l
      where l.id = live_messages.live_id
        and (
          coalesce(l.seller_id, l.vendedor_id) = auth.uid()
          or public.batata_staff_has_permission(
            coalesce(l.seller_id, l.vendedor_id),
            'can_manage_chat'
          )
          or coalesce(l.is_active, false) = true
          or lower(trim(coalesce(l.status, ''))) in ('live', 'ended')
        )
    )
  );

-- Anon: sem SELECT na tabela (Hub usa view). Reforço.
revoke all on table public.live_messages from anon;
grant select on table public.live_messages to authenticated;
grant select, insert on table public.live_messages to service_role;

-- =============================================================================
-- live_viewers SELECT — sem dump de user_ids de todas as lives
-- =============================================================================

drop policy if exists "live_viewers_select_auth" on public.live_viewers;
drop policy if exists live_viewers_select_auth on public.live_viewers;

create policy live_viewers_select_scoped
  on public.live_viewers
  for select
  to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.lives l
      where l.id = live_viewers.live_id
        and (
          coalesce(l.seller_id, l.vendedor_id) = auth.uid()
          or public.batata_staff_has_permission(
            coalesce(l.seller_id, l.vendedor_id),
            'can_view_live_dashboard'
          )
        )
    )
  );

-- Upsert self (heartbeat via RPC DEFINER também escreve; policy para updates directos)
drop policy if exists "live_viewers_upsert_self" on public.live_viewers;
drop policy if exists live_viewers_upsert_self on public.live_viewers;

create policy live_viewers_upsert_self
  on public.live_viewers
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

revoke all on table public.live_viewers from anon;
grant select on table public.live_viewers to authenticated;
grant select, insert, update, delete on table public.live_viewers to service_role;

notify pgrst, 'reload schema';
