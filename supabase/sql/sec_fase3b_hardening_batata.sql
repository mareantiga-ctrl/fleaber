-- =============================================================================
-- FASE 3B — Gorjetas trust boundary + storage privado + guards (BATATA)
-- Staging only. Idempotente. NÃO é consolidação global (continua em F03 docs).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- F01 — tip pending: teto 1–500 € (alinhado à Edge)
-- ---------------------------------------------------------------------------
create or replace function public.batata_create_live_tip_pending(
  p_live_id uuid,
  p_seller_id uuid,
  p_amount numeric,
  p_message text default null,
  p_stripe_session_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer_id uuid := auth.uid();
  v_tip_id uuid;
  v_fee numeric;
  v_seller_amount numeric;
  v_live_seller uuid;
  v_note text;
  v_amount numeric;
begin
  if v_buyer_id is null then
    raise exception 'Tem de iniciar sessão para enviar gorjeta.';
  end if;

  if p_seller_id is null or p_seller_id = v_buyer_id then
    raise exception 'Vendedor inválido para gorjeta.';
  end if;

  v_amount := round(coalesce(p_amount, 0), 2);
  if v_amount < 1 then
    raise exception 'Valor mínimo de gorjeta: 1 €.';
  end if;
  if v_amount > 500 then
    raise exception 'Valor máximo de gorjeta: 500 €.';
  end if;

  if p_live_id is not null then
    select coalesce(seller_id, vendedor_id) into v_live_seller
    from public.lives
    where id = p_live_id;

    if v_live_seller is null then
      raise exception 'Direto não encontrado.';
    end if;

    if v_live_seller <> p_seller_id then
      raise exception 'O vendedor não corresponde a este direto.';
    end if;
  end if;

  v_fee := public.batata_live_tip_processing_fee(v_amount);
  v_seller_amount := public.batata_live_tip_seller_amount(v_amount);
  v_note := nullif(trim(coalesce(p_message, '')), '');

  insert into public.live_tips (
    live_id,
    buyer_id,
    seller_id,
    amount,
    processing_fee,
    seller_amount,
    message,
    payment_source,
    status,
    stripe_session_id
  ) values (
    p_live_id,
    v_buyer_id,
    p_seller_id,
    v_amount,
    v_fee,
    v_seller_amount,
    v_note,
    'stripe',
    'pending',
    nullif(trim(coalesce(p_stripe_session_id, '')), '')
  )
  returning id into v_tip_id;

  return v_tip_id;
end;
$$;

revoke all on function public.batata_create_live_tip_pending(uuid, uuid, numeric, text, text)
  from public, anon;
grant execute on function public.batata_create_live_tip_pending(uuid, uuid, numeric, text, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- F01 — settle: crédito só se Stripe paid cents == tip.amount
-- Drop assinatura antiga (2 args) para impedir bypass sem montante.
-- ---------------------------------------------------------------------------
drop function if exists public.batata_settle_live_tip_from_stripe(uuid, text);

create or replace function public.batata_settle_live_tip_from_stripe(
  p_tip_id uuid,
  p_stripe_session_id text,
  p_paid_amount_cents integer
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tip public.live_tips%rowtype;
  v_note text;
  v_session text;
  v_expected_cents integer;
begin
  if p_tip_id is null then
    return false;
  end if;

  v_session := nullif(trim(coalesce(p_stripe_session_id, '')), '');
  if v_session is null then
    raise exception 'tip_session_required';
  end if;

  if p_paid_amount_cents is null or p_paid_amount_cents < 100 then
    raise exception 'tip_paid_amount_invalid';
  end if;

  select * into v_tip
  from public.live_tips
  where id = p_tip_id
  for update;

  if not found then
    return false;
  end if;

  -- Idempotente: mesma sessão já concluída.
  if v_tip.status = 'completed' then
    if v_tip.stripe_session_id is not null
       and v_tip.stripe_session_id is distinct from v_session then
      raise exception 'tip_already_settled_other_session';
    end if;
    return true;
  end if;

  if v_tip.status <> 'pending' or v_tip.payment_source <> 'stripe' then
    return false;
  end if;

  -- Sessão já ligada a outra Checkout Session → recusar (anti 2 sessions / replay).
  if v_tip.stripe_session_id is not null
     and v_tip.stripe_session_id is distinct from v_session then
    raise exception 'tip_session_mismatch';
  end if;

  v_expected_cents := round(v_tip.amount * 100)::integer;
  if p_paid_amount_cents is distinct from v_expected_cents then
    raise exception 'tip_amount_mismatch: paid=% expected=%',
      p_paid_amount_cents, v_expected_cents;
  end if;

  v_note := coalesce(v_tip.message, 'Gorjeta em direto');

  perform public.batata_ensure_wallet(v_tip.seller_id);
  perform public.batata_ensure_wallet(v_tip.buyer_id);

  if not public.batata_wallet_apply_tip_once(
    v_tip.seller_id,
    v_tip.id,
    v_tip.seller_amount,
    'gorjeta_recebida',
    v_note
  ) then
    return false;
  end if;

  insert into public.wallet_transactions (
    wallet_id,
    amount,
    type,
    description,
    tip_id
  ) values (
    v_tip.buyer_id,
    -round(v_tip.amount, 2),
    'gorjeta_enviada',
    coalesce(nullif(trim(v_note), ''), 'Gorjeta paga com cartão'),
    v_tip.id
  )
  on conflict (wallet_id, tip_id, type) where tip_id is not null do nothing;

  update public.live_tips
  set
    status = 'completed',
    completed_at = now(),
    stripe_session_id = v_session
  where id = v_tip.id;

  return true;
end;
$$;

revoke all on function public.batata_settle_live_tip_from_stripe(uuid, text, integer)
  from public, anon, authenticated;
grant execute on function public.batata_settle_live_tip_from_stripe(uuid, text, integer)
  to service_role;

comment on function public.batata_settle_live_tip_from_stripe(uuid, text, integer) is
  'FASE3B: credita seller_amount só se p_paid_amount_cents == tip.amount*100.';

-- ---------------------------------------------------------------------------
-- F02 — bucket privado para provas/disputas + policies chat_media ownership
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'fleaber_private',
  'fleaber_private',
  false,
  15728640,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic', 'application/pdf']
)
on conflict (id) do update
set
  public = false,
  file_size_limit = excluded.file_size_limit;

do $$
declare
  r record;
begin
  for r in
    select policyname
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and (
        policyname ilike '%fleaber_private%'
        or policyname ilike '%chat_media%'
        or policyname in (
          'Fotos do chat são públicas',
          'Users podem fazer upload de fotos'
        )
        or policyname ilike '%upload de fotos%'
        or policyname ilike '%Fotos do chat%'
      )
  loop
    execute format('drop policy if exists %I on storage.objects', r.policyname);
  end loop;
end $$;

-- chat_media: SELECT público excepto provas/disputas legadas
create policy chat_media_public_select
  on storage.objects
  for select
  using (
    bucket_id = 'chat_media'
    and name not like 'order_proofs/%'
    and name not like 'order_disputes/%'
  );

-- Legado: dono (uid no path) ainda lê provas no bucket público
create policy chat_media_proofs_owner_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'chat_media'
    and (
      name like 'order_proofs/%'
      or name like 'order_disputes/%'
    )
    and auth.uid() is not null
    and position(auth.uid()::text in name) > 0
  );

-- INSERT: ownership por pasta; novos order_proofs/disputes no chat_media PROIBIDOS
create policy chat_media_auth_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'chat_media'
    and auth.uid() is not null
    and name not like 'order_proofs/%'
    and name not like 'order_disputes/%'
    and (
      name like ('product_photos/' || auth.uid()::text || '/%')
      or name like ('profile_photos/' || auth.uid()::text || '/%')
      or name like ('live_item_photos/' || auth.uid()::text || '/%')
      or name like ('live_raffle_prize/' || auth.uid()::text || '/%')
      or name like ('chat_uploads/' || auth.uid()::text || '/%')
    )
  );

