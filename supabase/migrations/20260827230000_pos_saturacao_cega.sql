-- =============================================================================
-- HARDENING PÓS-AUDITORIA CEGA DE SATURAÇÃO (staging only)
-- Fecha classe P0: valores JWT no INSERT tornam-se autoridade financeira/stock.
-- NÃO é Fase 4. NÃO tocar produção.
-- Idempotente. Aplicar: npx supabase db query --linked -f este ficheiro
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0) product_offer_id (liga order a proposta autoritativa)
-- ---------------------------------------------------------------------------
alter table public.orders
  add column if not exists product_offer_id uuid
  references public.product_offers(id) on delete set null;

create index if not exists orders_product_offer_idx
  on public.orders (product_offer_id)
  where product_offer_id is not null;

-- ---------------------------------------------------------------------------
-- 1) payment_method — allowlist off-platform explícita (fail-closed)
-- ---------------------------------------------------------------------------
create or replace function public.batata_normalize_payment_method(p_method text)
returns text
language sql
immutable
as $$
  select lower(trim(regexp_replace(coalesce(p_method, ''), '\s+', ' ', 'g')));
$$;

create or replace function public.batata_is_off_platform_payment(p_method text)
returns boolean
language sql
immutable
as $$
  -- Allowlist EXACTA (LOTE FINAL). Sem like '%mb way%' solto.
  -- Vazio / whitespace / typo inventado = false (fail-closed → plataforma).
  select public.batata_normalize_payment_method(p_method) in (
    'mb way',
    'mb_way',
    'mb-way',
    'mbway',
    'transferencia',
    'transferência',
    'transfer',
    'transf',
    'pagamento directo',
    'pagamento direto',
    'pagamento_directo',
    'pagamento_direto',
    'directo',
    'direto',
    'entrega em mao',
    'entrega em mão',
    'em mao',
    'em mão',
    'levantamento',
    'combinado',
    'combinada',
    'pagamento direto ao vendedor (mb way/transf)',
    'pagamento directo ao vendedor (mb way/transf)'
  );
$$;

create or replace function public.batata_is_platform_payment(p_method text)
returns boolean
language sql
immutable
as $$
  -- Tudo o que NÃO é off-platform allowlist = plataforma (inclui '' / ' ' / desconhecido).
  -- Seller→pago sem captura fica bloqueado.
  select not public.batata_is_off_platform_payment(p_method);
$$;

revoke all on function public.batata_normalize_payment_method(text) from public, anon;
revoke all on function public.batata_is_off_platform_payment(text) from public, anon;
revoke all on function public.batata_is_platform_payment(text) from public, anon;
grant execute on function public.batata_normalize_payment_method(text)
  to authenticated, service_role;
grant execute on function public.batata_is_off_platform_payment(text)
  to authenticated, service_role;
grant execute on function public.batata_is_platform_payment(text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) P0 — selar contrato: JWT NUNCA input; proposta só via product_offers aceite
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_seal_contract()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_jwt boolean := (v_role = 'authenticated' and v_uid is not null);
  v_unit_cents int := 0;
  v_li numeric;
  v_prod numeric;
  v_offer public.product_offers%rowtype;
  v_auth_qty int;
  v_res_qty int := 0;
