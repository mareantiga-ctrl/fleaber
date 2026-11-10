# meta-webhook (Phase 8)

Meta Page webhook receiver for **feed** comment events. Verification uses `META_WEBHOOK_VERIFY_TOKEN`; POST bodies use `X-Hub-Signature-256` with `META_APP_SECRET` or `FACEBOOK_APP_SECRET`.

## Dashboard (João — later)

- Callback URL: `https://<STAGING_PROJECT_REF>.supabase.co/functions/v1/meta-webhook`
- Verify token: value of `META_WEBHOOK_VERIFY_TOKEN` in Supabase Edge secrets
- Object: **Page**
- Field: **feed** (comments on Page posts / live video posts when Meta delivers them on feed)

## Behaviour

1. Validates signature (403 if invalid).
2. Idempotent delivery log via `batata_meta_webhook_claim_delivery`.
3. Resolves Fleaber `live_id` from `commerce_meta_live_video_bindings` (post id / page).
4. Parses comment with shared PS Face parser → `batata_ingest_ocr_reservation_v2` with `p_event_channel=graph` and `p_meta_page_id`.

Does **not** call Graph API or send Messenger messages.

## Limitations (documented)

- Live comment latency: Meta often recommends polling/SSE for active lives; webhook `feed` is reconciliation / supplement.
- Without linked Page + live binding + secrets, events are logged as skipped — not a fake success.
