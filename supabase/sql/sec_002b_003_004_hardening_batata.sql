-- SEC-002 fase 2 + SEC-003 + SEC-004 (BATATA, cuidado com regressões)
-- Staging 2026-08-04
--
-- SEC-002 fase2: reforça estados dinheiro sem partir:
--   · V → enviado, V confirma pago, V → devolvida (disputa)
--   · B → concluido (receção / fechar disputa) a partir de estados pós-pagamento
--   · B → em_devolucao / pedido_devolucao
--   · B → premio_rifa → pago (já na fase1)
--
-- SEC-003: política lives "visíveis por todos" (using true) + esconder stream keys
-- SEC-004: revoke authenticated em stripe_convert (app usa reconcile / edge service_role)

-- =============================================================================
-- SEC-002 fase 2 — alargar guard de status
-- =============================================================================

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
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  v_new := lower(trim(coalesce(NEW.status, '')));
  v_is_buyer := NEW.buyer_id is not null and NEW.buyer_id = v_uid;
  v_is_seller := (NEW.seller_id is not null and NEW.seller_id = v_uid);

  if TG_OP = 'INSERT' then
    if v_is_buyer and v_new in ('pago', 'concluido', 'devolvida', 'enviado') then
      NEW.status := 'reserva_pendente';
    end if;
    return NEW;
  end if;

  v_old := lower(trim(coalesce(OLD.status, '')));
  if v_new is not distinct from v_old then
    return NEW;
  end if;

  -- --- Comprador ---
  if v_is_buyer and not v_is_seller then
    -- Auto-pago (excepto prémio rifa) — fase 1
    if v_new = 'pago' and v_old is distinct from 'premio_rifa' then
      NEW.status := OLD.status;
      return NEW;
    end if;

    -- Só o vendedor marca enviado
    if v_new = 'enviado' then
      NEW.status := OLD.status;
      return NEW;
    end if;

    -- Só o vendedor aceita disputa → devolvida (app)
    if v_new = 'devolvida' then
      NEW.status := OLD.status;
      return NEW;
    end if;

    -- Concluido: receção ou fecho de disputa — não a partir de reserva/pendente
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
    end if;
  end if;

  return NEW;
end;
$fn$;

-- Trigger já existe (fase1); recreate garante definição nova
drop trigger if exists trg_batata_orders_guard_paid_status on public.orders;
create trigger trg_batata_orders_guard_paid_status
  before insert or update of status
  on public.orders
  for each row
  execute function public.batata_orders_guard_paid_status();

comment on function public.batata_orders_guard_paid_status() is
  'SEC-002: buyer cannot self-pay/ship/refund-wallet; concluido only from post-pay states.';

-- =============================================================================
-- SEC-004 — stripe_convert só service_role (e callers SECURITY DEFINER)
-- =============================================================================

revoke all on function public.batata_live_reservation_stripe_convert(uuid, uuid) from public;
revoke all on function public.batata_live_reservation_stripe_convert(uuid, uuid) from authenticated;
grant execute on function public.batata_live_reservation_stripe_convert(uuid, uuid) to service_role;
-- authenticated continua a poder chamar batata_live_reconcile_stripe_order (com ownership)

-- =============================================================================
-- SEC-003 — lives: fechar SELECT aberto + esconder stream keys
-- =============================================================================

-- Política FlutterFlow perigosa (qual = true) vista em staging
drop policy if exists "Lives ativas são visíveis por todos" on public.lives;
drop policy if exists "lives_select_public_live" on public.lives;

-- Feed Home / player / Hub: ver lives públicas sem ser dono
create policy "lives_select_feed_or_owner"
  on public.lives
  for select
  to authenticated, anon
  using (
    status in ('live', 'ended', 'scheduled')
    or coalesce(is_active, false) = true
    or auth.uid() = seller_id
    or auth.uid() = vendedor_id
  );

-- Chaves RTMP: não legíveis por anon/authenticated (PostgREST omite colunas)
-- Seller obtém stream_key via edge create-mux-live (já existente).
do $$
begin
  begin
    revoke select (mux_stream_key, stream_key) on table public.lives from anon;
  exception when undefined_object then null;
  when others then null;
  end;
  begin
    revoke select (mux_stream_key, stream_key) on table public.lives from authenticated;
  exception when undefined_object then null;
  when others then null;
  end;
end $$;

-- Garantir que service_role mantém acesso completo (edge complete-mux, etc.)
grant select on table public.lives to service_role;

notify pgrst, 'reload schema';