begin
  -- JWT: descartar qualquer contract_* / spoof de oferta no payload.
  if v_jwt then
    NEW.contract_unit_cents := null;
    NEW.contract_qty := null;
  elsif NEW.contract_unit_cents is not null and NEW.contract_unit_cents > 0 then
    -- service_role / backfill interno: respeitar selo já escrito pelo servidor.
    if NEW.contract_qty is null or NEW.contract_qty < 1 then
      NEW.contract_qty := greatest(coalesce(NEW.quantity, 1), 1);
    end if;
    NEW.quantity := NEW.contract_qty;
    return NEW;
  end if;

  -- Prémio rifa: itens 0 (só portes no checkout).
  if NEW.live_raffle_id is not null
     and lower(trim(coalesce(NEW.status, ''))) = 'premio_rifa' then
    NEW.contract_unit_cents := 0;
    NEW.contract_qty := 1;
    NEW.quantity := 1;
    return NEW;
  end if;

  -- Quantidade canónica = quantity legitimamente pedida (depois validada).
  v_auth_qty := greatest(coalesce(NEW.quantity, 1), 1);
  if v_auth_qty > 99 then
    raise exception 'invalid_order_quantity' using errcode = '23514';
  end if;

  -- Live/bag: qty não pode exceder reserva aceite do buyer neste live_item.
  if v_jwt
     and NEW.live_item_id is not null
     and NEW.buyer_id is not null then
    select coalesce(sum(r.requested_qty), 0)::int into v_res_qty
    from public.live_reservation_requests r
    where r.live_item_id = NEW.live_item_id
      and r.buyer_id = NEW.buyer_id
      and r.status in ('accepted', 'converted');
    if v_res_qty > 0 and v_auth_qty > v_res_qty then
      raise exception 'order_quantity_exceeds_reservation'
        using errcode = '23514';
    end if;
  end if;

  -- Preço catálogo / live item (autoridade de mercado).
  if NEW.live_item_id is not null then
    select li.price into v_li
    from public.live_items li
    where li.id = NEW.live_item_id;
    if v_li is not null and v_li > 0 then
      v_unit_cents := greatest(1, round(v_li * 100)::int);
    end if;
  end if;

  if v_unit_cents <= 0 and NEW.product_id is not null then
    select p.price into v_prod
    from public.products p
    where p.id = NEW.product_id;
    if v_prod is not null and v_prod > 0 then
      v_unit_cents := greatest(1, round(v_prod * 100)::int);
    end if;
  end if;

  -- Proposta: SÓ entidade product_offers aceite + partes correctas.
  -- NÃO usar payment_method LIKE '%proposta%' nem price_total do cliente.
  v_offer := null;
  if NEW.product_offer_id is not null then
    select * into v_offer
    from public.product_offers po
    where po.id = NEW.product_offer_id;
  elsif NEW.product_id is not null and NEW.buyer_id is not null then
    select * into v_offer
    from public.product_offers po
    where po.product_id = NEW.product_id
      and po.buyer_id = NEW.buyer_id
      and (NEW.seller_id is null or po.seller_id = NEW.seller_id)
      and lower(trim(coalesce(po.status, ''))) = 'accepted'
      and (po.expires_at is null or po.expires_at > now())
    order by coalesce(po.responded_at, po.created_at) desc
    limit 1;
  end if;

  if v_offer.id is not null then
    if lower(trim(coalesce(v_offer.status, ''))) is distinct from 'accepted'
       or v_offer.product_id is distinct from NEW.product_id
       or v_offer.buyer_id is distinct from NEW.buyer_id
       or (NEW.seller_id is not null and v_offer.seller_id is distinct from NEW.seller_id)
       or (v_offer.expires_at is not null and v_offer.expires_at <= now())
       or coalesce(v_offer.amount, 0) <= 0
       or v_offer.responded_at is null then
      -- Oferta inválida / spoof → ignorar; manter catálogo.
      NEW.product_offer_id := null;
    else
      NEW.product_offer_id := v_offer.id;
      v_unit_cents := greatest(1, round(v_offer.amount * 100)::int);
    end if;
  else
    NEW.product_offer_id := null;
  end if;

  if v_unit_cents <= 0 then
    raise exception 'order_contract_price_missing' using errcode = '23514';
  end if;

  NEW.contract_unit_cents := v_unit_cents;
  NEW.contract_qty := v_auth_qty;
  NEW.quantity := v_auth_qty;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_seal_contract on public.orders;
create trigger trg_batata_orders_seal_contract
  before insert on public.orders
  for each row
  execute function public.batata_orders_seal_contract();

