-- =============================================================================
-- C1 — RI-E-SELLER-PATCH-CONVERTED-OVER
-- Classe: qualquer estado JWT que CONSOME capacidade ≤ stock real.
-- Staging only. NÃO Fase 4. NÃO produção.
-- =============================================================================
-- Semântica (check constraint live):
--   pending | rejected | expired  → NÃO consomem capacidade (lista de espera / fecho)
--   accepted | converted          → CONSUMEM capacidade (reserva / venda)
-- Canonicaliza status (case/whitespace) antes da decisão.
-- Advisory lock por live_item_id nas transições que consomem (races).
-- =============================================================================

create or replace function public.batata_live_reservation_status_canonical(p_status text)
returns text
language sql
immutable
as $$
  select lower(trim(coalesce(p_status, '')));
$$;

create or replace function public.batata_live_reservation_status_consumes_capacity(p_status text)
returns boolean
language sql
immutable
as $$
  -- Únicos estados do check constraint que materializam/reservam unidades.
  -- Qualquer futuro estado consumidor DEVE entrar aqui + no allowlist abaixo.
  select public.batata_live_reservation_status_canonical(p_status) in (
    'accepted',
    'converted'
  );
$$;

comment on function public.batata_live_reservation_status_consumes_capacity(text) is
  'RI-E class: true se o status conta em reserved/sold capacity (accepted|converted).';

revoke all on function public.batata_live_reservation_status_canonical(text) from public, anon;
revoke all on function public.batata_live_reservation_status_consumes_capacity(text) from public, anon;
grant execute on function public.batata_live_reservation_status_canonical(text)
  to authenticated, service_role;
grant execute on function public.batata_live_reservation_status_consumes_capacity(text)
  to authenticated, service_role;

-- Capacidade restante exclui a própria row (UPDATE) e soma todos os estados consumidores.
create or replace function public.batata_live_reservation_accept_available(
  p_live_item_id uuid,
  p_exclude_request_id uuid default null
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_item_qty int := 0;
  v_already int := 0;
begin
  if p_live_item_id is null then
    return 0;
  end if;
  v_item_qty := coalesce(public.batata_live_item_total_qty(p_live_item_id), 0);
  if v_item_qty <= 0 then
    return 0;
  end if;
  select coalesce(sum(r.requested_qty), 0)::int
  into v_already
  from public.live_reservation_requests r
  where r.live_item_id = p_live_item_id
    and public.batata_live_reservation_status_consumes_capacity(r.status)
    and r.id is distinct from p_exclude_request_id;
  return greatest(v_item_qty - v_already, 0);
end;
$fn$;

revoke all on function public.batata_live_reservation_accept_available(uuid, uuid)
  from public, anon;
grant execute on function public.batata_live_reservation_accept_available(uuid, uuid)
  to authenticated, service_role;

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
  v_new_consumes boolean := false;
  v_old_consumes boolean := false;
  v_need_capacity boolean := false;
  v_allowed_status boolean := false;
begin
  -- service_role / sem JWT end-user: paths internos (stripe convert, lab).
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if NEW.requested_qty is null or NEW.requested_qty < 1 or NEW.requested_qty > 99 then
    raise exception 'invalid_requested_qty' using errcode = '23514';
  end if;

  -- Canonicalizar status JWT (ACCEPTED / " converted " → accepted/converted)
  NEW.status := public.batata_live_reservation_status_canonical(NEW.status);

  v_allowed_status := NEW.status in (
    'pending', 'accepted', 'rejected', 'expired', 'converted'
  );
  if not v_allowed_status then
    raise exception 'invalid_reservation_status' using errcode = '23514';
  end if;

  v_is_seller :=
    (NEW.seller_id is not null and NEW.seller_id = v_uid)
    or exists (
      select 1 from public.lives l
      where l.id = NEW.live_id
        and (l.seller_id = v_uid or l.vendedor_id = v_uid)
    )
    or public.batata_staff_has_permission(NEW.seller_id, 'can_manage_reservations');

  v_new_consumes := public.batata_live_reservation_status_consumes_capacity(NEW.status);

  if TG_OP = 'INSERT' then
    if not v_is_seller then
      -- Buyer / não-seller: só pending (lista de espera; qty pode > stock)
      NEW.status := 'pending';
      NEW.buyer_id := coalesce(NEW.buyer_id, v_uid);
      if NEW.buyer_id is distinct from v_uid then
        raise exception 'reservation_buyer_mismatch' using errcode = '42501';
      end if;
      return NEW;
    end if;

    -- Seller INSERT em estado consumidor → capacidade obrigatória
    if v_new_consumes then
      perform pg_advisory_xact_lock(hashtext(NEW.live_item_id::text || ':live_res_cap'));
      v_avail := public.batata_live_reservation_accept_available(
        NEW.live_item_id,
        null
      );
      if NEW.requested_qty > v_avail then
        raise exception 'qty_exceeds_stock' using errcode = '23514';
      end if;
    end if;
    return NEW;
  end if;

  -- UPDATE
  v_old_consumes := public.batata_live_reservation_status_consumes_capacity(OLD.status);

  -- Buyer JWT: congelar status e qty
  if not v_is_seller and NEW.buyer_id = v_uid then
    if NEW.status is distinct from public.batata_live_reservation_status_canonical(OLD.status) then
      NEW.status := public.batata_live_reservation_status_canonical(OLD.status);
    end if;
    if NEW.requested_qty is distinct from OLD.requested_qty then
      NEW.requested_qty := OLD.requested_qty;
    end if;
    return NEW;
  end if;

  -- Transição para estado consumidor: só seller/staff
  if v_new_consumes and not v_old_consumes then
    if not v_is_seller then
      raise exception 'reservation_accept_not_authorized' using errcode = '42501';
    end if;
  end if;

  -- Semântica: precisa validar capacidade se
  --   (a) passa a consumir, ou
  --   (b) já consumia e qty aumenta
  v_need_capacity :=
    v_new_consumes
    and (
      (not v_old_consumes)
      or (NEW.requested_qty > coalesce(OLD.requested_qty, 0))
    );

  if v_need_capacity then
    if NEW.live_item_id is null then
      raise exception 'qty_exceeds_stock' using errcode = '23514';
    end if;
    perform pg_advisory_xact_lock(hashtext(NEW.live_item_id::text || ':live_res_cap'));
    v_avail := public.batata_live_reservation_accept_available(
      NEW.live_item_id,
      NEW.id
    );
    if NEW.requested_qty > v_avail then
      raise exception 'qty_exceeds_stock' using errcode = '23514';
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

comment on function public.batata_live_reservation_guard_authority() is
  'C1 RI-E class: JWT capacity gate for any consuming status (accepted|converted); pending waitlist OK; advisory lock races.';

notify pgrst, 'reload schema';
