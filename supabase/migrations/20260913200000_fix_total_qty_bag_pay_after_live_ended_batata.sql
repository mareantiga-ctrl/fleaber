-- BATATA 2026-09-13 — total_qty bag pay after live ended (mirror stock exception)
-- See supabase/sql/fix_total_qty_bag_pay_after_live_ended_batata.sql

create or replace function public.batata_live_item_total_qty(p_live_item_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_qty integer;
  v_seller uuid;
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_staff boolean := false;
  v_buyer_bag boolean := false;
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return 0;
  end if;

  select coalesce(l.seller_id, l.vendedor_id) into v_seller
  from public.lives l where l.id = v_li.live_id;

  if v_uid is not null and v_seller is not null then
    v_staff := v_uid = v_seller
      or public.batata_staff_has_permission(v_seller, 'can_manage_chat');
  end if;

  if v_uid is not null then
    select exists (
      select 1
      from public.live_reservation_requests r
      where r.live_item_id = v_li.id
        and r.buyer_id = v_uid
        and r.status in ('pending', 'accepted')
    ) into v_buyer_bag;
  end if;

  if v_role is distinct from 'service_role'
     and not coalesce(v_staff, false)
     and not coalesce(v_buyer_bag, false) then
    if not public.batata_live_is_broadcasting(v_li.live_id) then
      return 0;
    end if;
  end if;

  if v_li.item_kind = 'marketplace_product' and v_li.product_id is not null then
    select p.quantity into v_qty from public.products p where p.id = v_li.product_id;
    if v_qty is null then return 0; end if;
    return greatest(v_qty, 0);
  end if;

  if v_li.item_kind = 'live_only' then
    if v_seller is not null then
      return public.batata_ref_history_pool_base_qty(
        v_seller, coalesce(v_li.logical_item_id, v_li.id)
      );
    end if;
  end if;

  return greatest(coalesce(v_li.quantity, 0), 0);
end;
$$;

revoke execute on function public.batata_live_item_total_qty(uuid) from anon;
grant execute on function public.batata_live_item_total_qty(uuid)
  to authenticated, service_role;

comment on function public.batata_live_item_total_qty(uuid) is
  'Qty total do live_item; comprador com reserva no saco vê qty após ended.';

notify pgrst, 'reload schema';
