-- =============================================================================
-- FASE 3 — Autorização e integridade de estado (BATATA)
-- Staging only. NÃO é consolidação global de migrations (Fase 4).
-- Idempotente.
-- Fecha: P1-02 bag qty · P1-13 pago→cancelado · ensure_checkout authz ·
--        stripe_convert anon GRANT
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) P1-02 — bag_update_qty: cap por stock disponível + máximo absoluto 99
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_bag_update_qty(
  p_request_id uuid,
  p_qty int
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.live_reservation_requests%rowtype;
  v_qty int;
  v_avail int := 0;
  v_snap jsonb;
  v_others int := 0;
begin
  select * into v_req
  from public.live_reservation_requests
  where id = p_request_id
  for update;

  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'request_not_found');
  end if;

  if auth.uid() is null
     or auth.uid() <> v_req.buyer_id
     or v_req.source <> 'fleaber_live'
     or v_req.status not in ('pending', 'accepted') then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  -- Rejeitar NULL / <=0 / absurdos (não clamp silencioso a 9999).
  if p_qty is null or p_qty < 1 then
    return jsonb_build_object('ok', false, 'error', 'invalid_qty');
  end if;
  if p_qty > 99 then
    return jsonb_build_object('ok', false, 'error', 'qty_too_high');
  end if;

  v_qty := p_qty;

  -- Cap pelo stock disponível do live_item (+ esta linha pode reter a sua qty actual).
  begin
    v_snap := public.batata_live_item_stock(v_req.live_item_id);
    v_avail := coalesce((v_snap->>'available_qty')::int, 0);
  exception when others then
    v_avail := 0;
  end;

  -- available_qty tipicamente exclui esta reserva aceite/pending — somar a qty actual
  -- desta linha para o tecto permitido a este pedido.
  v_avail := v_avail + greatest(coalesce(v_req.requested_qty, 1), 0);

  if v_avail < 1 then
    return jsonb_build_object('ok', false, 'error', 'no_stock', 'available_qty', 0);
  end if;

  if v_qty > v_avail then
    return jsonb_build_object(
      'ok', false,
      'error', 'qty_exceeds_stock',
      'available_qty', v_avail,
      'requested', v_qty
    );
  end if;

  update public.live_reservation_requests
  set
    requested_qty = v_qty,
    updated_at = now()
  where id = v_req.id;

  return jsonb_build_object(
    'ok', true,
    'request_id', v_req.id,
    'requested_qty', v_qty,
    'available_qty', v_avail
  );
end;
$$;

revoke all on function public.batata_live_bag_update_qty(uuid, int)
  from public, anon;
grant execute on function public.batata_live_bag_update_qty(uuid, int)
  to authenticated, service_role;

-- INSERT/UPDATE directo: teto requested_qty (buyer não tem UPDATE policy, mas
-- INSERT buyer + triggers seller path). Defesa em profundidade.
create or replace function public.batata_live_reservation_qty_cap()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if NEW.requested_qty is null or NEW.requested_qty < 1 then
    NEW.requested_qty := 1;
  elsif NEW.requested_qty > 99 then
    NEW.requested_qty := 99;
  end if;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_live_reservation_qty_cap on public.live_reservation_requests;
create trigger trg_batata_live_reservation_qty_cap
  before insert or update of requested_qty
  on public.live_reservation_requests
  for each row
  execute function public.batata_live_reservation_qty_cap();

-- ---------------------------------------------------------------------------
-- 2) P1-13 — autenticado não cancela estados pós-pagamento (restock sem refund)
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
begin
  -- service_role / SQL Editor / refund-order Edge: sem restrição JWT.
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  v_new := lower(trim(coalesce(NEW.status, '')));
  v_is_buyer := NEW.buyer_id is not null and NEW.buyer_id = v_uid;
  v_is_seller := (NEW.seller_id is not null and NEW.seller_id = v_uid);

  if TG_OP = 'INSERT' then
    if v_is_buyer and v_new in (
      'pago', 'concluido', 'devolvida', 'enviado', 'premio_rifa'
    ) then
      NEW.status := 'reserva_pendente';
    end if;
    return NEW;
  end if;

  v_old := lower(trim(coalesce(OLD.status, '')));
  if v_new is not distinct from v_old then
    return NEW;
  end if;

  v_post_pay := v_old in (
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
  );

  -- Qualquer authenticated (buyer ou seller via PostgREST): não cancelar pós-pago.
  -- Cancelamento legítimo pós-pago → refund-order (service_role).
  if v_post_pay and v_new in ('cancelado', 'cancelled') then
    NEW.status := OLD.status;
    return NEW;
  end if;

  -- --- Comprador ---
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

    -- Pós-pago: comprador não salta para estados de vendedor / inventário.
    if v_post_pay and v_new in (
      'reserva_pendente', 'reservado', 'pendente', 'aguarda_confirmacao'
    ) then
      NEW.status := OLD.status;
      return NEW;
    end if;

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

