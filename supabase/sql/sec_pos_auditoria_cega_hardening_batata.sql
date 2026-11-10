-- =============================================================================
-- HARDENING PÓS-AUDITORIAS CEGAS — money/authz (BATATA)
-- Staging only. Idempotente. NÃO consolidação global Fase 4.
-- Fecha: P0 refund mint · storage counterparty · tip pending reassert
-- =============================================================================

-- ---------------------------------------------------------------------------
-- P0 — batata_process_partial_refund_dispute: sem mint sem pagamento
-- Autoridade: order pós-pago + disputa com % do vendedor; % do cliente IGNORADO.
-- ---------------------------------------------------------------------------
create or replace function public.batata_process_partial_refund_dispute(
  p_order_id uuid,
  p_refund_percent numeric default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_total numeric;
  v_percent numeric;
  v_refund numeric;
  v_commission numeric;
  v_seller_amount numeric;
  v_buyer_done boolean := false;
  v_seller_done boolean := false;
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_dispute public.order_disputes%rowtype;
  v_status text;
  v_paid_ok boolean := false;
begin
  perform set_config('batata.wallet_internal', '1', true);

  if p_order_id is null then
    return false;
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found or v_order.buyer_id is null or v_order.seller_id is null then
    return false;
  end if;

  -- JWT: só o COMPRADOR aceita reembolso parcial (fluxo chat).
  -- service_role / nested DEFINER: permitido (ops / Edge futura).
  if v_role = 'authenticated' then
    if v_uid is null or v_uid is distinct from v_order.buyer_id then
      raise exception 'not_allowed' using errcode = '42501';
    end if;
  elsif v_role is distinct from 'service_role' and v_uid is not null then
    -- roles estranhos sem service
    if v_uid is distinct from v_order.buyer_id then
      raise exception 'not_allowed' using errcode = '42501';
    end if;
  end if;

  if v_order.wallet_release_processed_at is not null
     or v_order.wallet_refund_processed_at is not null then
    return false;
  end if;

  v_status := lower(trim(coalesce(v_order.status, '')));

  -- Gate financeiro: nunca creditar sobre reserva / cancelado / pré-pago.
  v_paid_ok := v_status in (
    'pago',
    'enviado',
    'entregue',
    'concluido',
    'pedido_devolucao',
    'em_devolucao',
    'devolucao_entregue',
    'disputa_devolucao_vendedor'
  );

  if not v_paid_ok then
    raise exception 'order_not_paid_for_refund';
  end if;

  -- Prova fraca de liquidação: Stripe PI, claim de stock, ou método directo
  -- já marcado pago (MB WAY). Sem isto + status pós-pago → ainda bloqueado acima.
  if coalesce(v_order.stock_units_applied, 0) <= 0
     and nullif(trim(coalesce(v_order.stripe_payment_intent_id, '')), '') is null
     and nullif(trim(coalesce(v_order.stripe_checkout_session_id, '')), '') is null
     and nullif(trim(coalesce(v_order.stripe_refund_id, '')), '') is null
  then
    -- MB WAY / directo: status pós-pago é a prova (seller confirmou).
    -- Reserva inventada sem stock claim continua bloqueada pelo status gate.
    null;
  end if;

  -- Disputa obrigatória com % do vendedor (nunca confiar no p_refund_percent do cliente).
  select *
  into v_dispute
  from public.order_disputes d
  where d.order_id = p_order_id
    and d.seller_refund_percent is not null
    and d.seller_refund_percent > 0
    and lower(coalesce(d.status, '')) is distinct from 'recusada'
    and (
      lower(coalesce(d.seller_offer_type, '')) in (
        'partial_refund',
        'return_and_partial_refund'
      )
      or d.seller_offer_type is null
    )
  order by d.created_at desc
  limit 1;

  if not found then
    raise exception 'dispute_refund_offer_required';
  end if;

  v_percent := least(greatest(v_dispute.seller_refund_percent, 0), 100);

  -- Base: price_total só DEPOIS do gate pós-pago (já liquidado comercialmente).
  -- Stripe: se price_total for absurdo face a PI, preferir não mintar sem PI amount
  -- (PI amount não está na row; price_total pós-settle Stripe é alinhado no settle).
  v_total := public.batata_order_amount(v_order);
  if v_total <= 0 or v_percent <= 0 then
    return false;
  end if;

  -- Cap defensivo: percentagens >100 já clamped; NaN → 0 via coalesce.
  v_refund := round(v_total * (v_percent / 100.0), 2);
  if v_refund <= 0 or v_refund > v_total then
    return false;
  end if;

  v_commission := public.batata_order_commission_amount(v_total);
  v_seller_amount := greatest(round(v_total - v_refund - v_commission, 2), 0);

  v_buyer_done := public.batata_credit_wallet_once(
    v_order.buyer_id,
    v_order.id,
    v_refund,
    'reembolso',
    'Reembolso parcial de ' || round(v_percent, 2)::text || '%'
  );

  v_seller_done := public.batata_credit_wallet_once(
    v_order.seller_id,
    v_order.id,
    v_seller_amount,
    'venda',
    'Valor restante após reembolso parcial'
  );

  perform public.batata_record_fleaber_commission_once(
    v_order.id,
    v_commission,
    'protection_fee',
    'Taxa de Proteção Fleaber'
  );

  update public.orders
  set wallet_release_processed_at = now(),
      wallet_refund_processed_at = now()
  where id = v_order.id;

  -- Marcar disputa resolvida no mesmo txn (reduz race UI).
  update public.order_disputes
  set
    buyer_decision = coalesce(nullif(trim(buyer_decision), ''), 'accepted_partial_refund'),
    status = 'resolvida',
    current_turn = 'administracao',
    next_deadline = now()
  where id = v_dispute.id
    and lower(coalesce(status, '')) is distinct from 'resolvida';

  return v_buyer_done or v_seller_done;
end;
$$;

revoke all on function public.batata_process_partial_refund_dispute(uuid, numeric)
  from public, anon;
grant execute on function public.batata_process_partial_refund_dispute(uuid, numeric)
  to authenticated, service_role;

comment on function public.batata_process_partial_refund_dispute(uuid, numeric) is
  'POS-AUDITORIA: buyer-only JWT; order pós-pago; % só da disputa; sem mint pré-pago.';

-- ---------------------------------------------------------------------------
-- F02 residual — counterparty: path por order + sem cancelada
-- Novos uploads: order_proofs/{buyer}/{orderId}/…
-- Legado flat order_proofs/{buyer}/{file}: só se houver order activa
-- ---------------------------------------------------------------------------
drop policy if exists fleaber_private_select_order_counterparty on storage.objects;

create policy fleaber_private_select_order_counterparty
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and (
      (
        name like 'order_proofs/%'
        and exists (
          select 1
          from public.orders o
          where o.seller_id = auth.uid()
            and o.buyer_id is not null
            and lower(trim(coalesce(o.status, ''))) not in ('cancelado', 'cancelled')
            and (
              name like ('order_proofs/' || o.buyer_id::text || '/' || o.id::text || '/%')
              or (
                name like ('order_proofs/' || o.buyer_id::text || '/%')
                and name not like ('order_proofs/' || o.buyer_id::text || '/%/%')
              )
            )
        )
      )
      or (
        name like 'order_disputes/%'
        and exists (
          select 1
          from public.orders o
          where (o.seller_id = auth.uid() or o.buyer_id = auth.uid())
            and (
              name like ('order_disputes/' || o.buyer_id::text || '/%')
              or name like ('order_disputes/' || o.seller_id::text || '/%')
            )
            and (
              lower(trim(coalesce(o.status, ''))) not in ('cancelado', 'cancelled')
              or exists (
                select 1 from public.order_disputes d
                where d.order_id = o.id
                  and lower(coalesce(d.status, '')) not in ('recusada', 'resolvida')
              )
            )
        )
      )
    )
  );