comment on function public.batata_orders_seal_contract() is
  'SAT 2026-08-27: contract_* OUTPUT do servidor; JWT input ignorado; proposta só product_offers aceite.';

-- ---------------------------------------------------------------------------
-- 3) Flags internos + money cols — INSERT JWT força defaults seguros
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_money_cols()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    if lower(trim(coalesce(NEW.status, ''))) in (
      'pago', 'enviado', 'entregue', 'concluido', 'devolvida',
      'em_devolucao', 'devolucao_entregue', 'disputa_devolucao_vendedor'
    ) then
      NEW.status := 'reserva_pendente';
    end if;
    -- Inventário completo de autoridade interna (nunca JWT declara "já feito")
    NEW.stripe_checkout_session_id := null;
    NEW.stripe_payment_intent_id := null;
    NEW.stripe_refund_id := null;
    NEW.stripe_refunded_at := null;
    NEW.amount_paid_cents := null;
    NEW.stock_units_applied := null;
    NEW.wallet_release_processed_at := null;
    NEW.wallet_refund_processed_at := null;
    NEW.auto_feedback_processed_at := null;
    NEW.completed_at := null;
    NEW.returned_at := null;
    -- contract_* limpos aqui também (selo corre a seguir/antes conforme ordem;
    -- seal já limpa; reforço fail-closed)
    return NEW;
  end if;

  if NEW.buyer_id is distinct from OLD.buyer_id then
    NEW.buyer_id := OLD.buyer_id;
  end if;
  if NEW.seller_id is distinct from OLD.seller_id then
    NEW.seller_id := OLD.seller_id;
  end if;
  if NEW.product_id is distinct from OLD.product_id then
    NEW.product_id := OLD.product_id;
  end if;
  if NEW.stripe_checkout_session_id is distinct from OLD.stripe_checkout_session_id then
    NEW.stripe_checkout_session_id := OLD.stripe_checkout_session_id;
  end if;
  if NEW.stripe_payment_intent_id is distinct from OLD.stripe_payment_intent_id then
    NEW.stripe_payment_intent_id := OLD.stripe_payment_intent_id;
  end if;
  if NEW.stripe_refund_id is distinct from OLD.stripe_refund_id then
    NEW.stripe_refund_id := OLD.stripe_refund_id;
  end if;
  if NEW.stripe_refunded_at is distinct from OLD.stripe_refunded_at then
    NEW.stripe_refunded_at := OLD.stripe_refunded_at;
  end if;
  if NEW.amount_paid_cents is distinct from OLD.amount_paid_cents then
    NEW.amount_paid_cents := OLD.amount_paid_cents;
  end if;
  -- Flags internos: JWT não fabrica. Triggers internos (stock/wallet/jobs)
  -- marcam batata.allow_internal_order_cols=1 na mesma transacção.
  if coalesce(current_setting('batata.allow_internal_order_cols', true), '')
       is distinct from '1' then
    if NEW.stock_units_applied is distinct from OLD.stock_units_applied then
      NEW.stock_units_applied := OLD.stock_units_applied;
    end if;
    if NEW.wallet_release_processed_at is distinct from OLD.wallet_release_processed_at then
      NEW.wallet_release_processed_at := OLD.wallet_release_processed_at;
    end if;
    if NEW.wallet_refund_processed_at is distinct from OLD.wallet_refund_processed_at then
      NEW.wallet_refund_processed_at := OLD.wallet_refund_processed_at;
    end if;
    if NEW.auto_feedback_processed_at is distinct from OLD.auto_feedback_processed_at then
      NEW.auto_feedback_processed_at := OLD.auto_feedback_processed_at;
    end if;
    -- completed_at: o trigger batata_set_order_completed_at escreve no BEFORE;
    -- permitir carimbo legítimo ao entrar em concluido.
    if NEW.completed_at is distinct from OLD.completed_at then
      if not (
        lower(trim(coalesce(NEW.status, ''))) = 'concluido'
        and OLD.completed_at is null
        and NEW.completed_at is not null
      ) then
        NEW.completed_at := OLD.completed_at;
      end if;
    end if;
    if NEW.returned_at is distinct from OLD.returned_at then
      NEW.returned_at := OLD.returned_at;
    end if;
  end if;
  if NEW.live_raffle_id is distinct from OLD.live_raffle_id then
    NEW.live_raffle_id := OLD.live_raffle_id;
  end if;
  if NEW.product_offer_id is distinct from OLD.product_offer_id then
    NEW.product_offer_id := OLD.product_offer_id;
  end if;

  if NEW.price_total is distinct from OLD.price_total then
    NEW.price_total := OLD.price_total;
  end if;
  if NEW.contract_unit_cents is distinct from OLD.contract_unit_cents then
    NEW.contract_unit_cents := OLD.contract_unit_cents;
  end if;
  if NEW.contract_qty is distinct from OLD.contract_qty then
    NEW.contract_qty := OLD.contract_qty;
  end if;
  if NEW.quantity is distinct from OLD.quantity then
    NEW.quantity := OLD.quantity;
  end if;
  if NEW.payment_method is distinct from OLD.payment_method then
    NEW.payment_method := OLD.payment_method;
  end if;

  return NEW;