drop trigger if exists trg_batata_orders_guard_paid_status on public.orders;
create trigger trg_batata_orders_guard_paid_status
  before insert or update of status
  on public.orders
  for each row
  execute function public.batata_orders_guard_paid_status();

comment on function public.batata_orders_guard_paid_status() is
  'FASE3: buyer/seller JWT cannot cancel post-pay (restock without refund); service_role OK.';

-- ---------------------------------------------------------------------------
-- 3) ensure_checkout_product — só seller da live (ou service_role)
-- ---------------------------------------------------------------------------
create or replace function public.batata_ensure_checkout_product(p_live_item_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_live public.lives%rowtype;
  v_seller uuid;
  v_pid uuid;
  v_img_json jsonb;
  v_img_text text[];
  v_image_urls_udt text;
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    raise exception 'live_item_not_found';
  end if;

  select * into v_live from public.lives where id = v_li.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);

  -- anon nunca.
  if v_role = 'anon' then
    raise exception 'not_allowed';
  end if;

  if v_li.checkout_product_id is not null then
    -- Só o vendedor pode sincronizar preço/qty no shadow (evita wipe de stock).
    -- Comprador no checkout só precisa do id existente.
    if v_role = 'authenticated'
       and v_uid is not null
       and v_seller is not null
       and v_uid = v_seller then
      update public.products
      set
        price = case
          when v_li.price is not null and v_li.price > 0 then v_li.price
          else price
        end,
        title = coalesce(nullif(trim(v_li.title), ''), title),
        quantity = greatest(coalesce(v_li.quantity, 1), 1)
      where id = v_li.checkout_product_id;
    end if;
    return v_li.checkout_product_id;
  end if;

  if v_li.item_kind = 'marketplace_product' and v_li.product_id is not null then
    return v_li.product_id;
  end if;

  if v_seller is null then
    raise exception 'seller_missing';
  end if;

  -- Criar shadow: authenticated (studio/checkout) ou service_role / callers DEFINER.

  v_img_json := case
    when v_li.photo_url is not null and trim(v_li.photo_url) <> ''
    then jsonb_build_array(trim(v_li.photo_url))
    else '[]'::jsonb
  end;
  v_img_text := case
    when v_li.photo_url is not null and trim(v_li.photo_url) <> ''
    then array[trim(v_li.photo_url)]
    else array[]::text[]
  end;

  select c.udt_name
  into v_image_urls_udt
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'products'
    and c.column_name = 'image_urls'
  limit 1;

  if v_image_urls_udt = '_text' then
    insert into public.products (
      seller_id, title, price, image_urls, ref_code,
      list_on_marketplace, available_for_live, quantity, is_sold
    )
    values (
      v_seller,
      coalesce(nullif(trim(v_li.title), ''), 'Artigo live'),
      coalesce(v_li.price, 0),
      v_img_text,
      coalesce(nullif(trim(v_li.ref_code), ''), 'LIVE-' || left(v_li.id::text, 8)),
      false,
      false,
      greatest(coalesce(v_li.quantity, 1), 1),
      false
    )
    returning id into v_pid;
  else
    insert into public.products (
      seller_id, title, price, image_urls, ref_code,
      list_on_marketplace, available_for_live, quantity, is_sold
    )
    values (
      v_seller,
      coalesce(nullif(trim(v_li.title), ''), 'Artigo live'),
      coalesce(v_li.price, 0),
      v_img_json,
      coalesce(nullif(trim(v_li.ref_code), ''), 'LIVE-' || left(v_li.id::text, 8)),
      false,
      false,
      greatest(coalesce(v_li.quantity, 1), 1),
      false
    )
    returning id into v_pid;
  end if;

  update public.live_items
  set checkout_product_id = v_pid, updated_at = now()
  where id = v_li.id;

  return v_pid;
end;
$$;

revoke all on function public.batata_ensure_checkout_product(uuid)
  from public, anon;
grant execute on function public.batata_ensure_checkout_product(uuid)
  to authenticated, service_role;

-- resolve continua autenticado (chama ensure internamente; ownership no ensure).
-- Comprador a chamar resolve noutro seller → ensure raise not_allowed.

-- ---------------------------------------------------------------------------
-- 4) stripe_convert — revoke anon (orphan GRANT)
-- ---------------------------------------------------------------------------
revoke all on function public.batata_live_reservation_stripe_convert(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.batata_live_reservation_stripe_convert(uuid, uuid)
  to service_role;

notify pgrst, 'reload schema';
