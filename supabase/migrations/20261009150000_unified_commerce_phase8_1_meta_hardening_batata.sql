-- =============================================================================
-- Phase 8.1 — Meta hardening (staging): poll binding assert, webhook reclaim,
-- Messenger send claim (concurrent idempotency). Non-destructive additive.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Assert page + seller + live + video before Graph poll
-- ---------------------------------------------------------------------------
create or replace function public.batata_meta_assert_poll_binding(
  p_page_id text,
  p_live_id uuid,
  p_meta_live_video_id text,
  p_seller_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_page text := nullif(trim(coalesce(p_page_id, '')), '');
  v_video text := nullif(trim(coalesce(p_meta_live_video_id, '')), '');
  v_conn public.commerce_meta_page_connections%rowtype;
  v_bind public.commerce_meta_live_video_bindings%rowtype;
  v_live public.lives%rowtype;
begin
  perform public.batata_meta_assert_service_caller();

  if v_page is null or p_live_id is null or v_video is null then
    return jsonb_build_object('ok', false, 'error', 'missing_params');
  end if;

  select * into v_conn
  from public.commerce_meta_page_connections c
  where c.page_id = v_page
    and c.revoked_at is null
    and c.ingest_enabled = true
  limit 1;

  if v_conn.id is null then
    return jsonb_build_object('ok', false, 'error', 'page_not_authorized');
  end if;

  if p_seller_id is not null and v_conn.seller_id is distinct from p_seller_id then
    return jsonb_build_object('ok', false, 'error', 'seller_page_mismatch');
  end if;

  select * into v_live from public.lives where id = p_live_id;
  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  if coalesce(v_live.seller_id, v_live.vendedor_id) is distinct from v_conn.seller_id then
    return jsonb_build_object('ok', false, 'error', 'live_seller_mismatch');
  end if;

  select * into v_bind
  from public.commerce_meta_live_video_bindings b
  where b.live_id = p_live_id
    and b.page_id = v_page
    and b.meta_live_video_id = v_video
    and b.revoked_at is null
  limit 1;

  if v_bind.id is null then
    return jsonb_build_object('ok', false, 'error', 'binding_mismatch');
  end if;

  if v_bind.seller_id is distinct from v_conn.seller_id then
    return jsonb_build_object('ok', false, 'error', 'binding_seller_mismatch');
  end if;

  return jsonb_build_object(
    'ok', true,
    'seller_id', v_conn.seller_id,
    'live_id', p_live_id,
    'page_id', v_page,
    'meta_live_video_id', v_video
  );
end;
$$;

revoke all on function public.batata_meta_assert_poll_binding(text, uuid, text, uuid) from public;
grant execute on function public.batata_meta_assert_poll_binding(text, uuid, text, uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- 2) Webhook claim: recoverable statuses can be reclaimed (not permanent dup)
-- ---------------------------------------------------------------------------
create or replace function public.batata_meta_webhook_claim_delivery(
  p_delivery_key text,
  p_page_id text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text := nullif(trim(coalesce(p_delivery_key, '')), '');
  v_page text := nullif(trim(coalesce(p_page_id, '')), '');
  v_seller_id uuid;
  v_live_id uuid;
  v_res jsonb;
  v_post text;
  v_existing public.commerce_meta_webhook_deliveries%rowtype;
  v_reclaimed boolean := false;
begin
  perform public.batata_meta_assert_service_caller();
  if v_key is null or v_page is null then
    return jsonb_build_object('ok', false, 'error', 'missing_delivery_key');
  end if;

  begin
    insert into public.commerce_meta_webhook_deliveries (delivery_key, page_id, payload, status)
    values (v_key, v_page, coalesce(p_payload, '{}'::jsonb), 'claimed');
  exception
    when unique_violation then
      select * into v_existing
      from public.commerce_meta_webhook_deliveries d
      where d.delivery_key = v_key;

      -- Terminal success → duplicate
      if v_existing.status in ('processed', 'duplicate') then
        return jsonb_build_object(
          'ok', true,
          'duplicate', true,
          'delivery_key', v_key,
          'prior_status', v_existing.status
        );
      end if;

      -- In-flight claimed (concurrent or mid-process): only reclaim if stale
      if v_existing.status = 'claimed' then
        if v_existing.created_at > timezone('utc', now()) - interval '30 seconds' then
          return jsonb_build_object(
            'ok', true,
            'duplicate', true,
            'delivery_key', v_key,
            'prior_status', 'claimed',
            'reason', 'inflight'
          );
        end if;
        update public.commerce_meta_webhook_deliveries
        set status = 'claimed',
            payload = coalesce(p_payload, payload),
            result = jsonb_build_object('reclaimed_stale', true),
            processed_at = null,
            page_id = v_page,
            created_at = timezone('utc', now())
        where delivery_key = v_key;
        v_reclaimed := true;
      elsif v_existing.status in ('error', 'skipped', 'rejected') then
        -- Recoverable failures — do not permanently block Meta retries
        update public.commerce_meta_webhook_deliveries
        set status = 'claimed',
            payload = coalesce(p_payload, payload),
            result = '{}'::jsonb,
            processed_at = null,
            page_id = v_page,
            created_at = timezone('utc', now())
        where delivery_key = v_key;
        v_reclaimed := true;
      else
        return jsonb_build_object(
          'ok', true,
          'duplicate', true,
          'delivery_key', v_key,
          'prior_status', v_existing.status
        );
      end if;
  end;

  select c.seller_id into v_seller_id
  from public.commerce_meta_page_connections c
  where c.page_id = v_page
    and c.revoked_at is null
    and c.ingest_enabled = true
  limit 1;

  if v_seller_id is null then
    update public.commerce_meta_webhook_deliveries
    set status = 'rejected',
        result = jsonb_build_object('error', 'page_not_authorized'),
        processed_at = now()
    where delivery_key = v_key;
    return jsonb_build_object('ok', false, 'error', 'page_not_authorized');
  end if;

  v_post := nullif(trim(coalesce(p_payload->>'postId', p_payload->>'post_id', '')), '');
  v_res := public.batata_meta_resolve_live_for_page(v_page, v_post);
  if coalesce((v_res->>'ok')::boolean, false) is not true then
    update public.commerce_meta_webhook_deliveries
    set seller_id = v_seller_id,
        status = 'skipped',
        result = v_res,
        processed_at = now()
    where delivery_key = v_key;
    return jsonb_build_object(
      'ok', true,
      'live_id', null,
      'seller_id', v_seller_id,
      'warning', coalesce(v_res->>'error', 'no_live'),
      'reclaimed', v_reclaimed
    );
  end if;

  v_live_id := (v_res->>'live_id')::uuid;
  update public.commerce_meta_webhook_deliveries
  set seller_id = v_seller_id,
      live_id = v_live_id
  where delivery_key = v_key;

  return jsonb_build_object(
    'ok', true,
    'live_id', v_live_id,
    'seller_id', v_seller_id,
    'reclaimed', v_reclaimed
  );
end;
$$;

revoke all on function public.batata_meta_webhook_claim_delivery(text, text, jsonb) from public;
grant execute on function public.batata_meta_webhook_claim_delivery(text, text, jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- 3) Messenger send claim — concurrent idempotency (no double Private Reply)
-- ---------------------------------------------------------------------------
create table if not exists public.commerce_meta_messenger_send_claims (
  page_id text not null,
  comment_id text not null,
  seller_id uuid not null,
  status text not null default 'claimed',
  attempt_count integer not null default 1,
  last_error text null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (page_id, comment_id),
  constraint commerce_meta_messenger_send_claims_status_chk
    check (status in ('claimed', 'sent', 'failed', 'skipped', 'ambiguous'))
);

comment on table public.commerce_meta_messenger_send_claims is
  'Phase 8.1: one Private Reply attempt per (page, comment). ambiguous = unknown Meta outcome — do not resend.';

revoke all on table public.commerce_meta_messenger_send_claims from public, anon, authenticated;
grant all on table public.commerce_meta_messenger_send_claims to service_role;

create or replace function public.batata_commerce_messenger_claim_send(
  p_seller_id uuid,
  p_page_id text,
  p_comment_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_page text := nullif(trim(coalesce(p_page_id, '')), '');
  v_cmt text := nullif(trim(coalesce(p_comment_id, '')), '');
  v_eval jsonb;
  v_row public.commerce_meta_messenger_send_claims%rowtype;
begin
  perform public.batata_meta_assert_service_caller();
  if p_seller_id is null or v_page is null or v_cmt is null then
    return jsonb_build_object('ok', false, 'eligible', false, 'error', 'missing_params');
  end if;

  v_eval := public.batata_commerce_messenger_evaluate_outbound(
    p_seller_id, v_page, v_cmt, 'private_reply'
  );
  if coalesce((v_eval->>'eligible')::boolean, false) is not true then
    return jsonb_build_object(
      'ok', true,
      'eligible', false,
      'reason', coalesce(v_eval->>'reason', 'not_eligible'),
      'claim', false
    );
  end if;

  begin
    insert into public.commerce_meta_messenger_send_claims (
      page_id, comment_id, seller_id, status
    )
    values (v_page, v_cmt, p_seller_id, 'claimed');
  exception
    when unique_violation then
      select * into v_row
      from public.commerce_meta_messenger_send_claims
      where page_id = v_page and comment_id = v_cmt;

      if v_row.status = 'sent' then
        return jsonb_build_object(
          'ok', true,
          'eligible', true,
          'claim', false,
          'duplicate', true,
          'reason', 'already_sent'
        );
      end if;

      if v_row.status = 'ambiguous' then
        return jsonb_build_object(
          'ok', true,
          'eligible', true,
          'claim', false,
          'duplicate', true,
          'reason', 'ambiguous_prior_send'
        );
      end if;

      if v_row.status = 'claimed' then
        return jsonb_build_object(
          'ok', true,
          'eligible', true,
          'claim', false,
          'duplicate', true,
          'reason', 'inflight'
        );
      end if;

      -- failed / skipped: allow one reclaim for network failure (not free repeat of success)
      if v_row.status in ('failed', 'skipped') then
        update public.commerce_meta_messenger_send_claims
        set status = 'claimed',
            attempt_count = attempt_count + 1,
            last_error = null,
            updated_at = now(),
            seller_id = p_seller_id
        where page_id = v_page and comment_id = v_cmt
          and status in ('failed', 'skipped');
        if not found then
          return jsonb_build_object(
            'ok', true,
            'eligible', true,
            'claim', false,
            'duplicate', true,
            'reason', 'race_lost'
          );
        end if;
        return jsonb_build_object(
          'ok', true,
          'eligible', true,
          'claim', true,
          'reclaimed', true
        );
      end if;

      return jsonb_build_object(
        'ok', true,
        'eligible', true,
        'claim', false,
        'duplicate', true,
        'reason', 'blocked'
      );
  end;

  return jsonb_build_object(
    'ok', true,
    'eligible', true,
    'claim', true
  );
end;
$$;

revoke all on function public.batata_commerce_messenger_claim_send(uuid, text, text) from public;
grant execute on function public.batata_commerce_messenger_claim_send(uuid, text, text)
  to service_role;

create or replace function public.batata_commerce_messenger_finish_send(
  p_page_id text,
  p_comment_id text,
  p_status text,
  p_error text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_page text := nullif(trim(coalesce(p_page_id, '')), '');
  v_cmt text := nullif(trim(coalesce(p_comment_id, '')), '');
  v_status text := lower(trim(coalesce(p_status, '')));
begin
  perform public.batata_meta_assert_service_caller();
  if v_page is null or v_cmt is null then
    return jsonb_build_object('ok', false, 'error', 'missing_params');
  end if;
  if v_status not in ('sent', 'failed', 'skipped', 'ambiguous') then
    return jsonb_build_object('ok', false, 'error', 'invalid_status');
  end if;

  update public.commerce_meta_messenger_send_claims
  set status = v_status,
      last_error = nullif(trim(coalesce(p_error, '')), ''),
      updated_at = timezone('utc', now())
  where page_id = v_page and comment_id = v_cmt;

  return jsonb_build_object('ok', true, 'status', v_status);
end;
$$;

revoke all on function public.batata_commerce_messenger_finish_send(text, text, text, text) from public;
grant execute on function public.batata_commerce_messenger_finish_send(text, text, text, text)
  to service_role;

notify pgrst, 'reload schema';