end;
$fn$;

comment on function public.batata_orders_guard_money_cols() is
  'SAT: INSERT JWT limpa flags internos; UPDATE JWT imutável em money/stock/stripe/wallet/contrato.';

-- ---------------------------------------------------------------------------
-- 4) Máquina de estados — plataforma sem captura não chega a pago/logística
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_paid_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_old text;
  v_new text;
  v_is_buyer boolean;
  v_is_seller boolean;
  v_post_pay boolean;
  v_has_dispute boolean := false;
  v_released boolean := false;
  v_captured boolean := false;
  v_platform boolean := false;
  v_pm text;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  v_new := lower(trim(coalesce(NEW.status, '')));
  v_is_buyer := NEW.buyer_id is not null and NEW.buyer_id = v_uid;
  v_is_seller := (NEW.seller_id is not null and NEW.seller_id = v_uid);

  if TG_OP = 'INSERT' then
    if v_is_buyer and v_new in (
      'pago', 'concluido', 'devolvida', 'enviado', 'entregue', 'premio_rifa',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue'
    ) then
      NEW.status := 'reserva_pendente';
    end if;
    return NEW;
  end if;

  v_old := lower(trim(coalesce(OLD.status, '')));
  if v_new is not distinct from v_old then
    return NEW;
  end if;

  v_pm := coalesce(OLD.payment_method, NEW.payment_method);
  v_platform := public.batata_is_platform_payment(v_pm);
  v_captured :=
    coalesce(OLD.amount_paid_cents, 0) > 0
    or coalesce(OLD.stripe_payment_intent_id, '') <> '';

  v_released := OLD.wallet_release_processed_at is not null
    or NEW.wallet_release_processed_at is not null;

  v_post_pay := v_old in (
    'pago', 'enviado', 'entregue', 'concluido', 'premio_rifa',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor', 'devolvida'
  );

  if v_post_pay and v_new in ('cancelado', 'cancelled') then
    NEW.status := OLD.status;
    return NEW;
  end if;

  -- Plataforma: estados que pressupõem pagamento exigem captura.
  if v_platform and not v_captured then
    if v_new in (
      'pago', 'enviado', 'entregue', 'concluido',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor', 'devolvida'
    ) then
      NEW.status := OLD.status;
      return NEW;
    end if;
  end if;

  -- ---- Comprador ----
  if v_is_buyer and not v_is_seller then
    if v_new = 'pago' and v_old is distinct from 'premio_rifa' then
      NEW.status := OLD.status;
      return NEW;
    end if;
    if v_new = 'enviado' then
      NEW.status := OLD.status;
      return NEW;
    end if;
    if v_new = 'devolvida' then
      NEW.status := OLD.status;
      return NEW;
    end if;

    if v_released and v_new in (
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor'
    ) then
      NEW.status := OLD.status;
      return NEW;
    end if;

    if v_new = 'pedido_devolucao' then
      if v_old not in ('concluido', 'entregue') then
        NEW.status := OLD.status;
        return NEW;
      end if;
      select exists(
        select 1 from public.order_disputes d
        where d.order_id = NEW.id
          and d.buyer_id = v_uid
          and lower(coalesce(d.status, '')) is distinct from 'recusada'
      ) into v_has_dispute;
      if not v_has_dispute then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_post_pay and v_new in (
      'reserva_pendente', 'reservado', 'pendente', 'aguarda_confirmacao'
    ) then
      NEW.status := OLD.status;
      return NEW;
    end if;

    if v_new = 'concluido' then
      if v_old not in (
        'enviado', 'entregue', 'pago', 'pedido_devolucao',
        'em_devolucao', 'disputa_devolucao_vendedor', 'devolucao_entregue'
      ) then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;
  end if;

  -- ---- Vendedor ----
  if v_is_seller then
    -- Off-platform allowlist: seller pode marcar pago. Plataforma / vazio / typo: NÃO.
    if v_new = 'pago' and v_old is distinct from 'pago' then
      if not public.batata_is_off_platform_payment(v_pm) then
        -- Excepção: já capturado por settle (amount_paid / PI)
        if not v_captured then
          NEW.status := OLD.status;
          return NEW;
        end if;
      end if;
    end if;

    -- Logística: só a partir de pago (ou captura) — evita unpaid→enviado
    if v_new in ('enviado', 'entregue') then
      if v_old is distinct from 'pago'
         and v_old is distinct from 'enviado'
         and not v_captured then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_new = 'devolvida' then
      if v_old not in (
        'devolucao_entregue',
        'disputa_devolucao_vendedor'
      ) then
        NEW.status := OLD.status;
        return NEW;
      end if;
      select exists(
        select 1 from public.order_disputes d
        where d.order_id = NEW.id
          and exists (
            select 1 from public.orders o
            where o.id = d.order_id and o.seller_id = v_uid
          )
          and lower(coalesce(d.status, '')) is distinct from 'recusada'
      ) into v_has_dispute;
      if not v_has_dispute then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_new = 'pedido_devolucao' and v_old is distinct from 'pedido_devolucao' then
      if not v_is_buyer then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;
  end if;

  if not v_is_buyer and not v_is_seller then
    NEW.status := OLD.status;
    return NEW;
  end if;

  return NEW;
