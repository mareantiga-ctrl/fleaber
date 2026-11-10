-- =============================================================================
-- BATATA — Blind D 1858 + E 1859 (P1/P2/P3)
-- Sem remover fluxos: mão continua; carrier selado; UI confirma receção OK.
-- production_touched: false · fase4: false
-- =============================================================================

-- ---------------------------------------------------------------------------
-- D1-SHIP-UNSEALED-EARLY-CONFIRM P1
-- Depois de pago/captura: JWT não muda shipping_method (null→mão, FedEx→mão).
-- Antes de pago: selo allowlist continua; Flutter grava mão/carrier no INSERT.
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_shipping_seal()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_old_st text;
  v_paid boolean;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;

  if NEW.shipping_method is not distinct from OLD.shipping_method then
    return NEW;
  end if;

  v_old_st := lower(trim(coalesce(OLD.status, '')));
  v_paid :=
    v_old_st in (
      'pago', 'enviado', 'entregue', 'concluido', 'premio_rifa',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor', 'devolvida'
    )
    or coalesce(OLD.amount_paid_cents, 0) > 0
    or nullif(trim(coalesce(OLD.stripe_payment_intent_id, '')), '') is not null;

  -- D1: após captura/pago → portes congelados (evita null→mão + release).
  -- Não congelar só por Session open (pré-pago ainda pode alinhar UI).
  if v_paid then
    raise exception 'order_shipping_frozen_after_payment' using errcode = '42501';
  end if;

  -- Pré-pago: selo allowlist imutável (BI-SHIP-01).
  if public.batata_shipping_method_is_sealed(OLD.shipping_method) then
    NEW.shipping_method := OLD.shipping_method;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_shipping_seal on public.orders;
create trigger trg_batata_orders_guard_shipping_seal
  before update of shipping_method
  on public.orders
  for each row
  execute function public.batata_orders_guard_shipping_seal();

comment on function public.batata_orders_guard_shipping_seal() is
  'D1-P1: pós-pago/session shipping imutável; pré-pago selo allowlist.';

-- ---------------------------------------------------------------------------
-- D4-CHAT-FORGE-CARD P2 — cards FLEABER_JSON já gravados não mudam de kind/texto
-- (INSERT de card legítimo na confirmação de receção mantém-se)
-- ---------------------------------------------------------------------------
create or replace function public.batata_chat_messages_guard_update()
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

  NEW.sender_id := OLD.sender_id;
  NEW.chat_id := OLD.chat_id;

  if OLD.sender_id is distinct from v_uid then
    -- Só is_read alheio (se a policy permitir)
    NEW.text := OLD.text;
    return NEW;
  end if;

  -- D4: JSON de sistema imutável após INSERT (anti-forge UPDATE).
  if coalesce(OLD.text, '') like 'FLEABER_JSON_V1:%'
     and NEW.text is distinct from OLD.text then
    raise exception 'chat_system_card_immutable' using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_chat_messages_guard_update on public.chat_messages;
create trigger trg_batata_chat_messages_guard_update
  before update on public.chat_messages
  for each row
  execute function public.batata_chat_messages_guard_update();

comment on function public.batata_chat_messages_guard_update() is
  'D4-P2: FLEABER_JSON_V1 imutável no UPDATE; INSERT de cards UI preservado.';

notify pgrst, 'reload schema';
