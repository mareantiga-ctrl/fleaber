-- RTB-B-P1-01/02 — seller não fabrica order para buyer alheio sem proposta aceite
-- Preserva: buyer INSERT self; seller INSERT com product_offer aceite (accept oferta);
--           service_role / DEFINER (rifa, settle).
-- production_touched: false · fase4: false

create or replace function public.batata_orders_guard_buyer_attribution()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_is_seller boolean;
  v_ok boolean := false;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  if TG_OP is distinct from 'INSERT' then
    return NEW;
  end if;

  v_is_seller := NEW.seller_id is not null and NEW.seller_id = v_uid;

  -- Comprador cria a própria encomenda: OK
  if NEW.buyer_id is not null and NEW.buyer_id = v_uid then
    return NEW;
  end if;

  -- Seller JWT a atribuir buyer alheio: só com proposta aceite autoritativa
  if v_is_seller and NEW.buyer_id is not null and NEW.buyer_id is distinct from v_uid then
    if NEW.product_offer_id is not null then
      select exists (
        select 1
        from public.product_offers po
        where po.id = NEW.product_offer_id
          and po.seller_id = NEW.seller_id
          and po.buyer_id = NEW.buyer_id
          and po.product_id is not distinct from NEW.product_id
          and lower(trim(coalesce(po.status, ''))) = 'accepted'
          and po.responded_at is not null
          and (po.expires_at is null or po.expires_at > now())
          and not public.batata_product_offer_is_consumed(po.id, NEW.id)
      ) into v_ok;
    end if;

    if not v_ok then
      raise exception 'order_buyer_attribution_denied'
        using errcode = '42501';
    end if;
    return NEW;
  end if;

  -- Nem buyer nem seller da row (ou buyer_id null): bloquear JWT
  raise exception 'order_buyer_attribution_denied'
    using errcode = '42501';
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_buyer_attribution on public.orders;
create trigger trg_batata_orders_guard_buyer_attribution
  before insert on public.orders
  for each row
  execute function public.batata_orders_guard_buyer_attribution();

comment on function public.batata_orders_guard_buyer_attribution() is
  'RTB-B-P1-01: seller JWT só atribui buyer alheio com product_offers accepted; fecha ghost sale + review chain.';

notify pgrst, 'reload schema';