end;
$fn$;

comment on function public.batata_orders_guard_paid_status() is
  'SAT: plataforma fail-closed (vazio=plataforma); off-platform só allowlist; logística exige pago/captura.';

-- ---------------------------------------------------------------------------
-- 5) Stock consume usa contract_qty canónico
-- ---------------------------------------------------------------------------
create or replace function public.batata_mark_product_sold_on_paid_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_units int;
  v_before int;
  v_remaining int;
  v_claimed int;
  v_stock_rows int;
  v_product_seller uuid;
begin
  if new.product_id is null then
    return new;
  end if;

  if lower(coalesce(new.status, '')) <> 'pago' then
    return new;
  end if;

  if new.stock_units_applied is not null then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and lower(coalesce(old.status, '')) is not distinct from lower(coalesce(new.status, '')) then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and lower(coalesce(old.status, '')) = 'premio_rifa' then
    return new;
  end if;

  select p.seller_id into v_product_seller
  from public.products p
  where p.id = new.product_id
  for update;

  if v_product_seller is distinct from new.seller_id then
    raise exception 'batata_stock_seller_mismatch'
      using errcode = 'P0001',
            hint = 'order=' || new.id::text || ' product=' || new.product_id::text;
  end if;

  -- Canónico: contract_qty (= quantity selada). Nunca divergir.
  v_units := greatest(
    coalesce(new.contract_qty, new.quantity, 1),
    1
  );

  -- Permitir claim na mesma sessão JWT (vendedor MB WAY → pago).
  perform set_config('batata.allow_internal_order_cols', '1', true);

  update public.orders
     set stock_units_applied = v_units,
         quantity = v_units,
         contract_qty = v_units
   where id = new.id
     and stock_units_applied is null;
  get diagnostics v_claimed = row_count;
  if v_claimed = 0 then
    return new;
  end if;

  select quantity into v_before
  from public.products
  where id = new.product_id;

  update public.products
     set quantity = quantity - v_units
   where id = new.product_id
     and seller_id = new.seller_id
     and coalesce(quantity, 0) >= v_units
   returning quantity into v_remaining;
  get diagnostics v_stock_rows = row_count;

  if v_stock_rows = 0 then
    raise exception 'batata_stock_insufficient'
      using errcode = 'P0001',
            hint = 'order=' || new.id::text || ' product=' || new.product_id::text ||
                   ' units=' || v_units::text || ' qty_before=' || coalesce(v_before::text, 'null');
  end if;

  if v_remaining is not null and v_remaining <= 0 then
    update public.products
       set is_sold = true,
           list_on_marketplace = false
     where id = new.product_id;
  elsif v_remaining is not null and v_remaining > 0 then
    update public.products
       set is_sold = false
     where id = new.product_id
       and is_sold = true;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6) product_offers — buyer não cria/aceita em benefício próprio