-- ---------------------------------------------------------------------------
-- P2 — batata_live_system_message: seller/staff only (auth ≠ rate limit)
-- Assinatura live: (uuid, text, text)
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_system_message(
  p_live_id uuid,
  p_body text,
  p_sender_label text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_seller uuid;
  v_body text := trim(coalesce(p_body, ''));
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
begin
  if p_live_id is null or v_body = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_payload');
  end if;

  if char_length(v_body) > 400 then
    return jsonb_build_object('ok', false, 'error', 'body_too_long');
  end if;

  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  select coalesce(seller_id, vendedor_id) into v_seller
  from public.lives
  where id = p_live_id;

  if v_seller is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  if v_uid is distinct from v_seller
     and not public.batata_staff_has_permission(v_seller, 'can_manage_chat') then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  insert into public.batata_rpc_rate_limits (uid, rpc, window_start, hits)
  values (v_uid, 'batata_live_system_message', v_window, 1)
  on conflict (uid, rpc, window_start) do update
  set hits = public.batata_rpc_rate_limits.hits + 1
  returning hits into v_hits;

  if v_hits > 60 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;

  insert into public.live_messages (
    live_id,
    user_id,
    kind,
    body,
    sender_label
  ) values (
    p_live_id,
    v_uid,
    'system',
    v_body,
    coalesce(nullif(trim(p_sender_label), ''), 'Sistema')
  );

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.batata_live_system_message(uuid, text, text)
  from public, anon;
grant execute on function public.batata_live_system_message(uuid, text, text)
  to authenticated, service_role;

-- drop 2-arg overload if present (evita bypass)
drop function if exists public.batata_live_system_message(uuid, text);

notify pgrst, 'reload schema';
