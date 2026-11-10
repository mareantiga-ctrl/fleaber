-- P2 lote 2: RTB-B-1755-P2-LIVE-MSG
-- BUG: qualquer autenticado lia live_messages de lives ended/active (incl. channel=facebook / nomes OCR).
-- Preserva: seller/staff vê tudo da sua live; chat público fleaber/hub (chat|tip|system) em live activa/ended;
--           hub_live_messages_public inalterado para anon/Hub.
-- production_touched: false · fase4: false

drop policy if exists live_messages_select_scoped on public.live_messages;
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
          or (
            -- Chat público da app/Hub (sem OCR/Facebook PII de ingest)
            lower(trim(coalesce(live_messages.channel, 'fleaber'))) in (
              'fleaber', 'hub'
            )
            and lower(trim(coalesce(live_messages.kind, ''))) in (
              'chat', 'tip', 'system'
            )
            and (
              coalesce(l.is_active, false) = true
              or lower(trim(coalesce(l.status, ''))) in ('live', 'ended')
            )
          )
        )
    )
  );

comment on policy live_messages_select_scoped on public.live_messages is
  'P2-LIVE-MSG: facebook/OCR só seller/staff; fleaber/hub chat|tip|system público em live/ended.';

notify pgrst, 'reload schema';