-- ---------------------------------------------------------------------------
create or replace function public.batata_product_offers_guard_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    -- Nunca nascer accepted/rejected via JWT
    if lower(trim(coalesce(NEW.status, ''))) is distinct from 'pending' then
      NEW.status := 'pending';
    end if;
    NEW.responded_at := null;
    if NEW.offered_by = 'buyer' then
      NEW.buyer_id := v_uid;
    elsif NEW.offered_by = 'seller' then
      NEW.seller_id := v_uid;
    end if;
    return NEW;
  end if;

  -- UPDATE: aceitar só a contraparte
  if NEW.status is distinct from OLD.status
     and lower(trim(coalesce(NEW.status, ''))) = 'accepted' then
    if lower(trim(coalesce(OLD.offered_by, ''))) = 'buyer' then
      if v_uid is distinct from OLD.seller_id then
        raise exception 'offer_accept_not_authorized' using errcode = '42501';
      end if;
    elsif lower(trim(coalesce(OLD.offered_by, ''))) = 'seller' then
      if v_uid is distinct from OLD.buyer_id then
        raise exception 'offer_accept_not_authorized' using errcode = '42501';
      end if;
    else
      raise exception 'offer_accept_not_authorized' using errcode = '42501';
    end if;
    NEW.responded_at := coalesce(NEW.responded_at, now());
    -- Congelar valor no accept
    NEW.amount := OLD.amount;
    NEW.product_id := OLD.product_id;
    NEW.buyer_id := OLD.buyer_id;
    NEW.seller_id := OLD.seller_id;
  end if;

  -- Após aceite/fecho: JWT não muda amount/status financeiro
  if lower(trim(coalesce(OLD.status, ''))) in (
    'accepted', 'rejected', 'superseded', 'expired'
  ) then
    NEW.amount := OLD.amount;
    NEW.status := OLD.status;
    NEW.product_id := OLD.product_id;
    NEW.buyer_id := OLD.buyer_id;
    NEW.seller_id := OLD.seller_id;
    NEW.offered_by := OLD.offered_by;
    NEW.responded_at := OLD.responded_at;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_product_offers_guard_authority on public.product_offers;
create trigger trg_batata_product_offers_guard_authority
  before insert or update on public.product_offers
  for each row
  execute function public.batata_product_offers_guard_authority();

