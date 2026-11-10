-- Fleaber BATATA: stock efectivo no PDP marketplace quando o artigo está
-- num directo com hold de rifa / reservas / premio_rifa.
-- Bypass RLS em live_items (security definer) — o SELECT directo falhava
-- em alguns viewers e o detalhe mostrava products.quantity cru (ex. 2 em vez de 1).
--
-- Executar no SQL Editor staging DEPOIS de live_raffle_prize_stock_batata.sql
-- (precisa de batata_live_item_stock).

create or replace function public.batata_live_stock_for_product(p_product_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_best jsonb;
  v_snap jsonb;
  v_best_hold integer := -1;
  v_best_avail integer := 2147483647;
  v_hold integer;
  v_avail integer;
begin
  if p_product_id is null then
    return jsonb_build_object('ok', false, 'error', 'product_id_required');
  end if;

  for v_id in
    select li.id
    from public.live_items li
    join public.lives l on l.id = li.live_id
    where li.product_id = p_product_id
       or li.checkout_product_id = p_product_id
    order by
      case
        when lower(trim(coalesce(l.status, ''))) = 'live'
             and coalesce(l.is_active, true) then 0
        when lower(trim(coalesce(l.status, ''))) in ('ended', 'cancelled') then 2
        else 1
      end,
      li.created_at desc nulls last
    limit 40
  loop
    v_snap := public.batata_live_item_stock(v_id);
    if coalesce((v_snap->>'ok')::boolean, false) is not true then
      continue;
    end if;
    v_hold := coalesce((v_snap->>'raffle_hold_qty')::int, 0);
    v_avail := coalesce((v_snap->>'available_qty')::int, 0);
    if v_best is null
       or v_hold > v_best_hold
       or (v_hold = v_best_hold and v_avail < v_best_avail) then
      v_best := v_snap;
      v_best_hold := v_hold;
      v_best_avail := v_avail;
    end if;
  end loop;

  if v_best is null then
    return jsonb_build_object('ok', false, 'error', 'no_live_item_for_product');
  end if;
  return v_best;
end;
$$;

revoke all on function public.batata_live_stock_for_product(uuid) from public;
grant execute on function public.batata_live_stock_for_product(uuid) to authenticated, anon;
