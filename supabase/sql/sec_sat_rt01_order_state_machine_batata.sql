-- =============================================================================
-- SAT-RT-01 — Máquina de estados fail-closed (staging only)
-- Buyer não fabrica entregue/concluido/review sem pagamento confirmado.
-- Preserva: seller MB WAY → pago; Stripe settle → pago; lista de espera live.
-- NÃO é Fase 4. NÃO tocar produção.
-- =============================================================================

-- Confirmação de pagamento autoritativa para o método.
-- Plataforma (inclui vazio/typo): captura Stripe.
-- Off-platform allowlist: seller já atestou via status na cadeia pós-pago
--   OU captura (se algum dia coexistir).
create or replace function public.batata_order_payment_confirmed(
  p_payment_method text,
  p_status text,
  p_amount_paid_cents integer,
  p_stripe_payment_intent_id text
)
returns boolean
language sql
immutable
as $$
  select
    coalesce(p_amount_paid_cents, 0) > 0
    or coalesce(p_stripe_payment_intent_id, '') <> ''
    or (
      public.batata_is_off_platform_payment(p_payment_method)
      and lower(trim(coalesce(p_status, ''))) in (
        'pago',
        'enviado',
        'entregue',
        'concluido',
        'premio_rifa',
        'pedido_devolucao',
        'em_devolucao',
        'devolucao_entregue',
        'disputa_devolucao_vendedor',
        'devolvida'
      )
    );
$$;

revoke all on function public.batata_order_payment_confirmed(text, text, integer, text)
  from public, anon;
grant execute on function public.batata_order_payment_confirmed(text, text, integer, text)
  to authenticated, service_role;

comment on function public.batata_order_payment_confirmed(text, text, integer, text) is
  'SAT-RT-01: venda só após captura (plataforma) ou status pós-pago seller (off-platform).';

-- Predicados de transição (explícitos, fail-closed).
create or replace function public.batata_order_status_is_prepay(p_status text)
returns boolean
language sql
immutable
as $$
  select lower(trim(coalesce(p_status, ''))) in (
    'reserva_pendente',
    'reservado',
    'pendente',
    'aguarda_confirmacao',
    'aguarda_pagamento',
    ''
  );
$$;

create or replace function public.batata_order_status_is_logistics_or_terminal(p_status text)
returns boolean
language sql
immutable
as $$
  select lower(trim(coalesce(p_status, ''))) in (
    'enviado',
    'entregue',
    'concluido',
    'pedido_devolucao',
    'em_devolucao',
    'devolucao_entregue',
    'disputa_devolucao_vendedor',
    'devolvida'
  );
$$;

-- ---------------------------------------------------------------------------
-- Guard principal — máquina de estados
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
  v_pm text;
  v_off boolean;
  v_platform boolean;
  v_captured boolean;
  v_paid_confirmed boolean;
  v_has_dispute boolean := false;
  v_released boolean := false;
