-- SEC-002 (fase 1, BATATA) — Impedir comprador de se auto-marcar «pago»
-- NÃO bloqueia:
--   · Vendedor: aguarda_confirmacao/reservado → pago (MB WAY / transferência)
--   · Comprador: premio_rifa → pago (entrega em mão do prémio)
--   · service_role / Stripe settle (sem JWT authenticated de end-user)
--   · Outros status (enviado, concluido, cancelado, disputas) — fase 2 se preciso
--
-- Risco regressão: Médio-Baixo nesta fase (só corta o atalho de fraude clássico).

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
begin
  -- Só clientes autenticados (não service_role / SQL Editor).
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  v_new := lower(trim(coalesce(NEW.status, '')));

  if TG_OP = 'INSERT' then
    -- Comprador não cria encomenda já «pago» / «concluido» / «devolvida».
    if NEW.buyer_id is not null
       and NEW.buyer_id = v_uid
       and v_new in ('pago', 'concluido', 'devolvida') then
      NEW.status := 'reserva_pendente';
    end if;
    return NEW;
  end if;

  -- UPDATE
  v_old := lower(trim(coalesce(OLD.status, '')));
  if v_new is not distinct from v_old then
    return NEW;
  end if;

  -- Comprador a forçar «pago» sem ser fluxo prémio rifa.
  if v_new = 'pago'
     and NEW.buyer_id is not null
     and NEW.buyer_id = v_uid
     and v_old is distinct from 'premio_rifa' then
    NEW.status := OLD.status;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_paid_status on public.orders;
create trigger trg_batata_orders_guard_paid_status
  before insert or update of status
  on public.orders
  for each row
  execute function public.batata_orders_guard_paid_status();

comment on function public.batata_orders_guard_paid_status() is
  'SEC-002 fase1: buyer cannot self-mark pago except premio_rifa→pago; Stripe/seller OK.';

notify pgrst, 'reload schema';
