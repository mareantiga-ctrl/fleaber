-- S2-P0 settle replay + BI-SHIP-01 freeze shipping (staging BATATA)
-- GET settle em order já pago NÃO deve mapear quote-fail → oversell refund (Edge).
-- JWT não pode PATCH shipping_method depois de selo válido (allowlist).
-- production_touched: false · fase4: false

create or replace function public.batata_shipping_method_is_sealed(p_method text)
returns boolean
language plpgsql
immutable
as $$
declare
  m text := lower(trim(coalesce(p_method, '')));
begin
  if m = '' then
    return false;
  end if;
  -- Mesma allowlist conceptual da Edge (hand + carrier labels).
  return m in (
    'hand', 'mao', 'mão', 'pickup', 'entrega_mao', 'entrega_mão',
    'entrega em mao', 'entrega em mão', 'levantamento',
    'entrega em mão (€0.00)', 'entrega em mao (€0.00)',
    'carrier', 'transportadora', 'ctt', 'correios',
    'envio transportadora (€3.50)', 'envio transportadora (€3,50)'
  )
  or m like 'envio transportadora%'
  or m like 'entrega em m%';
end;
$$;

create or replace function public.batata_orders_guard_shipping_seal()
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

  if TG_OP = 'UPDATE'
     and public.batata_shipping_method_is_sealed(OLD.shipping_method)
     and NEW.shipping_method is distinct from OLD.shipping_method then
    -- BI-SHIP-01: selo válido imutável via JWT (buyer/seller).
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
  'BI-SHIP-01: JWT não muda shipping_method depois de selo válido (hand/carrier).';

notify pgrst, 'reload schema';