-- ---------------------------------------------------------------------------
-- 7) Live reservations — buyer não declara accepted
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_reservation_guard_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_is_seller boolean := false;
  v_avail int := 0;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if NEW.requested_qty is null or NEW.requested_qty < 1 or NEW.requested_qty > 99 then
    raise exception 'invalid_requested_qty' using errcode = '23514';
  end if;

  v_is_seller :=
    (NEW.seller_id is not null and NEW.seller_id = v_uid)
    or exists (
      select 1 from public.lives l
      where l.id = NEW.live_id
        and (l.seller_id = v_uid or l.vendedor_id = v_uid)
    )
    or public.batata_staff_has_permission(NEW.seller_id, 'can_manage_reservations');

  if TG_OP = 'INSERT' then
    if not v_is_seller then
      -- Buyer / não-seller: só pending
      NEW.status := 'pending';
      NEW.buyer_id := coalesce(NEW.buyer_id, v_uid);
      if NEW.buyer_id is distinct from v_uid then
        raise exception 'reservation_buyer_mismatch' using errcode = '42501';
      end if;
    end if;
    return NEW;
  end if;

  -- UPDATE → accepted só seller/staff
  if NEW.status is distinct from OLD.status
     and lower(trim(coalesce(NEW.status, ''))) = 'accepted' then
    if not v_is_seller then
      raise exception 'reservation_accept_not_authorized' using errcode = '42501';
    end if;
  end if;

  -- Buyer JWT não muda status nem qty após criar
  if not v_is_seller and NEW.buyer_id = v_uid then
    if NEW.status is distinct from OLD.status then
      NEW.status := OLD.status;
    end if;
    if NEW.requested_qty is distinct from OLD.requested_qty then
      NEW.requested_qty := OLD.requested_qty;
    end if;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_live_reservation_guard_authority
  on public.live_reservation_requests;
create trigger trg_batata_live_reservation_guard_authority
  before insert or update on public.live_reservation_requests
  for each row
  execute function public.batata_live_reservation_guard_authority();

-- ---------------------------------------------------------------------------
-- 8) phone_verified_at + campos de confiança em profiles
-- ---------------------------------------------------------------------------
create or replace function public.batata_profiles_guard_verification()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    NEW.phone_verified_at := null;
    return NEW;
  end if;

  if NEW.phone_verified_at is distinct from OLD.phone_verified_at then
    NEW.phone_verified_at := OLD.phone_verified_at;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_profiles_guard_verification on public.profiles;
create trigger trg_batata_profiles_guard_verification
  before insert or update of phone_verified_at
  on public.profiles
  for each row
  execute function public.batata_profiles_guard_verification();

-- ---------------------------------------------------------------------------
-- 9) Disputas terminais — congelar campos financeiros
-- ---------------------------------------------------------------------------
create or replace function public.batata_order_disputes_guard_terminal()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_old_st text;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;

  v_old_st := lower(trim(coalesce(OLD.status, '')));
  if v_old_st in (
    'resolvida', 'fechada', 'closed', 'resolved', 'recusada',
    'cancelada', 'concluida', 'concluída', 'arquivada'
  ) then
    NEW.seller_refund_percent := OLD.seller_refund_percent;
    NEW.seller_offer_type := OLD.seller_offer_type;
    NEW.seller_pays_return_shipping := OLD.seller_pays_return_shipping;
    NEW.seller_offer_set_by := OLD.seller_offer_set_by;
    NEW.seller_offer_set_at := OLD.seller_offer_set_at;
    NEW.buyer_decision := OLD.buyer_decision;
    NEW.admin_resolution := OLD.admin_resolution;
    NEW.admin_resolution_note := OLD.admin_resolution_note;
    NEW.status := OLD.status;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_order_disputes_guard_terminal on public.order_disputes;
create trigger trg_batata_order_disputes_guard_terminal
  before update on public.order_disputes
  for each row
  execute function public.batata_order_disputes_guard_terminal();

