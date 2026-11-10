-- =============================================================================
-- BATATA 2026-10-05 — Phase 1 stock correction
-- Product rule (closed): PENDING does NOT block stock — same-item OR cross-item.
-- approval_pending + pending → no hold
-- bag_hold_none + pending → no hold
-- accepted / guaranteed hold → still blocks
-- orders that already block → unchanged (via existing blocked_orders paths)
-- Additive corrective migration. Does NOT edit prior Phase 1 migrations.
-- =============================================================================

create or replace function public.batata_lrr_counts_in_cross_block(
  p_status text,
  p_request_kind text
)
returns boolean
language sql
immutable
as $$
  -- Only a real guaranteed hold (accepted) blocks other listings of the same
  -- product / lineage / ref. Pending of any request_kind is NEVER a stock hold.
  select lower(trim(coalesce(p_status, ''))) = 'accepted';
$$;

comment on function public.batata_lrr_counts_in_cross_block(text, text) is
  'Cross-item stock block: ONLY status=accepted. Pending (approval_pending or bag_hold_none) never blocks. p_request_kind retained for call-site compatibility.';

grant execute on function public.batata_lrr_counts_in_cross_block(text, text)
  to anon, authenticated, service_role;

-- Comment-only refresh on stock RPC (body already uses the helper above).
comment on function public.batata_live_item_stock(uuid) is
  'Stock live: pending (any kind) never holds same-item or cross-item; accepted holds; orders hold paths unchanged.';

notify pgrst, 'reload schema';
