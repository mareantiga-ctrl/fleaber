-- =============================================================================
-- BATATA 2026-10-05 — Phase 2: neutralize UNSAFE backfill from 20261005150600 §4
--
-- Independent review: promoting pending+guaranteed(+snapshots) → accepted is NOT
-- provably safe:
-- 1) WHERE is not exclusive to batata_reserve_with_policy (buyer/service INSERT can
--    stamp request_kind/ttl/expires; pre-GUC guard only forced status=pending).
-- 2) Hybrid rows never blocked stock; promotion invents a historical hold.
-- 3) expires_at in the past + accepted → guaranteed expiry cron → trust failure
--    for a hold the buyer never actually had as accepted.
--
-- This migration does NOT invent active guarantees.
-- It neutralizes rows marked by the prior repair and any remaining hybrids
-- matching the same shape, without trust/payment invention.
-- Additive. Does NOT edit 20261005150600. Staging only. Production unchanged.
-- =============================================================================

-- Allow explicit neutralization reasons (notes keep full audit trail).
alter table public.live_reservation_requests
  drop constraint if exists live_reservation_requests_expiry_reason_chk;

alter table public.live_reservation_requests
  add constraint live_reservation_requests_expiry_reason_chk
  check (
    expiry_reason is null
    or expiry_reason in (
      'pending_ttl_expired',
      'guaranteed_hold_expired_unpaid',
      'buyer_abandonment',
      'stock_unavailable',
      'seller_cancelled',
      'buyer_cancelled',
      'system_error',
      'payment_processing',
      'payment_provider_technical_failure',
      'superseded_by_policy',
      'identity_insufficient_closed',
      'backfill_safety_neutralized',
      'hybrid_guaranteed_pending_neutralized'
    )
  );

-- A) Rows previously promoted by repaired_guaranteed_status → leave accepted
--    (stock + expiry/trust surface). Revert to expired terminal; keep kind/notes.
update public.live_reservation_requests
set
  status = 'expired',
  expiry_reason = case
    when coalesce(nullif(trim(expiry_reason), ''), '') = ''
      then 'backfill_safety_neutralized'
    when expiry_reason in (
      'backfill_safety_neutralized',
      'hybrid_guaranteed_pending_neutralized'
    ) then expiry_reason
    else expiry_reason
  end,
  notes = trim(both ' |' from coalesce(notes, '')
    || ' | backfill_repaired_guaranteed_status_reverted'),
  updated_at = timezone('utc', now())
where notes ilike '%repaired_guaranteed_status%'
  and notes not ilike '%backfill_repaired_guaranteed_status_reverted%'
  and status = 'accepted'
  and coalesce(request_kind, '') = 'guaranteed';

-- B) Remaining hybrids that still match the UNSAFE WHERE shape (pending) —
--    never promote; expire so a re-run of the old UPDATE cannot invent holds.
update public.live_reservation_requests
set
  status = 'expired',
  expiry_reason = coalesce(
    nullif(trim(expiry_reason), ''),
    'hybrid_guaranteed_pending_neutralized'
  ),
  notes = trim(both ' |' from coalesce(notes, '')
    || ' | hybrid_guaranteed_pending_neutralized'),
  updated_at = timezone('utc', now())
where status = 'pending'
  and coalesce(request_kind, '') = 'guaranteed'
  and ttl_seconds_snapshot is not null
  and expires_at is not null;

notify pgrst, 'reload schema';