create policy chat_media_auth_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'chat_media'
    and auth.uid() is not null
    and (
      name like ('product_photos/' || auth.uid()::text || '/%')
      or name like ('profile_photos/' || auth.uid()::text || '/%')
      or name like ('live_item_photos/' || auth.uid()::text || '/%')
      or name like ('live_raffle_prize/' || auth.uid()::text || '/%')
      or name like ('chat_uploads/' || auth.uid()::text || '/%')
    )
  )
  with check (
    bucket_id = 'chat_media'
    and auth.uid() is not null
    and (
      name like ('product_photos/' || auth.uid()::text || '/%')
      or name like ('profile_photos/' || auth.uid()::text || '/%')
      or name like ('live_item_photos/' || auth.uid()::text || '/%')
      or name like ('live_raffle_prize/' || auth.uid()::text || '/%')
      or name like ('chat_uploads/' || auth.uid()::text || '/%')
    )
  );

create policy chat_media_auth_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'chat_media'
    and auth.uid() is not null
    and (
      name like ('product_photos/' || auth.uid()::text || '/%')
      or name like ('profile_photos/' || auth.uid()::text || '/%')
      or name like ('live_item_photos/' || auth.uid()::text || '/%')
      or name like ('live_raffle_prize/' || auth.uid()::text || '/%')
      or name like ('chat_uploads/' || auth.uid()::text || '/%')
      or (
        (name like 'order_proofs/%' or name like 'order_disputes/%')
        and position(auth.uid()::text in name) > 0
      )
    )
  );