begin
  -- service_role / SQL interno: não restringir (settle, jobs, restores).
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  v_new := lower(trim(coalesce(NEW.status, '')));
  v_is_buyer := NEW.buyer_id is not null and NEW.buyer_id = v_uid;
  v_is_seller := NEW.seller_id is not null and NEW.seller_id = v_uid;

  -- INSERT: buyer não nasce em estado de venda realizada.
  if TG_OP = 'INSERT' then
    if v_is_buyer and (
         v_new = 'pago'
         or public.batata_order_status_is_logistics_or_terminal(v_new)
         or v_new = 'premio_rifa'
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
  v_off := public.batata_is_off_platform_payment(v_pm);
  v_platform := public.batata_is_platform_payment(v_pm);
  v_captured :=
    coalesce(OLD.amount_paid_cents, 0) > 0
    or coalesce(OLD.stripe_payment_intent_id, '') <> '';

  -- Confirmação olha ao estado ANTERIOR (não ao NEW).
  v_paid_confirmed := public.batata_order_payment_confirmed(
    v_pm,
    v_old,
    OLD.amount_paid_cents,
    OLD.stripe_payment_intent_id
  );

  v_released := OLD.wallet_release_processed_at is not null
    or NEW.wallet_release_processed_at is not null;

  -- Pago→cancelado bloqueado (já existia).
  if v_paid_confirmed and v_new in ('cancelado', 'cancelled') then
    NEW.status := OLD.status;
    return NEW;
  end if;

  -- ---------------------------------------------------------------
  -- GATE UNIVERSAL: logística/terminal exige pagamento confirmado.
  -- Excepção: transição PARA 'pago' (tratada abaixo por papel).
  -- ---------------------------------------------------------------
  if public.batata_order_status_is_logistics_or_terminal(v_new)
     and not v_paid_confirmed then
    NEW.status := OLD.status;
    return NEW;
  end if;

  -- Plataforma: seller também não marca pago sem captura
  -- (off-platform seller→pago continua permitido).
  if v_new = 'pago' and not v_paid_confirmed then
    if v_platform or not v_off then
      -- Só service_role/settle deve passar; JWT plataforma bloqueado.
      if not v_captured then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;
  end if;

  -- ---- Comprador (fail-closed: só transições de produto) ----
  if v_is_buyer and not v_is_seller then
    -- Nunca atesta pagamento.
    if v_new = 'pago' and v_old is distinct from 'premio_rifa' then
      NEW.status := OLD.status;
      return NEW;
    end if;

    -- Nunca marca envio / entregue (produto: seller envia; buyer confirma receção→concluido).
    if v_new in ('enviado', 'entregue') then
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

    -- Não voltar a pré-pago depois de pago.
    if v_paid_confirmed and public.batata_order_status_is_prepay(v_new) then
      NEW.status := OLD.status;
      return NEW;
    end if;

    -- Concluido: só após envio OU pago (mão) OU entregue — e já passou o gate de pagamento.
    if v_new = 'concluido' then
      if v_old not in (
        'enviado',
        'entregue',
        'pago',
        'pedido_devolucao',
        'em_devolucao',
        'disputa_devolucao_vendedor',
        'devolucao_entregue'
      ) then
        NEW.status := OLD.status;
        return NEW;
      end if;
      -- Defesa extra: pré-pago nunca.
      if public.batata_order_status_is_prepay(v_old) then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;
  end if;

  -- ---- Vendedor ----
  if v_is_seller then
    -- MB WAY / off-platform: seller confirma receção do dinheiro → pago.
    if v_new = 'pago' and v_old is distinct from 'pago' then
      if not v_off and not v_captured then
        NEW.status := OLD.status;
        return NEW;
      end if;
      -- Só a partir de pré-pago / aguarda (não saltar de cancelado etc.).
      if not public.batata_order_status_is_prepay(v_old)
         and v_old is distinct from 'aguarda_pagamento' then
        -- permitir se já capturado (idempotência settle raro via JWT? bloquear)
        if not v_captured then
          NEW.status := OLD.status;
          return NEW;
        end if;
      end if;
    end if;

    -- Logística seller: predecessor explícito + pagamento (gate universal já).
    if v_new = 'enviado' then
      if v_old is distinct from 'pago' and v_old is distinct from 'enviado' then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_new = 'entregue' then
      if v_old not in ('pago', 'enviado') then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    -- Seller não marca concluido (produto: buyer confirma receção).
    if v_new = 'concluido' then
      NEW.status := OLD.status;
      return NEW;
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
  'SAT-RT-01: FSM fail-closed — logística/terminal só após pagamento confirmado; buyer não fabrica entregue/concluido unpaid; MB WAY seller→pago preservado.';

-- ---------------------------------------------------------------------------
-- Reviews: exigir venda com pagamento confirmado (não só status)
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

  -- SAT-RT-01: review só se pagamento foi confirmado para o método.
  if not public.batata_order_payment_confirmed(
       v_order.payment_method,
       v_order.status,
       v_order.amount_paid_cents,
       v_order.stripe_payment_intent_id
     ) then
    raise exception 'review_order_unpaid' using errcode = '23514';
  end if;

  -- Defesa: off-platform sem stock claim = nunca passou por seller→pago.
  if public.batata_is_off_platform_payment(v_order.payment_method)
     and coalesce(v_order.stock_units_applied, 0) <= 0
     and coalesce(v_order.amount_paid_cents, 0) <= 0 then
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

notify pgrst, 'reload schema';