-- ---------------------------------------------------------------------------
-- 10) Reviews — is_automatic server-only; stars imutáveis após INSERT
-- ---------------------------------------------------------------------------
create or replace function public.batata_reviews_guard_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_order public.orders%rowtype;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  NEW.buyer_id := v_uid;
  -- Cliente nunca marca automático
  NEW.is_automatic := false;

  if NEW.order_id is null then
    raise exception 'review_order_required' using errcode = '23514';
  end if;

  select * into v_order from public.orders where id = NEW.order_id;
  if not found or v_order.buyer_id is distinct from v_uid then
    raise exception 'review_order_not_yours' using errcode = '42501';
  end if;

  if lower(coalesce(v_order.status, '')) not in ('concluido', 'entregue') then
    raise exception 'review_order_invalid_status' using errcode = '23514';
  end if;

  -- Plataforma: exigir captura (evita review em unpaid→concluido legado)
  if public.batata_is_platform_payment(v_order.payment_method)
     and coalesce(v_order.amount_paid_cents, 0) <= 0
     and coalesce(v_order.stripe_payment_intent_id, '') = '' then
    raise exception 'review_order_unpaid' using errcode = '23514';
  end if;

  NEW.target_id := v_order.seller_id;
  if lower(coalesce(NEW.author_role, '')) = '' then
    NEW.author_role := 'comprador';
  end if;

  if exists (
    select 1 from public.reviews r
    where r.order_id = NEW.order_id
      and r.buyer_id = v_uid
      and lower(coalesce(r.author_role, 'comprador')) = 'comprador'
  ) then
    raise exception 'review_duplicate' using errcode = '23505';
  end if;

  return NEW;
end;
$fn$;

create or replace function public.batata_reviews_guard_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  -- Política produto: review imutável após publicar (stars/comment/is_automatic)
  NEW.stars := OLD.stars;
  NEW.comment := OLD.comment;
  NEW.is_automatic := OLD.is_automatic;
  NEW.order_id := OLD.order_id;
  NEW.buyer_id := OLD.buyer_id;
  NEW.target_id := OLD.target_id;
  NEW.author_role := OLD.author_role;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_reviews_guard_insert on public.reviews;
create trigger trg_batata_reviews_guard_insert
  before insert on public.reviews
  for each row
  execute function public.batata_reviews_guard_insert();

drop trigger if exists trg_batata_reviews_guard_update on public.reviews;
create trigger trg_batata_reviews_guard_update
  before update on public.reviews
  for each row
  execute function public.batata_reviews_guard_update();

-- ---------------------------------------------------------------------------
-- 11) REVOKE lab / staging / auto-feedback de anon+authenticated
-- ---------------------------------------------------------------------------
do $revoke_lab$
declare
  r record;
begin
  for r in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (
        p.proname like 'batata_lab%'
        or p.proname like 'batata_staging%'
        or p.proname in (
          'batata_generate_auto_feedback',
          'batata_expire_product_offers',
          'staging_nuke_user_data',
          'staging_restore_stock_before_nuke'
        )
      )
  loop
    execute format(
      'revoke all on function public.%I(%s) from public, anon, authenticated',
      r.proname, r.args
    );
    execute format(
      'grant execute on function public.%I(%s) to service_role',
      r.proname, r.args
    );
  end loop;
end;
$revoke_lab$;

-- Pin explícito (prova no relatório)
revoke all on function public.batata_lab_clear_all_fm_pending()
  from public, anon, authenticated;
grant execute on function public.batata_lab_clear_all_fm_pending() to service_role;

revoke all on function public.batata_lab_clear_fm_pending(uuid)
  from public, anon, authenticated;
grant execute on function public.batata_lab_clear_fm_pending(uuid) to service_role;

revoke all on function public.batata_generate_auto_feedback(timestamptz)
  from public, anon, authenticated;
grant execute on function public.batata_generate_auto_feedback(timestamptz) to service_role;

-- Overload sem args (default)
do $af$
begin
  revoke all on function public.batata_generate_auto_feedback()
    from public, anon, authenticated;
  grant execute on function public.batata_generate_auto_feedback() to service_role;
exception when undefined_function then
  null;
end;
$af$;

notify pgrst, 'reload schema';