-- fleaber_private: sem anon; path {kind}/{uid}/...
create policy fleaber_private_select_own
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and (
      name like ('order_proofs/' || auth.uid()::text || '/%')
      or name like ('order_disputes/' || auth.uid()::text || '/%')
    )
  );

create policy fleaber_private_insert_own
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and (
      name like ('order_proofs/' || auth.uid()::text || '/%')
      or name like ('order_disputes/' || auth.uid()::text || '/%')
    )
  );

create policy fleaber_private_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and (
      name like ('order_proofs/' || auth.uid()::text || '/%')
      or name like ('order_disputes/' || auth.uid()::text || '/%')
    )
  )
  with check (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and (
      name like ('order_proofs/' || auth.uid()::text || '/%')
      or name like ('order_disputes/' || auth.uid()::text || '/%')
    )
  );

create policy fleaber_private_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and (
      name like ('order_proofs/' || auth.uid()::text || '/%')
      or name like ('order_disputes/' || auth.uid()::text || '/%')
    )
  );

-- Vendedor lê provas do comprador com quem tem encomenda (path order_proofs/{buyer_uid}/…)
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
            and name like ('order_proofs/' || o.buyer_id::text || '/%')
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
        )
      )
    )
  );

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- F05 — antes do nuke: repor stock de orders com claim (evita deriva qty)
-- ---------------------------------------------------------------------------
create or replace function public.staging_restore_stock_before_nuke(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n int := 0;
  r record;
begin
  if p_user_id is null then
    raise exception 'user_id required';
  end if;

  for r in
    select o.id, o.product_id, o.stock_units_applied
    from public.orders o
    where (o.buyer_id = p_user_id or o.seller_id = p_user_id)
      and coalesce(o.stock_units_applied, 0) > 0
      and o.product_id is not null
    for update of o
  loop
    update public.products p
    set
      quantity = coalesce(p.quantity, 0) + r.stock_units_applied,
      is_sold = case
        when coalesce(p.quantity, 0) + r.stock_units_applied > 0 then false
        else p.is_sold
      end
    where p.id = r.product_id;

    update public.orders
    set stock_units_applied = 0
    where id = r.id;

    v_n := v_n + 1;
  end loop;

  return jsonb_build_object('orders_stock_restored', v_n);
end;
$$;

revoke all on function public.staging_restore_stock_before_nuke(uuid)
  from public, anon, authenticated;
grant execute on function public.staging_restore_stock_before_nuke(uuid)
  to service_role;

